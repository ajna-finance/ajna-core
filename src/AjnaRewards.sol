// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IERC20 }    from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import { IPool } from './base/interfaces/IPool.sol';
import { IPositionManager } from './base/interfaces/IPositionManager.sol';
import { PositionManager } from './base/PositionManager.sol';

import './libraries/Maths.sol';

import { PoolCommons } from './libraries/external/PoolCommons.sol';

import './IAjnaRewards.sol';

contract AjnaRewards is IAjnaRewards {

    using SafeERC20   for IERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    address public immutable ajnaToken; // address of the AJNA token

    IPositionManager public immutable positionManager; // The PositionManager contract

    /**
     * @notice Maximum percentage of tokens burned that can be claimed as Ajna token lp nft rewards.
     */
    uint256 internal constant REWARD_CAP = 0.8 * 1e18;

    /**
     * @notice Maximum percentage of tokens burned that can be claimed as Ajna token update rewards.
     */
    uint256 internal constant UPDATE_CAP = 0.1 * 1e18;

    /**
     * @notice Reward factor by which to scale the total rewards earned.
     * @dev ensures that rewards issued to staked lenders in a given pool are less than the ajna tokens burned in that pool.
     */
    uint256 internal constant REWARD_FACTOR = 0.5 * 1e18;

    /**
     * @notice Reward factor by which to scale rewards earned for updating a buckets exchange rate.
     */
    uint256 internal UPDATE_CLAIM_REWARD = 0.05 * 1e18;

    /**
     * @notice Time period after a burn event in which buckets exchange rates can be updated.
     */
    uint256 internal constant UPDATE_PERIOD = 2 weeks;

    /**
     * @notice Track whether a depositor has claimed rewards for a given burn event.
     * @dev tokenID => burnEvent => has claimed
     */
    mapping(uint256 => mapping(uint256 => bool)) public hasClaimedForToken;
    /**
     * @notice Track the total amount of rewards that have been claimed for a given burn event.
     * @dev burnEvent => tokens claimed
     */
    mapping(uint256 => uint256) public burnEventRewardsClaimed;

    /**
     * @notice Track the total amount of rewards that have been claimed for a given burn event's bucket updates.
     * @dev burnEvent => tokens claimed
     */
    mapping(uint256 => uint256) public burnEventUpdateRewardsClaimed;

    /**
     * @notice Mapping of LP NFTs staked in the Ajna Rewards contract.
     * @dev tokenID => Stake
     */
    mapping(uint256 => Stake) public stakes;

    /**
     * @notice Mapping of per pool bucket exchange rates at a given burn event.
     * @dev poolAddress => bucketIndex => burnEventId => bucket exchange rate
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal poolBucketBurnExchangeRates;

    struct Stake {
        address owner;                            // owner of the LP NFT
        address ajnaPool;                         // address of the Ajna pool the NFT corresponds to
        uint256 lastInteractionBurnEpoch;         // last burn event the stake interacted with the rewards contract
        mapping(uint256 => uint256) lpsAtDeposit; // the LP NFT's balance in each bucket at the time of staking
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(address ajnaToken_, IPositionManager positionManager_) {
        ajnaToken = ajnaToken_;
        positionManager = positionManager_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Claim ajna token rewards that have accrued to a staked LP NFT.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function claimRewards(uint256 tokenId_, uint256 burnEpochToStartClaim_) external {
        if (msg.sender != stakes[tokenId_].owner) revert NotOwnerOfDeposit();

        if (hasClaimedForToken[tokenId_][burnEpochToStartClaim_]) revert AlreadyClaimed();

        _claimRewards(tokenId_, burnEpochToStartClaim_);
    }

    /**
     *  @notice Stake a LP NFT into the rewards contract.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId_ ID of the LP NFT to stake in the AjnaRewards contract.
     */
    function stakeToken(uint256 tokenId_) external {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfDeposit();

        Stake storage stake = stakes[tokenId_];
        stake.owner = msg.sender;
        stake.ajnaPool = ajnaPool;
        // record the burnId at which the staking occurs
        uint256 curBurnEpoch = IPool(ajnaPool).currentBurnEpoch();
        stake.lastInteractionBurnEpoch = curBurnEpoch;

        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);
        for (uint256 i = 0; i < positionIndexes.length; ) {
            // record the number of lp tokens in each bucket the NFT is in
            stake.lpsAtDeposit[positionIndexes[i]] = positionManager.getLPTokens(tokenId_, positionIndexes[i]);

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }
        }

        emit StakeToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);

        // calculate rewards for updating exchange rates, if any
        uint256 updateReward = _updateBucketExchangeRates(stake.ajnaPool, positionManager.getPositionIndexes(tokenId_));
        // transfer rewards to sender
        IERC20(ajnaToken).safeTransfer(msg.sender, updateReward);
    }

    /**
     *  @notice Withdraw a staked LP NFT from the rewards contract.
     *  @dev    If rewards are available, claim all available rewards before withdrawal.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function unstakeToken(uint256 tokenId_) external {
        if (msg.sender != stakes[tokenId_].owner) revert NotOwnerOfDeposit();

        address ajnaPool = stakes[tokenId_].ajnaPool;

        // claim rewards, if any
        _claimRewards(tokenId_, IPool(ajnaPool).currentBurnEpoch());

        delete stakes[tokenId_];

        // transfer LP NFT from contract to sender
        emit UnstakeToken(msg.sender, ajnaPool, tokenId_);
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @dev    Caller can claim 5% of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_    Address of the pool whose exchange rates are being updated.
     *  @param  indexes_ List of bucket indexes to be updated.
     */
    function updateBucketExchangeRatesAndClaim(address pool_, uint256[] calldata indexes_) external returns (uint256 updateReward) {
        updateReward = _updateBucketExchangeRates(pool_, indexes_);

        // transfer rewards to sender
        IERC20(ajnaToken).safeTransfer(msg.sender, updateReward);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked NFT.
     *  @dev    Rewards are calculated as the difference in exchange rates between the last interaction burn event and the current burn event.
     *  @param  tokenId_               ID of the staked LP NFT.
     *  @param  burnEpochToStartClaim_ The burn period from which to start the calculations, decrementing down.
     *  @param  isClaim_               Boolean checking whether the newly calculated rewards should be written to state as part of a claim.
     *  @return rewards_ Amount of rewards earned by the NFT.
     */
    function _calculateRewards(uint256 tokenId_, uint256 burnEpochToStartClaim_, bool isClaim_) internal returns (uint256 rewards_) {
        Stake storage stake = stakes[tokenId_];
        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);

        // calculate accrued interest as determined by the difference in exchange rates between the last interaction block and the current block
        for (uint256 i = 0; i < positionIndexes.length; ) {

            // iterate through all burn periods to check exchange for buckets over time
            for (uint256 epoch = stake.lastInteractionBurnEpoch; epoch < burnEpochToStartClaim_; ) {
                uint256 nextEpoch = epoch + 1;

                // calculate change in exchange rates in a stakes buckets
                uint256 interestEarned = _calculateExchangeRateInterestEarned(stake.ajnaPool, epoch, positionIndexes[i], stake);

                if (interestEarned == 0) {
                    // epoch is bounded by the number of reserve auctions that have occured in the pool, preventing overflow / underflow
                    unchecked { ++epoch; }

                    // no interest will be earned in this period, continue onto the next period
                    continue;
                }

                // retrieve total interest accumulated by the pool over the claim period, and total tokens burned over that period
                (, uint256 totalBurnedInPeriod, uint256 totalInterestEarnedInPeriod) = _getPoolAccumulators(stake.ajnaPool, nextEpoch, epoch);

                // calculate rewards earned
                uint256 newRewards = Maths.wmul(REWARD_FACTOR, Maths.wmul(Maths.wdiv(interestEarned, totalInterestEarnedInPeriod), totalBurnedInPeriod));

                if (_checkRewardsClaimed(nextEpoch, newRewards, totalBurnedInPeriod)) {
                    // set claim reward to difference between cap and reward
                    newRewards = Maths.wmul(REWARD_CAP, totalBurnedInPeriod) - burnEventRewardsClaimed[nextEpoch];
                    rewards_ += newRewards;
                }
                else {
                    // accumulate additional rewards earned for this period
                    rewards_ += newRewards;
                }

                if (isClaim_) {
                    // update token claim trackers
                    burnEventRewardsClaimed[nextEpoch] += newRewards;
                    hasClaimedForToken[tokenId_][nextEpoch] = true;
                }

                // epoch is bounded by the number of reserve auctions that have occured in the pool, preventing overflow / underflow
                unchecked { ++epoch; }
            }

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }

        }
    }

    /**
     *  @notice Calculate the amount of interest that has accrued to a lender in a bucket based upon their LPs.
     *  @param  pool_           Address of the pool whose exchange rates are being checked.
     *  @param  burnEventEpoch_ The burn event to check the exchange rate for.
     *  @param  bucketIndex_    Index of the bucket to check the exchange rate for.
     *  @param  deposit_        Stake struct of the NFT.
     *  @return interestEarned_ The amount of interest accrued.
     */
    function _calculateExchangeRateInterestEarned(address pool_, uint256 burnEventEpoch_, uint256 bucketIndex_, Stake storage deposit_) internal view returns (uint256 interestEarned_) {
        uint256 prevExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEventEpoch_];
        uint256 currentExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEventEpoch_ + 1];
        uint256 lpsInBucket = deposit_.lpsAtDeposit[bucketIndex_];

        if (prevExchangeRate == 0 || currentExchangeRate == 0) {
            return 0;
        }

        // calculate the equivalent amount of quote tokens given the stakes lp balance,
        // and the exchange rate at the previous and current burn events
        uint256 quoteAtPrev = Maths.rayToWad(Maths.rmul(prevExchangeRate, lpsInBucket));
        uint256 quoteAtCurrentRate = Maths.rayToWad(Maths.rmul(currentExchangeRate, lpsInBucket));

        if (quoteAtCurrentRate > quoteAtPrev) {
            interestEarned_ = quoteAtCurrentRate - quoteAtPrev;
        } else {
            interestEarned_ = quoteAtPrev - quoteAtCurrentRate;
        }
    }

    /**
     *  @notice Check that less than 80% of the tokens for a given burn event have been claimed.
     *  @param  burnEventEpoch_ ID of the burn event to check claims against.
     *  @param  rewardsEarned_ Amount of rewards earned by the NFT.
     *  @param  totalBurned_ Total amount of AJNA burned in the pool since the NFT's last interaction burn event.
     *  @return True if the rewards earned by the NFT would exceed the cap, false otherwise.
     */
    function _checkRewardsClaimed(uint256 burnEventEpoch_, uint256 rewardsEarned_, uint256 totalBurned_) internal view returns (bool) {
        return burnEventRewardsClaimed[burnEventEpoch_] + rewardsEarned_ > Maths.wmul(REWARD_CAP, totalBurned_);
    }

    /**
     *  @notice Claim rewards that have been accumulated by a staked NFT.
     *  @param  tokenId_               ID of the staked LP NFT.
     *  @param  burnEpochToStartClaim_ The burn period from which to start the calculations, decrementing down.
     */
    function _claimRewards(uint256 tokenId_, uint256 burnEpochToStartClaim_) internal {
        uint256 rewardsEarned = _calculateRewards(tokenId_, burnEpochToStartClaim_, true);
        Stake storage stake = stakes[tokenId_];

        emit ClaimRewards(msg.sender, stake.ajnaPool, tokenId_, _getBurnEpochsClaimed(stake.lastInteractionBurnEpoch, burnEpochToStartClaim_), rewardsEarned);

        // update last interaction burn event
        stake.lastInteractionBurnEpoch = burnEpochToStartClaim_;

        // update bucket exchange rates and claim associated rewards
        rewardsEarned += _updateBucketExchangeRates(stake.ajnaPool, positionManager.getPositionIndexes(tokenId_));

        // transfer rewards to sender
        if (rewardsEarned > IERC20(ajnaToken).balanceOf(address(this))) rewardsEarned = IERC20(ajnaToken).balanceOf(address(this));
        IERC20(ajnaToken).safeTransfer(msg.sender, rewardsEarned);
    }

    /**
     *  @notice Retrieve an array of burn epochs from which a depositor has claimed rewards.
     *  @param  lastInteractionBurnEpoch_ The last burn period in which a depositor interacted with the rewards contract.
     *  @param  burnEpochToStartClaim_    The most recent burn period from a depostor earned rewards.
     *  @return burnEpochsClaimed_   Array of burn epochs from which a depositor has claimed rewards.
     */
    function _getBurnEpochsClaimed(uint256 lastInteractionBurnEpoch_, uint256 burnEpochToStartClaim_) internal pure returns (uint256[] memory burnEpochsClaimed_) {
        uint256 numEpochsClaimed = burnEpochToStartClaim_ - lastInteractionBurnEpoch_;
        burnEpochsClaimed_ = new uint256[](numEpochsClaimed);

        uint256 i;
        uint256 claimEpoch = lastInteractionBurnEpoch_ + 1;
        while (claimEpoch <= burnEpochToStartClaim_) {
            burnEpochsClaimed_[i] = claimEpoch;

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
                ++claimEpoch;
            }
        }
    }

    /**
     *  @notice Retrieve the total ajna tokens burned and total interest earned by a pool since a given block.
     *  @param  pool_                  Address of the Ajna pool to retrieve accumulators of.
     *  @param  currentBurnEventEpoch_ The latest burn event.
     *  @param  lastBurnEventEpoch_    The burn event to use as checkpoint since which values have accumulated.
     *  @return currentBurnTime_       Timestamp of the latest burn event.
     *  @return ajnaTokensBurned_      Total ajna tokens burned by the pool since the last burn event.
     *  @return totalInterestEarned_   Total interest earned by the pool since the last burn event.
     */
    function _getPoolAccumulators(address pool_, uint256 currentBurnEventEpoch_, uint256 lastBurnEventEpoch_) internal view returns (uint256, uint256, uint256) {
        (uint256 currentBurnTime_, uint256 totalInterestLatest, uint256 totalBurnedLatest) = IPool(pool_).burnInfo(currentBurnEventEpoch_);
        (, uint256 totalInterestAtBlock, uint256 totalBurnedAtBlock) = IPool(pool_).burnInfo(lastBurnEventEpoch_);

        uint256 ajnaTokensBurned_    = totalBurnedLatest - totalBurnedAtBlock;
        uint256 totalInterestEarned_ = totalInterestLatest - totalInterestAtBlock;
        return (currentBurnTime_, ajnaTokensBurned_, totalInterestEarned_);
    }

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @dev    Called as part of stakeToken, unstakeToken, and claimRewards, as well as updateBucketExchangeRatesAndClaim.
     *  @dev    Caller can claim 5% of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_    Address of the pool whose exchange rates are being updated.
     *  @param  indexes_ List of bucket indexes to be updated.
     */
    function _updateBucketExchangeRates(address pool_, uint256[] memory indexes_) internal returns (uint256 updateReward_) {
        // get the current burn epoch from the given pool
        uint256 curBurnEpoch = IPool(pool_).currentBurnEpoch();

        // if the pool has not yet burned any tokens, return 0 after updating exchange rates
        if (curBurnEpoch == 0) {
            for (uint256 i = 0; i < indexes_.length; ) {
                // check bucket hasn't already been updated
                // if it has, skip to the next bucket
                if (poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnEpoch] != 0) {
                    // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                    unchecked { ++i; }
                    continue;
                }

                // record a buckets exchange rate
                uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(indexes_[i]);
                poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnEpoch] = curBucketExchangeRate;

                // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                unchecked { ++i; }
            }
            emit UpdateExchangeRates(msg.sender, pool_, indexes_, 0);
            // no rewards are available to claim before reserve auctions start
            return 0;
        }

        // retrieve accumulator values used to calculate rewards accrued
        (uint256 curBurnTime, uint256 totalBurned, uint256 totalInterestEarned) = _getPoolAccumulators(pool_, curBurnEpoch, curBurnEpoch - 1);

        // check that the update is being performed within the allowed time period
        // if it isn't, return 0
        if (block.timestamp > curBurnTime + UPDATE_PERIOD) {
            return 0;
        }

        for (uint256 i = 0; i < indexes_.length; ) {
            // check bucket hasn't already been updated
            // if it has, skip to the next bucket
            if (poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnEpoch] != 0) {
                // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                unchecked { ++i; }
                continue;
            }

            // record a buckets exchange rate
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(indexes_[i]);
            poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnEpoch] = curBucketExchangeRate;

            // retrieve the exchange rate of the previous burn event
            uint256 prevBucketExchangeRate = poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnEpoch - 1];

            // skip reward calculation for a bucket if the previous update was missed
            // prevents excess rewards from being provided from using a 0 value as an input to the interestFactor calculation below.
            if (prevBucketExchangeRate == 0) {
                // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                unchecked { ++i; }
                continue;
            }

            // retrieve current deposit in a bucket
            (, , , uint256 bucketDeposit, ) = IPool(pool_).bucketInfo(indexes_[i]);

            // calculate rewards earned for updating a bucket
            uint256 burnFactor     = Maths.wmul(totalBurned, bucketDeposit);
            uint256 interestFactor = Maths.wdiv(Maths.WAD - Maths.wdiv(prevBucketExchangeRate, curBucketExchangeRate), totalInterestEarned);
            updateReward_         += Maths.wmul(UPDATE_CLAIM_REWARD, Maths.wmul(burnFactor, interestFactor));

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }
        }

        // update total tokens claimed for updating exchange rates tracker
        if (burnEventUpdateRewardsClaimed[curBurnEpoch] + updateReward_ >= Maths.wmul(UPDATE_CAP, totalBurned)) {
            // if update reward is greater than cap, set to remaining difference
            updateReward_ = Maths.wmul(UPDATE_CAP, totalBurned) - burnEventUpdateRewardsClaimed[curBurnEpoch];
            burnEventUpdateRewardsClaimed[curBurnEpoch] += updateReward_;
        } else {
            // accumulate the full amount of additional rewards
            burnEventUpdateRewardsClaimed[curBurnEpoch] += updateReward_;
        }

        // emit event with the list of indexes updated
        // some of the indexes may have been previously updated
        emit UpdateExchangeRates(msg.sender, pool_, indexes_, updateReward_);
    }

    /*******************************/
    /*** External View Functions ***/
    /*******************************/

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked NFT.
     *  @param  tokenId_               ID of the staked LP NFT.
     *  @param  burnEpochToStartClaim_ The burn period from which to start the calculations, decrementing down.
     *  @return rewards_ The amount of rewards earned by the NFT.
     */
    function calculateRewards(uint256 tokenId_, uint256 burnEpochToStartClaim_) external returns (uint256 rewards_) {
        rewards_ = _calculateRewards(tokenId_, burnEpochToStartClaim_, false);
    }

    /**
     *  @notice Retrieve information about a given stake.
     *  @param  tokenId_  ID of the NFT staked in the rewards contract to retrieve information about.
     *  @return The owner of a given NFT stake.
     *  @return The Pool the NFT represents positions in.
     *  @return The last burn epoch in which the owner of the NFT interacted with the rewards contract.
     */
    function getDepositInfo(uint256 tokenId_) external view returns (address, address, uint256) {
        Stake storage stake = stakes[tokenId_];
        return (stake.owner, stake.ajnaPool, stake.lastInteractionBurnEpoch);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
