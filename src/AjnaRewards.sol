// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IERC20 }    from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Checkpoints.sol';

import { IPool } from './base/interfaces/IPool.sol';
import { IPositionManager } from './base/interfaces/IPositionManager.sol';
import { PositionManager } from './base/PositionManager.sol';

import './libraries/Maths.sol';

import { PoolCommons } from './libraries/external/PoolCommons.sol';

import './IAjnaRewards.sol';

import '@std/console.sol';

contract AjnaRewards is IAjnaRewards {

    using Checkpoints for Checkpoints.History;
    using SafeERC20   for IERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    address public immutable ajnaToken; // address of the AJNA token

    IPositionManager public immutable positionManager; // address of the PositionManager contract

    uint256 internal constant REWARD_CAP = 0.800000000000000000 * 1e18;
    uint256 internal constant UPDATE_CAP = 0.100000000000000000 * 1e18;

    /**
     * @notice Reward factor by which to scale the total rewards earned.
     * @dev ensures that rewards issued to staked lenders in a given pool are less than the ajna tokens burned in that pool.
     */
    uint256 internal constant REWARD_FACTOR = 0.500000000000000000 * 1e18;

    uint256 internal UPDATE_CLAIM_REWARD = 0.050000000000000000 * 1e18;

    /**
     * @notice Number of blocks after a burn event in which buckets exchange rates can be updated.
     */
    uint256 internal constant UPDATE_PERIOD = 100800;

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
     * @dev tokenID => Deposit
     */
    mapping(uint256 => Deposit) public deposits;

    /**
     * @notice Mapping of per pool bucket exchange rates at a given burn event.
     * @dev poolAddress => bucketIndex => burnEventId => bucket exchange rate
     */
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal poolBucketBurnExchangeRates;

    struct Deposit {
        address owner;                            // owner of the LP NFT
        address ajnaPool;                         // address of the Ajna pool the NFT corresponds to
        uint256 lastInteractionBurn;              // last burn event the deposit interacted with the rewards contract
        mapping(uint256 => uint256) lpsAtDeposit; // total pool deposits in each of the buckets a position is in
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
     *  @notice Deposit a LP NFT into the rewards contract.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId_ ID of the LP NFT to stake in the AjnaRewards contract.
     */
    function depositNFT(uint256 tokenId_) external {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfToken();

        Deposit storage deposit = deposits[tokenId_];
        deposit.owner = msg.sender;
        deposit.ajnaPool = ajnaPool;
        // record the burnId at which the deposit occurs
        uint256 curBurnId = IPool(ajnaPool).currentBurnId();
        deposit.lastInteractionBurn = curBurnId;

        // update the exchange rate for each bucket the NFT is in
        uint256[] memory positionIndexes = positionManager.getPositionPrices(tokenId_);
        for (uint256 i = 0; i < positionIndexes.length; ) {
            uint256 curBucketExchangeRate = IPool(ajnaPool).bucketExchangeRate(positionIndexes[i]);
            poolBucketBurnExchangeRates[ajnaPool][positionIndexes[i]][curBurnId] = curBucketExchangeRate;

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }

        // record the number of lp tokens in each bucket the NFT is in
        _setPositionLPs(tokenId_);

        emit DepositToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);
    }

    /**
     *  @notice Withdraw a staked LP NFT from the rewards contract.
     *  @dev    If rewards are available, claim all available rewards before withdrawal.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function withdrawNFT(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        address ajnaPool = deposits[tokenId_].ajnaPool;

        // claim rewards, if any
        _claimRewards(tokenId_);

        delete deposits[tokenId_];

        // transfer LP NFT from contract to sender
        emit WithdrawToken(msg.sender, ajnaPool, tokenId_);
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     *  @notice Claim ajna token rewards that have accrued to a staked LP NFT.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function claimRewards(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        _claimRewards(tokenId_);
    }

    // TODO: check we're only updating one block back
    function updateBucketExchangeRatesAndClaim(address pool_, uint256[] calldata indexes_) external {
        // check that the provided burn block is valid, and within the allowed time period
        uint256 curBurnId = IPool(pool_).currentBurnId();
        (uint256 curBurnBlock, uint256 curTotalInterest, uint256 curTotalBurned) = IPool(pool_).burnInfo(curBurnId);
        if (block.number > curBurnBlock + UPDATE_PERIOD) revert ExchangeRateUpdateTooLate();

        // TODO: use _getPoolAccumulators() to get the current accumulators
        // retrieve previous accumulator values to calculate rewards accrued
        (, uint256 prevTotalInterest, uint256 prevTotalBurned) = IPool(pool_).burnInfo(curBurnId - 1);

        uint256 updateReward;

        for (uint256 i = 0; i < indexes_.length; ) {
            // check bucket hasn't already been updated
            if (poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnId] != 0) revert ExchangeRateAlreadyUpdated();

            // record a buckets exchange rate for a given burn event
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(indexes_[i]);
            poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnId] = curBucketExchangeRate;

            // claim rewards that have accrued to a bucket
            uint256 prevBucketExchangeRate = poolBucketBurnExchangeRates[pool_][indexes_[i]][curBurnId - 1];

            (, , , uint256 bucketDeposit, ) = IPool(pool_).bucketInfo(indexes_[i]);

            // TODO: handle the case of interest earned being 0?
            // calculate rewards earned for updating a bucket
            uint256 burnFactor = Maths.wmul((curTotalBurned - prevTotalBurned), bucketDeposit);
            uint256 interestFactor = Maths.wdiv(Maths.WAD - Maths.wdiv(prevBucketExchangeRate, curBucketExchangeRate), (curTotalInterest - prevTotalInterest));
            updateReward += Maths.wmul(UPDATE_CLAIM_REWARD, Maths.wmul(burnFactor, interestFactor));

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }

        // check update reward accumulated is less than cap
        if (burnEventUpdateRewardsClaimed[curBurnId] + updateReward > Maths.wmul(UPDATE_CAP, (curTotalBurned - prevTotalBurned))) revert MaxTokensAlreadyClaimed();

        // update total tokens claimed tracker
        burnEventUpdateRewardsClaimed[curBurnId] += updateReward;

        // transfer rewards to sender
        emit UpdateExchangeRates(msg.sender, pool_, indexes_, updateReward);
        IERC20(ajnaToken).safeTransfer(msg.sender, updateReward);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    // check that less than 80% of the tokens for a given burn event have been claimed
    function _checkRewardsClaimed(uint256 burnEventId_, uint256 rewardsEarned_, uint256 totalBurned_) internal view returns (bool) {
        return burnEventRewardsClaimed[burnEventId_] + rewardsEarned_ > Maths.wmul(REWARD_CAP, totalBurned_);
    }

    function _claimRewards(uint256 tokenId_) internal {
        uint256 burnEventId   = IPool(deposits[tokenId_].ajnaPool).currentBurnId();
        (uint256 rewardsEarned, uint256 totalBurned) = _calculateRewardsEarned(tokenId_);

        if (_checkRewardsClaimed(burnEventId, rewardsEarned, totalBurned)) revert MaxTokensAlreadyClaimed();

        // update total tokens claimed tracker
        burnEventRewardsClaimed[burnEventId] += rewardsEarned;

        emit ClaimRewards(msg.sender, deposits[tokenId_].ajnaPool, tokenId_, rewardsEarned);

        // update last interaction burn event
        deposits[tokenId_].lastInteractionBurn = burnEventId;

        // transfer rewards to sender
        if (rewardsEarned > IERC20(ajnaToken).balanceOf(address(this))) rewardsEarned = IERC20(ajnaToken).balanceOf(address(this));
        IERC20(ajnaToken).safeTransfer(msg.sender, rewardsEarned);
    }

    function _calculateRewardsEarned(uint256 tokenId_) internal view returns (uint256 rewards_, uint256 totalBurned_) {
        Deposit storage deposit = deposits[tokenId_];
        uint256[] memory positionIndexes = positionManager.getPositionPrices(tokenId_); //TODO: rename this in position manager

        address ajnaPool = deposit.ajnaPool;
        uint256 interestEarned = 0;
        uint256 currentBurnEventId = IPool(ajnaPool).currentBurnId();
        uint256 lastInteractionBurnEvent = deposit.lastInteractionBurn;

        // calculate accrued interest as determined by the difference in exchange rates between the last interaction block and the current block
        for (uint256 i = 0; i < positionIndexes.length; ) {
            uint256 lastClaimedExchangeRate = poolBucketBurnExchangeRates[ajnaPool][positionIndexes[i]][lastInteractionBurnEvent];
            uint256 currentExchangeRate = poolBucketBurnExchangeRates[ajnaPool][positionIndexes[i]][currentBurnEventId];

            uint256 quoteAtLastClaimed = Maths.rayToWad(Maths.rmul(lastClaimedExchangeRate, deposit.lpsAtDeposit[positionIndexes[i]]));
            uint256 quoteAtCurrentRate = Maths.rayToWad(Maths.rmul(currentExchangeRate, deposit.lpsAtDeposit[positionIndexes[i]]));

            if (quoteAtCurrentRate > quoteAtLastClaimed) {
                interestEarned += quoteAtCurrentRate - quoteAtLastClaimed;
            }
            else {
                interestEarned -= quoteAtLastClaimed - quoteAtCurrentRate;
            }

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }

        // retrieve total interest accumulated by the pool over the claim period, and total tokens burned over that period
        uint256 totalInterestEarned;
        (totalBurned_, totalInterestEarned) = _getPoolAccumulators(ajnaPool, currentBurnEventId, lastInteractionBurnEvent);

        // calculate rewards earned
        // TODO: check this return
        if (totalInterestEarned == 0) return (0, totalBurned_);
        rewards_ = Maths.wmul(REWARD_FACTOR, Maths.wmul(Maths.wdiv(interestEarned, totalInterestEarned), totalBurned_));
    }

    /**
     *  @notice Retrieve the total ajna tokens burned and total interest earned by a pool since a given block.
     *  @param  pool_               Address of the Ajna pool to retrieve accumulators of.
     *  @param  currentBurnEventId_ ID of the latest burn event.
     *  @param  lastBurnEventId_    ID of the burn event to use as checkpoint since which values should have accumulated.
     */
    function _getPoolAccumulators(address pool_, uint256 currentBurnEventId_, uint256 lastBurnEventId_) internal view returns (uint256 ajnaTokensBurned_, uint256 totalInterestEarned_) {
        (, uint256 totalInterestLatest, uint256 totalBurnedLatest) = IPool(pool_).burnInfo(currentBurnEventId_);
        (, uint256 totalInterestAtBlock, uint256 totalBurnedAtBlock) = IPool(pool_).burnInfo(lastBurnEventId_);

        ajnaTokensBurned_ = totalBurnedLatest - totalBurnedAtBlock;
        totalInterestEarned_ = totalInterestLatest - totalInterestAtBlock;
    }

    function _setPositionLPs(uint256 tokenId_) internal {
        uint256[] memory positionIndexes = positionManager.getPositionPrices(tokenId_);

        for (uint256 i = 0; i < positionIndexes.length; ) {
            deposits[tokenId_].lpsAtDeposit[positionIndexes[i]] = positionManager.getLPTokens(tokenId_, positionIndexes[i]);

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function calculateRewardsEarned(uint256 tokenId_) external view returns (uint256 rewards_) {
        // TODO: update return value to return both of these?
        uint256 totalBurned_;
        (rewards_, totalBurned_) = _calculateRewardsEarned(tokenId_);
    }

    /**
     *  @notice Retrieve information about a given deposit.
     *  @param  tokenId_  ID of the NFT deposited into the rewards contract to retrieve information about.
     *  @return The owner of a given NFT deposit.
     *  @return The Pool the NFT represents positions in.
     *  @return The last block in which the owner of the NFT interacted with the rewards contract.
     */
    function getDepositInfo(uint256 tokenId_) external view returns (address, address, uint256) {
        Deposit storage deposit = deposits[tokenId_];
        return (deposit.owner, deposit.ajnaPool, deposit.lastInteractionBurn);
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
