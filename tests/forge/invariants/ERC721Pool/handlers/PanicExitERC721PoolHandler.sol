// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { TokenWithNDecimals } from '../../../utils/Tokens.sol';

import { BaseERC721PoolHandler }           from './unbounded/BaseERC721PoolHandler.sol';
import { UnboundedBasicERC721PoolHandler } from './unbounded/UnboundedBasicERC721PoolHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';

contract PanicExitERC721PoolHandler is UnboundedLiquidationPoolHandler, UnboundedBasicERC721PoolHandler {
    using EnumerableSet for EnumerableSet.UintSet;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 200;
    uint16 internal constant LOANS_COUNT = 500;
    uint16 nonce;
    uint256 numberOfBuckets;

    EnumerableSet.UintSet internal _activeBorrowers;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, poolInfo_, 0, testContract_) {
        numberOfBuckets = buckets.length();
        setUp();
    }

    function setUp() internal useTimestamps {
        vm.startPrank(address(this));

        _setupLendersAndDeposits(LENDERS);
        _setupBorrowersAndLoans(LOANS_COUNT);

        ( , , uint256 totalLoans) = _pool.loansInfo();
        require(totalLoans == LOANS_COUNT, "loans setup failed");

        vm.warp(block.timestamp + 100_000 days);
    }

    /*******************************/
    /*** Borrower Exit Functions ***/
    /*******************************/

    function repayLoanOrSettleDebt(
        uint256 borrowerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);

        _actor = _borrowers[borrowerIndex_];
        changePrank(_actor);
        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(_actor);
        if (block.timestamp > kickTime + 72 hours) {
            numberOfCalls['BPanicExitPoolHandler.settleDebt']++;
            _settleAuction(_actor, numberOfBuckets);
        } else {
            numberOfCalls['BPanicExitPoolHandler.repayLoan']++;
            _repayDebt(type(uint256).max);
        }
        (, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        _pullCollateral(collateral);

        _resetSettledAuction(_actor, borrowerIndex_);
    }

    /*****************************/
    /*** Lender Exit Functions ***/
    /*****************************/

    function kickAndTakeAuction(
        uint256 borrowerIndex_,
        uint256 kickerIndex_,
        uint256 skippedTime_,
        bool    takeAuction_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPanicExitPoolHandler.kickAndTakeAuction']++;

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);
        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);

        address borrower = _borrowers[borrowerIndex_];
        address kicker   = _lenders[kickerIndex_];

        _actor = kicker;
        changePrank(_actor);
        _kickAuction(borrower);

        if (takeAuction_) {
            vm.warp(block.timestamp + 61 minutes);
            ( , uint256 auctionedCollateral, ) = _pool.borrowerInfo(borrower);
            _takeAuction(borrower, auctionedCollateral, _actor);
            _resetSettledAuction(borrower, borrowerIndex_);
        }
    }

    function kickAndBucketTakeAuction(
        uint256 borrowerIndex_,
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        bool depositTake_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPanicExitPoolHandler.kickAndBucketTakeAuction']++;

        bucketIndex_   = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);
        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);

        address borrower = _borrowers[borrowerIndex_];
        address kicker   = _lenders[kickerIndex_];

        _actor = kicker;
        changePrank(_actor);
        _kickAuction(borrower);

        vm.warp(block.timestamp + 61 minutes);

        _bucketTake(_actor, borrower, depositTake_, bucketIndex_);
        _resetSettledAuction(borrower, borrowerIndex_);
    }

    function lenderKickAuction(
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPanicExitPoolHandler.lenderKickAuction']++;

        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker  = _lenders[kickerIndex_];

        _actor = kicker;
        changePrank(_actor);
        _lenderKickAuction(_lenderBucketIndex);
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['BPanicExitPoolHandler.withdrawBonds']++;

        kickerIndex_    = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker  = _lenders[kickerIndex_];

        (uint256 kickerClaimable, ) = _pool.kickerInfo(kicker); 

        _actor = kicker;
        changePrank(_actor);
        _withdrawBonds(kicker, kickerClaimable);
    }

    function settleHeadAuction(
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        (, , , , , , address headAuction, , ) = _pool.auctionInfo(address(0));
        if (headAuction != address(0)) {
            _settleAuction(headAuction, 10);
            _resetSettledAuction(headAuction, 0);
        }
    }

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

    function _resetSettledAuction(address borrower_, uint256 borrowerIndex_) internal {
        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower_);
        if (kickTime == 0) {
            if (borrowerIndex_ != 0) _activeBorrowers.remove(borrowerIndex_);
        }
    }

}