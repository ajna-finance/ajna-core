// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IERC20 }          from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC721 }         from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { SafeERC20 }       from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { IPool }                        from './interfaces/pool/IPool.sol';
import { IPositionManager }             from './interfaces/position/IPositionManager.sol';
import { IPositionManagerOwnerActions } from './interfaces/position/IPositionManagerOwnerActions.sol';
import {
    IRewardsManager,
    IRewardsManagerOwnerActions,
    IRewardsManagerState,
    IRewardsManagerDerivedState
} from './interfaces/rewards/IRewardsManager.sol';
import { StakeInfo, BucketState } from './interfaces/rewards/IRewardsManagerState.sol';

import { PositionManager } from './PositionManager.sol';

import { Maths } from './libraries/internal/Maths.sol';

/**
 *  @title  Rewards (staking) Manager contract
 *  @notice Pool lenders can optionally mint `NFT` that represents their positions.
 *          The Rewards contract allows pool lenders with positions `NFT` to stake and earn `Ajna` tokens. 
 *          Lenders with `NFT`s can:
 *          - `stake` token
 *          - `update bucket exchange rate` and earn rewards
 *          - `claim` rewards
 *          - `unstake` token
 */
contract RewardsManager is IRewardsManager, ReentrancyGuard {

    using SafeERC20 for IERC20;

    /*****************/
    /*** Constants ***/
    /*****************/

    /**
     * @notice Maximum percentage of tokens burned that can be claimed as `Ajna` token `LP` `NFT` rewards.
     */
    uint256 internal constant REWARD_CAP = 0.8 * 1e18;
    /**
     * @notice Maximum percentage of tokens burned that can be claimed as `Ajna` token update rewards.
     */
    uint256 internal constant UPDATE_CAP = 0.1 * 1e18;
    /**
     * @notice Reward factor by which to scale the total rewards earned.
     * @dev ensures that rewards issued to staked lenders in a given pool are less than the `Ajna` tokens burned in that pool.
     */
    uint256 internal constant REWARD_FACTOR = 0.5 * 1e18;
    /**
     * @notice Reward factor by which to scale rewards earned for updating a buckets exchange rate.
     */
    uint256 internal constant UPDATE_CLAIM_REWARD = 0.05 * 1e18;
    /**
     * @notice Time period after a burn event in which buckets exchange rates can be updated.
     */
    uint256 internal constant UPDATE_PERIOD = 2 weeks;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev `tokenID => epoch => bool has claimed` mapping.
    mapping(uint256 => mapping(uint256 => bool)) public override isEpochClaimed;
    /// @dev `epoch => rewards claimed` mapping.
    mapping(uint256 => uint256) public override rewardsClaimed;
    /// @dev `epoch => update bucket rate rewards claimed` mapping.
    mapping(uint256 => uint256) public override updateRewardsClaimed;

    /// @dev Mapping of per pool bucket exchange rates at a given burn event `poolAddress => bucketIndex => epoch => bucket exchange rate`.
    mapping(address => mapping(uint256 => mapping(uint256 => uint256))) internal bucketExchangeRates;

    /// @dev Mapping `tokenID => Stake info`.
    mapping(uint256 => StakeInfo) internal stakes;

    /******************/
    /*** Immutables ***/
    /******************/

    /// @dev Address of the `Ajna` token.
    address public immutable ajnaToken;
    /// @dev The `PositionManager` contract
    IPositionManager public immutable positionManager;

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(address ajnaToken_, IPositionManager positionManager_) {
        if (ajnaToken_ == address(0)) revert DeployWithZeroAddress();

        ajnaToken = ajnaToken_;
        positionManager = positionManager_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @inheritdoc IRewardsManagerOwnerActions
     *  @dev    === Revert on ===
     *  @dev    not owner `NotOwnerOfDeposit()`
     *  @dev    already claimed `AlreadyClaimed()`
     *  @dev    === Emit events ===
     *  @dev    - `ClaimRewards`
     */
    function claimRewards(
        uint256 tokenId_,
        uint256 epochToClaim_
    ) external override {
        StakeInfo storage stakeInfo = stakes[tokenId_];

        if (msg.sender != stakeInfo.owner) revert NotOwnerOfDeposit();

        if (isEpochClaimed[tokenId_][epochToClaim_]) revert AlreadyClaimed();

        _claimRewards(stakeInfo, tokenId_, epochToClaim_, true, stakeInfo.ajnaPool);
    }

    /**
     *  @inheritdoc IRewardsManagerOwnerActions
     *  @dev    === Revert on ===
     *  @dev    not owner `NotOwnerOfDeposit()`
     *  @dev    invalid index params `MoveStakedLiquidityInvalid()`
     *  @dev    === Emit events ===
     *  @dev    - `MoveStakedLiquidity`
     */
    function moveStakedLiquidity(
        uint256 tokenId_,
        uint256[] memory fromBuckets_,
        uint256[] memory toBuckets_,
        uint256 expiry_
    ) external nonReentrant override {
        StakeInfo storage stakeInfo = stakes[tokenId_];

        if (msg.sender != stakeInfo.owner) revert NotOwnerOfDeposit();

        // check move array sizes match to be able to match on index
        uint256 fromBucketLength = fromBuckets_.length;
        if (fromBucketLength != toBuckets_.length) revert MoveStakedLiquidityInvalid();

        address ajnaPool = stakeInfo.ajnaPool;
        uint256 curBurnEpoch = IPool(ajnaPool).currentBurnEpoch();

        // claim rewards before moving liquidity, if any
        _claimRewards(
            stakeInfo,
            tokenId_,
            curBurnEpoch,
            false,
            ajnaPool
        );

        uint256 fromIndex;
        uint256 toIndex;
        for (uint256 i = 0; i < fromBucketLength; ) {
            fromIndex = fromBuckets_[i];
            toIndex = toBuckets_[i];

            // call out to position manager to move liquidity between buckets
            IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
                tokenId_,
                ajnaPool,
                fromIndex,
                toIndex,
                expiry_
            );
            positionManager.moveLiquidity(moveLiquidityParams);

            // update to bucket state
            BucketState storage toBucket = stakeInfo.snapshot[toIndex];
            toBucket.lpsAtStakeTime  = uint128(positionManager.getLP(tokenId_, toIndex));
            toBucket.rateAtStakeTime = uint128(IPool(ajnaPool).bucketExchangeRate(toIndex));
            delete stakeInfo.snapshot[fromIndex];

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }
        }

        emit MoveStakedLiquidity(tokenId_, fromBuckets_, toBuckets_);

        // update to bucket list exchange rates, from buckets are aready updated on claim
        // calculate rewards for updating exchange rates, if any
        uint256 updateReward = _updateBucketExchangeRates(
            ajnaPool,
            toBuckets_
        );

        // transfer rewards to sender
        _transferAjnaRewards(updateReward);
    }

    /**
     *  @inheritdoc IRewardsManagerOwnerActions
     *  @dev    === Revert on ===
     *  @dev    not owner `NotOwnerOfDeposit()`
     *  @dev    === Emit events ===
     *  @dev    - `Stake`
     */
    function stake(
        uint256 tokenId_
    ) external override {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfDeposit();

        StakeInfo storage stakeInfo = stakes[tokenId_];
        stakeInfo.owner    = msg.sender;
        stakeInfo.ajnaPool = ajnaPool;

        uint256 curBurnEpoch = IPool(ajnaPool).currentBurnEpoch();

        // record the staking epoch
        stakeInfo.stakingEpoch = uint96(curBurnEpoch);

        // initialize last time interaction at staking epoch
        stakeInfo.lastClaimedEpoch = uint96(curBurnEpoch);

        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);

        for (uint256 i = 0; i < positionIndexes.length; ) {

            uint256 bucketId = positionIndexes[i];

            BucketState storage bucketState = stakeInfo.snapshot[bucketId];

            // record the number of lps in bucket at the time of staking
            bucketState.lpsAtStakeTime = uint128(positionManager.getLP(
                tokenId_,
                bucketId
            ));
            // record the bucket exchange rate at the time of staking
            bucketState.rateAtStakeTime = uint128(IPool(ajnaPool).bucketExchangeRate(bucketId));

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked { ++i; }
        }

        emit Stake(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).transferFrom(msg.sender, address(this), tokenId_);

        // calculate rewards for updating exchange rates, if any
        uint256 updateReward = _updateBucketExchangeRates(
            ajnaPool,
            positionIndexes
        );

        // transfer rewards to sender
        _transferAjnaRewards(updateReward);
    }

    /**
     *  @inheritdoc IRewardsManagerOwnerActions
     *  @dev    === Revert on ===
     *  @dev    not owner `NotOwnerOfDeposit()`
     *  @dev    === Emit events ===
     *  @dev    - `ClaimRewards`
     *  @dev    - `Unstake`
     */
    function unstake(
        uint256 tokenId_
    ) external override {
        StakeInfo storage stakeInfo = stakes[tokenId_];

        if (msg.sender != stakeInfo.owner) revert NotOwnerOfDeposit();

        address ajnaPool = stakeInfo.ajnaPool;

        // claim rewards, if any
        _claimRewards(
            stakeInfo,
            tokenId_,
            IPool(ajnaPool).currentBurnEpoch(),
            false,
            ajnaPool
        );

        // remove bucket snapshots recorded at the time of staking
        uint256[] memory positionIndexes = positionManager.getPositionIndexes(tokenId_);
        for (uint256 i = 0; i < positionIndexes.length; ) {
            delete stakeInfo.snapshot[positionIndexes[i]]; // reset BucketState struct for current position

            unchecked { ++i; }
        }

        // remove recorded stake info
        delete stakes[tokenId_];

        emit Unstake(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT from contract to sender
        IERC721(address(positionManager)).transferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     *  @inheritdoc IRewardsManagerOwnerActions
     *  @dev    === Emit events ===
     *  @dev    - `UpdateExchangeRates`
     */
    function updateBucketExchangeRatesAndClaim(
        address pool_,
        uint256[] calldata indexes_
    ) external override returns (uint256 updateReward) {
        updateReward = _updateBucketExchangeRates(pool_, indexes_);

        // transfer rewards to sender
        _transferAjnaRewards(updateReward);
    }

    /*******************************/
    /*** External View Functions ***/
    /*******************************/

    /// @inheritdoc IRewardsManagerDerivedState
    function calculateRewards(
        uint256 tokenId_,
        uint256 epochToClaim_
    ) external view override returns (uint256 rewards_) {

        address ajnaPool         = stakes[tokenId_].ajnaPool;
        uint256 lastClaimedEpoch = stakes[tokenId_].lastClaimedEpoch;
        uint256 stakingEpoch     = stakes[tokenId_].stakingEpoch;

        uint256[] memory positionIndexes = positionManager.getPositionIndexesFiltered(tokenId_);

        // iterate through all burn periods to calculate and claim rewards
        for (uint256 epoch = lastClaimedEpoch; epoch < epochToClaim_; ) {

            rewards_ += _calculateNextEpochRewards(
                tokenId_,
                epoch,
                stakingEpoch,
                ajnaPool,
                positionIndexes
            );

            unchecked { ++epoch; }
        }
    }

    /// @inheritdoc IRewardsManagerState
    function getStakeInfo(
        uint256 tokenId_
    ) external view override returns (address, address, uint256) {
        return (
            stakes[tokenId_].owner,
            stakes[tokenId_].ajnaPool,
            stakes[tokenId_].lastClaimedEpoch
        );
    }

    /// @inheritdoc IRewardsManagerState
    function getBucketStateStakeInfo(
        uint256 tokenId_,
        uint256 bucketId_
    ) external view override returns (uint256, uint256) {
        return (
            stakes[tokenId_].snapshot[bucketId_].lpsAtStakeTime,
            stakes[tokenId_].snapshot[bucketId_].rateAtStakeTime
        );
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked `NFT`.
     *  @dev    Rewards are calculated as the difference in exchange rates between the last interaction burn event and the current burn event.
     *  @param  tokenId_      `ID` of the staked `LP` `NFT`.
     *  @param  epochToClaim_ The burn epoch to claim rewards for (rewards calculation starts from the last claimed epoch).
     *  @return rewards_      Amount of rewards earned by the `NFT`.
     */
    function _calculateAndClaimRewards(
        uint256 tokenId_,
        uint256 epochToClaim_
    ) internal returns (uint256 rewards_) {

        address ajnaPool         = stakes[tokenId_].ajnaPool;
        uint256 lastClaimedEpoch = stakes[tokenId_].lastClaimedEpoch;
        uint256 stakingEpoch     = stakes[tokenId_].stakingEpoch;

        uint256[] memory positionIndexes = positionManager.getPositionIndexesFiltered(tokenId_);

        // iterate through all burn periods to calculate and claim rewards
        for (uint256 epoch = lastClaimedEpoch; epoch < epochToClaim_; ) {

            uint256 nextEpochRewards = _calculateNextEpochRewards(
                tokenId_,
                epoch,
                stakingEpoch,
                ajnaPool,
                positionIndexes
            );

            rewards_ += nextEpochRewards;

            unchecked { ++epoch; }

            // update epoch token claim trackers
            rewardsClaimed[epoch]           += nextEpochRewards;
            isEpochClaimed[tokenId_][epoch] = true;
        }
    }

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked `NFT` in next epoch.
     *  @dev    Rewards are calculated as the difference in exchange rates between the last interaction burn event and the current burn event.
     *  @param  tokenId_         `ID` of the staked `LP` `NFT`.
     *  @param  epoch_           The current epoch.
     *  @param  stakingEpoch_    The epoch in which token was staked.
     *  @param  ajnaPool_        Address of the pool.
     *  @param  positionIndexes_ Bucket ids associated with `NFT` staked.
     *  @return epochRewards_    Calculated rewards in epoch.
     */
    function _calculateNextEpochRewards(
        uint256 tokenId_,
        uint256 epoch_,
        uint256 stakingEpoch_,
        address ajnaPool_,
        uint256[] memory positionIndexes_
    ) internal view returns (uint256 epochRewards_) {

        uint256 nextEpoch = epoch_ + 1;
        uint256 claimedRewardsInNextEpoch = rewardsClaimed[nextEpoch];
        uint256 bucketIndex;
        uint256 interestEarned;

        // iterate through all buckets and calculate epoch rewards for
        for (uint256 i = 0; i < positionIndexes_.length; ) {
            bucketIndex = positionIndexes_[i];
            BucketState memory bucketSnapshot = stakes[tokenId_].snapshot[bucketIndex];

            uint256 bucketRate;
            if (epoch_ != stakingEpoch_) {

                // if staked in a previous epoch then use the initial exchange rate of epoch
                bucketRate = bucketExchangeRates[ajnaPool_][bucketIndex][epoch_];
            } else {

                // if staked during the epoch then use the bucket rate at the time of staking
                bucketRate = bucketSnapshot.rateAtStakeTime;
            }

            // calculate the amount of interest accrued in current epoch
            interestEarned += _calculateExchangeRateInterestEarned(
                ajnaPool_,
                nextEpoch,
                bucketIndex,
                bucketSnapshot.lpsAtStakeTime,
                bucketRate
            ); 
            unchecked { ++i; }
        }

        // calculate and accumulate rewards if interest earned
        if (interestEarned != 0) {
            epochRewards_ = _calculateNewRewards(
                ajnaPool_,
                interestEarned,
                nextEpoch,
                epoch_,
                claimedRewardsInNextEpoch
            );
        }
    }

    /**
     *  @notice Calculate the amount of interest that has accrued to a lender in a bucket based upon their `LP`.
     *  @param  pool_           Address of the pool whose exchange rates are being checked.
     *  @param  nextEventEpoch_ The next event epoch to check the exchange rate for.
     *  @param  bucketIndex_    Index of the bucket to check the exchange rate for.
     *  @param  bucketLP_       Amount of `LP` in bucket.
     *  @param  exchangeRate_   Exchange rate in current epoch.
     *  @return interestEarned_ The amount of interest accrued.
     */
    function _calculateExchangeRateInterestEarned(
        address pool_,
        uint256 nextEventEpoch_,
        uint256 bucketIndex_,
        uint256 bucketLP_,
        uint256 exchangeRate_
    ) internal view returns (uint256 interestEarned_) {

        if (exchangeRate_ != 0) {

            uint256 nextExchangeRate = bucketExchangeRates[pool_][bucketIndex_][nextEventEpoch_];

            // calculate interest earned only if next exchange rate is higher than current exchange rate
            if (nextExchangeRate > exchangeRate_) {

                // calculate the equivalent amount of quote tokens given the stakes lp balance,
                // and the exchange rate at the next and current burn events
                interestEarned_ = Maths.wmul(nextExchangeRate - exchangeRate_, bucketLP_);
            }

        }
    }

    /**
     *  @notice Calculate new rewards between current and next epoch, based on earned interest.
     *  @param  ajnaPool_              Address of the pool.
     *  @param  interestEarned_        The amount of interest accrued to current epoch.
     *  @param  nextEpoch_             The next burn event epoch to calculate new rewards.
     *  @param  epoch_                 The current burn event epoch to calculate new rewards.
     *  @param  rewardsClaimedInEpoch_ Rewards claimed in epoch.
     *  @return newRewards_            New rewards between current and next burn event epoch.
     */
    function _calculateNewRewards(
        address ajnaPool_,
        uint256 interestEarned_,
        uint256 nextEpoch_,
        uint256 epoch_,
        uint256 rewardsClaimedInEpoch_
    ) internal view returns (uint256 newRewards_) {
        (
            ,
            // total interest accumulated by the pool over the claim period
            uint256 totalBurnedInPeriod,
            // total tokens burned over the claim period
            uint256 totalInterestEarnedInPeriod
        ) = _getPoolAccumulators(ajnaPool_, nextEpoch_, epoch_);

        // calculate rewards earned
        newRewards_ = totalInterestEarnedInPeriod == 0 ? 0 : Maths.wmul(
            REWARD_FACTOR,
            Maths.wdiv(
                Maths.wmul(interestEarned_, totalBurnedInPeriod),
                totalInterestEarnedInPeriod
            )
        );

        uint256 rewardsCapped = Maths.wmul(REWARD_CAP, totalBurnedInPeriod);

        // Check rewards claimed - check that less than 80% of the tokens for a given burn event have been claimed.
        if (rewardsClaimedInEpoch_ + newRewards_ > rewardsCapped) {

            // set claim reward to difference between cap and reward
            newRewards_ = rewardsCapped - rewardsClaimedInEpoch_;
        }
    }

    /**
     *  @notice Claim rewards that have been accumulated by a staked `NFT`.
     *  @param  stakeInfo_     `StakeInfo` struct containing details of stake to claim rewards for.
     *  @param  tokenId_       `ID` of the staked `LP` `NFT`.
     *  @param  epochToClaim_  The burn epoch to claim rewards for (rewards calculation starts from the last claimed epoch)
     *  @param  validateEpoch_ True if the epoch is received as a parameter and needs to be validated (lower or equal with latest epoch).
     *  @param  ajnaPool_      Address of `Ajna` pool associated with the stake.
     */
    function _claimRewards(
        StakeInfo storage stakeInfo_,
        uint256 tokenId_,
        uint256 epochToClaim_,
        bool validateEpoch_,
        address ajnaPool_
    ) internal {

        // revert if higher epoch to claim than current burn epoch
        if (validateEpoch_ && epochToClaim_ > IPool(ajnaPool_).currentBurnEpoch()) revert EpochNotAvailable();

        // update bucket exchange rates and claim associated rewards
        uint256 rewardsEarned = _updateBucketExchangeRates(
            ajnaPool_,
            positionManager.getPositionIndexes(tokenId_)
        );

        rewardsEarned += _calculateAndClaimRewards(tokenId_, epochToClaim_);

        uint256[] memory burnEpochsClaimed = _getBurnEpochsClaimed(
            stakeInfo_.lastClaimedEpoch,
            epochToClaim_
        );

        emit ClaimRewards(
            msg.sender,
            ajnaPool_,
            tokenId_,
            burnEpochsClaimed,
            rewardsEarned
        );

        // update last interaction burn event
        stakeInfo_.lastClaimedEpoch = uint96(epochToClaim_);

        // transfer rewards to sender
        _transferAjnaRewards(rewardsEarned);
    }

    /**
     *  @notice Retrieve an array of burn epochs from which a depositor has claimed rewards.
     *  @param  lastClaimedEpoch_      The last burn period in which a depositor claimed rewards.
     *  @param  burnEpochToStartClaim_ The most recent burn period from a depositor earned rewards.
     *  @return burnEpochsClaimed_     Array of burn epochs from which a depositor has claimed rewards.
     */
    function _getBurnEpochsClaimed(
        uint256 lastClaimedEpoch_,
        uint256 burnEpochToStartClaim_
    ) internal pure returns (uint256[] memory burnEpochsClaimed_) {
        uint256 numEpochsClaimed = burnEpochToStartClaim_ - lastClaimedEpoch_;

        burnEpochsClaimed_ = new uint256[](numEpochsClaimed);

        uint256 i;
        uint256 claimEpoch = lastClaimedEpoch_ + 1;
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
     *  @param  pool_                  Address of the `Ajna` pool to retrieve accumulators of.
     *  @param  currentBurnEventEpoch_ The latest burn event.
     *  @param  lastBurnEventEpoch_    The burn event to use as checkpoint since which values have accumulated.
     *  @return Timestamp of the latest burn event.
     *  @return Total `Ajna` tokens burned by the pool since the last burn event.
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
     *  @dev    Called as part of `stake`, `unstake`, and `claimRewards`, as well as `updateBucketExchangeRatesAndClaim`.
     *  @dev    Caller can claim `5%` of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_           Address of the pool whose exchange rates are being updated.
     *  @param  indexes_        List of bucket indexes to be updated.
     *  @return updatedRewards_ Update exchange rate rewards.
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

                uint256 rewardsCap            = Maths.wmul(UPDATE_CAP, totalBurned);
                uint256 rewardsClaimedInEpoch = updateRewardsClaimed[curBurnEpoch];

                // update total tokens claimed for updating bucket exchange rates tracker
                if (rewardsClaimedInEpoch + updatedRewards_ >= rewardsCap) {
                    // if update reward is greater than cap, set to remaining difference
                    updatedRewards_ = rewardsCap - rewardsClaimedInEpoch;
                }

                // accumulate the full amount of additional rewards
                updateRewardsClaimed[curBurnEpoch] += updatedRewards_;
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
        uint256 burnExchangeRate = bucketExchangeRates[pool_][bucketIndex_][burnEpoch_];

        // update bucket exchange rate at epoch only if it wasn't previously updated
        if (burnExchangeRate == 0) {
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(bucketIndex_);

            // record bucket exchange rate at epoch
            bucketExchangeRates[pool_][bucketIndex_][burnEpoch_] = curBucketExchangeRate;
        }
    }

    /**
     *  @notice Update the exchange rate of a specific bucket and calculate rewards based on prev exchange rate.
     *  @param  pool_           Address of the pool whose exchange rates are being updated.
     *  @param  bucketIndex_    Bucket index to update exchange rate.
     *  @param  burnEpoch_      Current burn epoch of the pool.
     *  @param  totalBurned_    Total `Ajna` tokens burned in pool.
     *  @param  interestEarned_ Total interest rate earned in pool.
     *  @return rewards_        Rewards for bucket exchange rate update.
     */
    function _updateBucketExchangeRateAndCalculateRewards(
        address pool_,
        uint256 bucketIndex_,
        uint256 burnEpoch_,
        uint256 totalBurned_,
        uint256 interestEarned_
    ) internal returns (uint256 rewards_) {
        uint256 burnExchangeRate = bucketExchangeRates[pool_][bucketIndex_][burnEpoch_];

        // update bucket exchange rate at epoch only if it wasn't previously updated
        if (burnExchangeRate == 0) {
            uint256 curBucketExchangeRate = IPool(pool_).bucketExchangeRate(bucketIndex_);

            // record bucket exchange rate at epoch
            bucketExchangeRates[pool_][bucketIndex_][burnEpoch_] = curBucketExchangeRate;

            // retrieve the bucket exchange rate at the previous epoch
            uint256 prevBucketExchangeRate = bucketExchangeRates[pool_][bucketIndex_][burnEpoch_ - 1];

            // skip reward calculation if update at the previous epoch was missed and if exchange rate decreased due to bad debt
            // prevents excess rewards from being provided from using a 0 value as an input to the interestFactor calculation below.
            if (prevBucketExchangeRate != 0 && prevBucketExchangeRate < curBucketExchangeRate) {

                // retrieve current deposit of the bucket
                (, , , uint256 bucketDeposit, ) = IPool(pool_).bucketInfo(bucketIndex_);

                uint256 burnFactor     = Maths.wmul(totalBurned_, bucketDeposit);
                uint256 interestFactor = interestEarned_ == 0 ? 0 : Maths.wdiv(
                    Maths.WAD - Maths.wdiv(prevBucketExchangeRate, curBucketExchangeRate),
                    interestEarned_
                );

                // calculate rewards earned for updating bucket exchange rate 
                rewards_ += Maths.wmul(UPDATE_CLAIM_REWARD, Maths.wmul(burnFactor, interestFactor));
            }
        }
    }

    /** @notice Utility method to transfer `Ajna` rewards to the sender
     *  @dev   This method is used to transfer rewards to the `msg.sender` after a successful claim or update.
     *  @dev   It is used to ensure that rewards claimers will be able to claim some portion of the remaining tokens if a claim would exceed the remaining contract balance.
     *  @param rewardsEarned_ Amount of rewards earned by the caller.
     */
    function _transferAjnaRewards(uint256 rewardsEarned_) internal {
        // check that rewards earned isn't greater than remaining balance
        // if remaining balance is greater, set to remaining balance
        uint256 ajnaBalance = IERC20(ajnaToken).balanceOf(address(this));
        if (rewardsEarned_ > ajnaBalance) rewardsEarned_ = ajnaBalance;

        if (rewardsEarned_ != 0) {
            // transfer rewards to sender
            IERC20(ajnaToken).safeTransfer(msg.sender, rewardsEarned_);
        }
    }

}
