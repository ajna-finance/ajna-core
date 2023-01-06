// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IERC20 }    from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import { IPool } from './base/interfaces/IPool.sol';
import { IPositionManager } from './base/interfaces/IPositionManager.sol';
import { PositionManager } from './base/PositionManager.sol';

import './libraries/Maths.sol';

import './IAjnaRewards.sol';

contract AjnaRewards is IAjnaRewards {

    using SafeERC20   for IERC20;

    /*****************/
    /*** Constants ***/
    /*****************/

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

    /***********************/
    /*** State Variables ***/
    /***********************/

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

    /******************/
    /*** Immutables ***/
    /******************/

    address          public immutable ajnaToken;       // address of the AJNA token
    IPositionManager public immutable positionManager; // The PositionManager contract

    struct RewardsLocalVars {
        uint256 bucketIndex;    // index of current bucket to calculate rewards for
        uint256 bucketRate;     // recorded exchange rate of current bucket
        uint256 epoch;          // current epoch to calculate rewards for
        uint256 nextEpoch;      // next epoch to calculate rewards for
        uint256 interestEarned; // interest earned on current epoch for the current bucket
        uint256 newRewards;     // calculated rewards
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
    function claimRewards(
        uint256 tokenId_,
        uint256 burnEpochToStartClaim_
    ) external {
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
        stake.owner    = msg.sender;
        stake.ajnaPool = ajnaPool;

        uint256 curBurnEpoch = IPool(ajnaPool).currentBurnEpoch();

        // record the staking epoch
        stake.stakingEpoch = uint96(curBurnEpoch);

        // initialize last time interaction at staking epoch
        stake.lastInteractionBurnEpoch = uint96(curBurnEpoch);

        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);
        for (uint256 i = 0; i < positionIndexes.length; ) {

            uint256 bucketId = positionIndexes[i];

            BucketState storage bucketState = stake.snapshot[bucketId];

            // record the number of lp tokens in bucket at the time of staking
            bucketState.lpsAtStakeTime = positionManager.getLPTokens(
                tokenId_,
                bucketId
            );
            // record the bucket exchange rate at the time of staking
            bucketState.rateAtStakeTime = IPool(ajnaPool).bucketExchangeRate(bucketId);

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }
        }

        emit StakeToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);

        // calculate rewards for updating exchange rates, if any
        uint256 updateReward = _updateBucketExchangeRates(
            ajnaPool,
            positionManager.getPositionIndexes(tokenId_)
        );

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

        emit UnstakeToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT from contract to sender
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @dev    Caller can claim 5% of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_    Address of the pool whose exchange rates are being updated.
     *  @param  indexes_ List of bucket indexes to be updated.
     */
    function updateBucketExchangeRatesAndClaim(
        address pool_,
        uint256[] calldata indexes_
    ) external returns (uint256 updateReward) {
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
     *  @return rewards_               Amount of rewards earned by the NFT.
     */
    function _calculateRewards(
        uint256 tokenId_,
        uint256 burnEpochToStartClaim_,
        bool isClaim_
    ) internal returns (uint256 rewards_) {

        address ajnaPool      = stakes[tokenId_].ajnaPool;
        uint256 lastBurnEpoch = stakes[tokenId_].lastInteractionBurnEpoch;
        uint256 stakingEpoch  = stakes[tokenId_].stakingEpoch;

        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);

        // calculate accrued interest as determined by the difference in exchange rates between the last interaction block and the current block
        for (uint256 i = 0; i < positionIndexes.length; ) {

            RewardsLocalVars memory vars;

            vars.bucketIndex = positionIndexes[i];

            BucketState memory bucketSnapshot = stakes[tokenId_].snapshot[vars.bucketIndex];

            // iterate through all burn periods to check exchange for buckets over time
            for (vars.epoch = lastBurnEpoch; vars.epoch < burnEpochToStartClaim_; ) {
                vars.nextEpoch = vars.epoch + 1;

                if (vars.epoch != stakingEpoch) {

                    // if staked in a previous epoch then use the initial exchange rate of epoch
                    vars.bucketRate = poolBucketBurnExchangeRates[ajnaPool][vars.bucketIndex][vars.epoch];
                } else {

                    // if staked during the epoch then use the bucket rate at the time of staking
                    vars.bucketRate = bucketSnapshot.rateAtStakeTime;
                }

                // calculate the amount of interest accrued in current epoch
                vars.interestEarned = _calculateExchangeRateInterestEarned(
                    ajnaPool,
                    vars.nextEpoch,
                    vars.bucketIndex,
                    bucketSnapshot.lpsAtStakeTime,
                    vars.bucketRate
                );

                // calculate and accumulate rewards if interest earned
                if (vars.interestEarned != 0) {

                    vars.newRewards = _calculateNewRewards(
                        ajnaPool,
                        vars.interestEarned,
                        vars.nextEpoch,
                        vars.epoch
                    );

                    // accumulate additional rewards earned for this period
                    rewards_ += vars.newRewards;

                    if (isClaim_) {
                        // update token claim trackers
                        burnEventRewardsClaimed[vars.nextEpoch] += vars.newRewards;
                        hasClaimedForToken[tokenId_][vars.nextEpoch] = true;
                    }
                }

                // epoch is bounded by the number of reserve auctions that have occured in the pool, preventing overflow / underflow
                unchecked { ++vars.epoch; }
            }

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }

        }
    }

    /**
     *  @notice Calculate the amount of interest that has accrued to a lender in a bucket based upon their LPs.
     *  @param  pool_           Address of the pool whose exchange rates are being checked.
     *  @param  nextEventEpoch_ The next event epoch to check the exchange rate for.
     *  @param  bucketIndex_    Index of the bucket to check the exchange rate for.
     *  @param  bucketLPs       Amount of LPs in bucket.
     *  @param  exchangeRate_   Exchange rate in current epoch.
     *  @return interestEarned_ The amount of interest accrued.
     */
    function _calculateExchangeRateInterestEarned(
        address pool_,
        uint256 nextEventEpoch_,
        uint256 bucketIndex_,
        uint256 bucketLPs,
        uint256 exchangeRate_
    ) internal view returns (uint256 interestEarned_) {

        if (exchangeRate_ != 0) {

            uint256 nextExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][nextEventEpoch_];

            // calculate interest earned only if next exchange rate is higher than current exchange rate
            if (nextExchangeRate > exchangeRate_) {

                // calculate the equivalent amount of quote tokens given the stakes lp balance,
                // and the exchange rate at the next and current burn events
                interestEarned_ = Maths.rayToWad(Maths.rmul(nextExchangeRate - exchangeRate_, bucketLPs));
            }

        }
    }

    /**
     *  @notice Calculate new rewards between current and next epoch, based on earned interest.
     *  @param  ajnaPool_       Address of the pool.
     *  @param  interestEarned_ The amount of interest accrued to current epoch.
     *  @param  nextEpoch_      The next burn event epoch to calculate new rewards.
     *  @param  epoch_          The current burn event epoch to calculate new rewards.
     *  @return newRewards_     New rewards between current and next burn event epoch.
     */
    function _calculateNewRewards(
        address ajnaPool_,
        uint256 interestEarned_,
        uint256 nextEpoch_,
        uint256 epoch_
    ) internal view returns (uint256 newRewards_) {

        (
            ,
            // total interest accumulated by the pool over the claim period
            uint256 totalBurnedInPeriod,
            // total tokens burned over the claim period
            uint256 totalInterestEarnedInPeriod
        ) = _getPoolAccumulators(ajnaPool_, nextEpoch_, epoch_);

        // calculate rewards earned
        newRewards_ = Maths.wmul(
            REWARD_FACTOR,
            Maths.wmul(
                Maths.wdiv(interestEarned_, totalInterestEarnedInPeriod), totalBurnedInPeriod
            )
        );

        uint256 rewardsCapped  = Maths.wmul(REWARD_CAP, totalBurnedInPeriod);
        uint256 rewardsClaimed = burnEventRewardsClaimed[nextEpoch_];

        // Check rewards claimed - check that less than 80% of the tokens for a given burn event have been claimed.
        if (rewardsClaimed + newRewards_ > rewardsCapped) {

            // set claim reward to difference between cap and reward
            newRewards_ = rewardsCapped - rewardsClaimed;
        }
    }

    /**
     *  @notice Claim rewards that have been accumulated by a staked NFT.
     *  @param  tokenId_               ID of the staked LP NFT.
     *  @param  burnEpochToStartClaim_ The burn period from which to start the calculations, decrementing down.
     */
    function _claimRewards(
        uint256 tokenId_,
        uint256 burnEpochToStartClaim_
    ) internal {

        Stake storage stake = stakes[tokenId_];
        address ajnaPool = stake.ajnaPool;

        // update bucket exchange rates and claim associated rewards
        uint256 rewardsEarned = _updateBucketExchangeRates(
            ajnaPool,
            positionManager.getPositionIndexes(tokenId_)
        );

        rewardsEarned += _calculateRewards(tokenId_, burnEpochToStartClaim_, true); 

        uint256[] memory burnEpochsClaimed = _getBurnEpochsClaimed(
            stake.lastInteractionBurnEpoch,
            burnEpochToStartClaim_
        );

        emit ClaimRewards(
            msg.sender,
            ajnaPool,
            tokenId_,
            burnEpochsClaimed,
            rewardsEarned
        );

        // update last interaction burn event
        stake.lastInteractionBurnEpoch = uint96(burnEpochToStartClaim_);

        uint256 ajnaBalance = IERC20(ajnaToken).balanceOf(address(this));

        if (rewardsEarned > ajnaBalance) rewardsEarned = ajnaBalance;

        // transfer rewards to sender
        IERC20(ajnaToken).safeTransfer(msg.sender, rewardsEarned);
    }

    /**
     *  @notice Retrieve an array of burn epochs from which a depositor has claimed rewards.
     *  @param  lastInteractionBurnEpoch_ The last burn period in which a depositor interacted with the rewards contract.
     *  @param  burnEpochToStartClaim_    The most recent burn period from a depostor earned rewards.
     *  @return burnEpochsClaimed_        Array of burn epochs from which a depositor has claimed rewards.
     */
    function _getBurnEpochsClaimed(
        uint256 lastInteractionBurnEpoch_,
        uint256 burnEpochToStartClaim_
    ) internal pure returns (uint256[] memory burnEpochsClaimed_) {
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
     *  @return Timestamp of the latest burn event.
     *  @return Total ajna tokens burned by the pool since the last burn event.
     *  @return Total interest earned by the pool since the last burn event.
     */
    function _getPoolAccumulators(
        address pool_,
        uint256 currentBurnEventEpoch_,
        uint256 lastBurnEventEpoch_
    ) internal view returns (uint256, uint256, uint256) {
        (
            uint256 currentBurnTime,
            uint256 totalInterestLatest,
            uint256 totalBurnedLatest
        ) = IPool(pool_).burnInfo(currentBurnEventEpoch_);

        (
            ,
            uint256 totalInterestAtBlock,
            uint256 totalBurnedAtBlock
        ) = IPool(pool_).burnInfo(lastBurnEventEpoch_);

        uint256 totalBurned   = totalBurnedLatest   != 0 ? totalBurnedLatest   - totalBurnedAtBlock   : totalBurnedAtBlock;
        uint256 totalInterest = totalInterestLatest != 0 ? totalInterestLatest - totalInterestAtBlock : totalInterestAtBlock;

        return (
            currentBurnTime,
            totalBurned,
            totalInterest
        );

    }

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @dev    Called as part of stakeToken, unstakeToken, and claimRewards, as well as updateBucketExchangeRatesAndClaim.
     *  @dev    Caller can claim 5% of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_    Address of the pool whose exchange rates are being updated.
     *  @param  indexes_ List of bucket indexes to be updated.
     */
    function _updateBucketExchangeRates(
        address pool_,
        uint256[] memory indexes_
    ) internal returns (uint256 updatedRewards_) {
        // get the current burn epoch from the given pool
        uint256 curBurnEpoch = IPool(pool_).currentBurnEpoch();

        // update exchange rates only if the pool has not yet burned any tokens without calculating any reward
        if (curBurnEpoch == 0) {
            for (uint256 i = 0; i < indexes_.length; ) {

                _updateBucketExchangeRate(
                    pool_,
                    indexes_[i],
                    curBurnEpoch
                );

                // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                unchecked { ++i; }
            }
        }

        else {
            // retrieve accumulator values used to calculate rewards accrued
            (
                uint256 curBurnTime,
                uint256 totalBurned,
                uint256 totalInterestEarned
            ) = _getPoolAccumulators(pool_, curBurnEpoch, curBurnEpoch - 1);

            if (block.timestamp <= curBurnTime + UPDATE_PERIOD) {

                // update exchange rates and calculate rewards if tokens were burned and within allowed time period
                for (uint256 i = 0; i < indexes_.length; ) {

                    // calculate rewards earned for updating bucket exchange rate
                    updatedRewards_ += _updateBucketExchangeRateAndCalculateRewards(
                        pool_,
                        indexes_[i],
                        curBurnEpoch,
                        totalBurned,
                        totalInterestEarned
                    );

                    // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
                    unchecked { ++i; }
                }

                uint256 rewardsCap     = Maths.wmul(UPDATE_CAP, totalBurned);
                uint256 rewardsClaimed = burnEventUpdateRewardsClaimed[curBurnEpoch];

                // update total tokens claimed for updating bucket exchange rates tracker
                if (rewardsClaimed + updatedRewards_ >= rewardsCap) {
                    // if update reward is greater than cap, set to remaining difference
                    updatedRewards_ = rewardsCap - rewardsClaimed;
                }

                // accumulate the full amount of additional rewards
                burnEventUpdateRewardsClaimed[curBurnEpoch] += updatedRewards_;
            }
        }

        // emit event with the list of bucket indexes updated
        emit UpdateExchangeRates(msg.sender, pool_, indexes_, updatedRewards_);
    }

    /**
     *  @notice Update the exchange rate of a specific bucket.
     *  @param  pool_        Address of the pool whose exchange rates are being updated.
     *  @param  bucketIndex_ Bucket index to update exchange rate.
     *  @param  burnEpoch_   Current burn epoch of the pool.
     */
    function _updateBucketExchangeRate(
        address pool_,
        uint256 bucketIndex_,
        uint256 burnEpoch_
    ) internal {
        uint256 burnExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEpoch_];

        // update bucket exchange rate at epoch only if it wasn't previously updated
        if (burnExchangeRate == 0) {
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(bucketIndex_);

            // record bucket exchange rate at epoch
            poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEpoch_] = curBucketExchangeRate;
        }
    }

    /**
     *  @notice Update the exchange rate of a specific bucket and calculate rewards based on prev exchange rate.
     *  @param  pool_           Address of the pool whose exchange rates are being updated.
     *  @param  bucketIndex_    Bucket index to update exchange rate.
     *  @param  burnEpoch_      Current burn epoch of the pool.
     *  @param  totalBurned_    Total Ajna tokens burned in pool.
     *  @param  interestEarned_ Total interest rate earned in pool.
     */
    function _updateBucketExchangeRateAndCalculateRewards(
        address pool_,
        uint256 bucketIndex_,
        uint256 burnEpoch_,
        uint256 totalBurned_,
        uint256 interestEarned_
    ) internal returns (uint256 rewards_) {
        uint256 burnExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEpoch_];

        // update bucket exchange rate at epoch only if it wasn't previously updated
        if (burnExchangeRate == 0) {
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(bucketIndex_);

            // record bucket exchange rate at epoch
            poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEpoch_] = curBucketExchangeRate;

            // retrieve the bucket exchange rate at the previous epoch
            uint256 prevBucketExchangeRate = poolBucketBurnExchangeRates[pool_][bucketIndex_][burnEpoch_ - 1];

            // skip reward calculation if update at the previous epoch was missed
            // prevents excess rewards from being provided from using a 0 value as an input to the interestFactor calculation below.
            if (prevBucketExchangeRate != 0) {

                // retrieve current deposit of the bucket
                (, , , uint256 bucketDeposit, ) = IPool(pool_).bucketInfo(bucketIndex_);

                uint256 burnFactor     = Maths.wmul(totalBurned_, bucketDeposit);
                uint256 interestFactor = Maths.wdiv(
                    Maths.WAD - Maths.wdiv(prevBucketExchangeRate, curBucketExchangeRate),
                    interestEarned_
                );

                // calculate rewards earned for updating bucket exchange rate 
                rewards_ += Maths.wmul(UPDATE_CLAIM_REWARD, Maths.wmul(burnFactor, interestFactor));
            }
        }
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
    function calculateRewards(
        uint256 tokenId_,
        uint256 burnEpochToStartClaim_
    ) external returns (uint256 rewards_) {
        rewards_ = _calculateRewards(tokenId_, burnEpochToStartClaim_, false);
    }

    /**
     *  @notice Retrieve information about a given stake.
     *  @param  tokenId_  ID of the NFT staked in the rewards contract to retrieve information about.
     *  @return The owner of a given NFT stake.
     *  @return The Pool the NFT represents positions in.
     *  @return The last burn epoch in which the owner of the NFT interacted with the rewards contract.
     */
    function getDepositInfo(
        uint256 tokenId_
    ) external view returns (address, address, uint256) {
        return (
            stakes[tokenId_].owner,
            stakes[tokenId_].ajnaPool,
            stakes[tokenId_].lastInteractionBurnEpoch);
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
