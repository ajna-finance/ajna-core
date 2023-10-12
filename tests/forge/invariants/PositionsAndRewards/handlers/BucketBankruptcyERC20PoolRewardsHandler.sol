// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { RewardsManager }  from 'src/RewardsManager.sol';
import { PositionManager } from 'src/PositionManager.sol';
import { Pool }            from 'src/base/Pool.sol';
import { ERC20Pool }       from 'src/ERC20Pool.sol';
import { Maths }           from 'src/libraries/internal/Maths.sol';

import { TokenWithNDecimals }          from '../../../utils/Tokens.sol';

import { BaseERC20PoolHandler }            from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { UnboundedBasicERC20PoolHandler }  from '../../ERC20Pool/handlers/unbounded/UnboundedBasicERC20PoolHandler.sol';
import { BaseRewardsPoolHandler }          from './BaseRewardsPoolHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';
import { UnboundedReservePoolHandler }     from '../../base/handlers/unbounded/UnboundedReservePoolHandler.sol';

contract BucketBankruptcyERC20PoolRewardsHandler is UnboundedBasicERC20PoolHandler, UnboundedLiquidationPoolHandler, UnboundedReservePoolHandler, BaseRewardsPoolHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 200;
    uint16 internal constant LOANS_COUNT = 500;
    uint16 nonce;
    uint256 numberOfBuckets;

    EnumerableSet.UintSet internal _activeBorrowers;

    constructor(
        address rewards_,
        address positions_,
        address[] memory pools_,
        address ajna_,
        address poolInfoUtils_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC20PoolHandler(pools_[0], ajna_, poolInfoUtils_, numOfActors_, testContract_) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);
        }

        // Position manager
        _positionManager = PositionManager(positions_); 

        // Rewards manager
        _rewardsManager = RewardsManager(rewards_);

        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC20_NON_SUBSET_HASH"));

        numberOfBuckets = buckets.length();
        setUp();
    }

    function setUp() internal useTimestamps {
        vm.startPrank(address(this));

        _setupLendersAndDeposits(LENDERS);
        _setupBorrowersAndLoans(LOANS_COUNT);

        ( , , uint256 totalLoans) = _pool.loansInfo();
        require(totalLoans == LOANS_COUNT, "loans setup failed");

        vm.warp(block.timestamp + 1_000 days);
    }

    function lenderKickAuction(
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPriceFall.lenderKickAuction']++;

        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker  = _lenders[kickerIndex_];

        _actor = kicker;
        changePrank(_actor);
        _lenderKickAuction(_lenderBucketIndex);
    }

    function moveQuoteTokenToLowerBucket(
        uint256 fromBucketIndex_,
        uint256 toBucketIndex_,
        uint256 amountToMove_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(fromBucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPriceFall.moveQuoteTokenToLowerBucket']++;

        toBucketIndex_ = constrictToRange(toBucketIndex_, _lenderBucketIndex, 7388);

        uint256 boundedAmount = _preMoveQuoteToken(amountToMove_, _lenderBucketIndex, toBucketIndex_);

        _moveQuoteToken(boundedAmount, _lenderBucketIndex, toBucketIndex_);
    }

    function stake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPriceFall.stake']++;
        // Pre action
        (uint256 tokenId, ) = _preStake(_lenderBucketIndex, amountToAdd_);

        // Action phase
        _stake(tokenId);
    }

    function moveStakedLiquidity(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_,
        uint256 numberOfEpochs_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BRewardsHandler.unstake']++;
        // Pre action
        (uint256 tokenId, uint256[] memory indexes) = _preUnstake(
            _lenderBucketIndex,
            amountToAdd_,
            numberOfEpochs_
        );
        
        // if rewards exceed contract balance tx will revert, return
        uint256 reward = _rewardsManager.calculateRewards(tokenId, _pool.currentBurnEpoch());
        if (reward > _ajna.balanceOf(address(_rewardsManager))) return;

        // Action phase
        _unstake(tokenId);

        // Move liquidity to lower index
        uint256 toIndex_ = constrictToRange(_randomBucket(), indexes[0], 7388);
        _moveLiquidity(tokenId, indexes[0], toIndex_);

        // re-stake Token
        _positionManager.approve(address(_rewardsManager), tokenId);
        _stake(tokenId);
    }

    function takeOrSettleAuction(
        uint256 borrowerIndex_,
        uint256 takerIndex_,
        uint256 skippedTime_
    ) external useTimestamps useRandomActor(takerIndex_) skipTime(skippedTime_) writeLogs {
        address borrower = _borrowers[constrictToRange(borrowerIndex_, 0, _borrowers.length - 1)];

        (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

        // Kick borrower if not already kicked
        if (kickTime == 0) {
            // skip some time to make borrower undercollateralized
            skip(200 days);

            _kickAuction(borrower);
            kickTime = block.timestamp;
        }

        // skip time to atleast 64 hours such that auction price is very low and less debt is settled through takeAuction
        uint256 timeAfterKick = block.timestamp - kickTime;
        if (timeAfterKick < 64 hours ) {
            skip(64 hours - timeAfterKick);
        }

        // if auction takeable, take all collateral or settle otherwise
        if (block.timestamp - kickTime <= 72 hours) {
            _takeAuction(borrower, type(uint256).max, _actor);
        } else {
            _settleAuction(borrower, numberOfBuckets);
        }
    }

    /*******************************/
    /*** Prepare Tests Functions ***/
    /*******************************/

    function _preMoveQuoteToken(
        uint256 amountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToMove_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

        // ensure actor has LP to move
        (uint256 lpBalance, ) = _pool.lenderInfo(fromIndex_, _actor);
        if (lpBalance == 0) _addQuoteToken(boundedAmount_, toIndex_);

        (uint256 lps, ) = _pool.lenderInfo(fromIndex_, _actor);
        // restrict amount to move by available deposit inside bucket
        uint256 availableDeposit = _poolInfo.lpToQuoteTokens(address(_pool), lps, fromIndex_);
        boundedAmount_ = Maths.min(boundedAmount_, availableDeposit);
    }

    /*******************************/
    /*** Setup Helper Functions  ***/
    /*******************************/

    function _setupLendersAndDeposits(uint256 count_) internal virtual {
        uint256[] memory buckets = buckets.values();
        for (uint256 i; i < count_;) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _actor = lender;
            changePrank(_actor);
            _addQuoteToken(100_000 * 1e18, buckets[_randomBucket()]);

            actors.push(lender);
            _lenders.push(lender);

            unchecked { ++i; }
        }
    }

    function _setupBorrowersAndLoans(uint256 count_) internal {
        for (uint256 i; i < count_;) {
            address borrower = address(uint160(uint256(keccak256(abi.encodePacked(i, 'borrower')))));

            _actor = borrower;
            changePrank(_actor);
            _drawDebt(_randomDebt() * 1e18);

            actors.push(borrower);
            _activeBorrowers.add(i);
            _borrowers.push(borrower);

            unchecked { ++i; }
        }
    }

    function _randomBucket() internal returns (uint256 randomBucket_) {
        randomBucket_ = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))
        ) % numberOfBuckets;
        ++ nonce;
    }

    function _randomDebt() internal returns (uint256 randomDebt_) {
        randomDebt_ = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))
        ) % 900 + 100;
        ++ nonce;
    }

    /*******************************/
    /***     Helper Functions    ***/
    /*******************************/

    function _resetSettledAuction(address borrower_, uint256 borrowerIndex_) internal {
        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower_);
        if (kickTime == 0) {
            if (borrowerIndex_ != 0) _activeBorrowers.remove(borrowerIndex_);
        }
    }


    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_,
        uint256 numberOfEpochs_
    ) internal override {}

    modifier useRandomPool(uint256 poolIndex) override {
        _;
    }

    function updateTokenAndPoolAddress(address pool_) internal override {}

}
