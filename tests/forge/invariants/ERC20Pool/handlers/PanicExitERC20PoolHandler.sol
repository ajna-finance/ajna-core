// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import 'src/ERC20Pool.sol';

import { TokenWithNDecimals } from '../../../utils/Tokens.sol';

import { BaseERC20PoolHandler }            from './unbounded/BaseERC20PoolHandler.sol';
import { UnboundedBasicERC20PoolHandler }  from './unbounded/UnboundedBasicERC20PoolHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';

contract PanicExitERC20PoolHandler is UnboundedLiquidationPoolHandler, UnboundedBasicERC20PoolHandler {
    using EnumerableSet for EnumerableSet.UintSet;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 500;
    uint16 internal constant LOANS_COUNT = 3000;
    uint16 nonce;
    uint256 numberOfBuckets;

    EnumerableSet.UintSet internal _activeBorrowers;

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        address testContract_
    ) BaseERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, 0, testContract_) {
        numberOfBuckets = buckets.length();
        setUp();
    }

    function setUp() internal useTimestamps {
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
    ) external useTimestamps skipTime(skippedTime_) {
        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);

        _actor = _borrowers[borrowerIndex_];
        vm.startPrank(_actor);
        (,,, uint256 kickTime,,,,,,) = _pool.auctionInfo(_actor);
        if (block.timestamp > kickTime + 72 hours) {
            numberOfCalls['BPanicExitPoolHandler.settleDebt']++;
            _settleAuction(_actor, numberOfBuckets);
        } else {
            numberOfCalls['BPanicExitPoolHandler.repayLoan']++;
            _repayDebt(type(uint256).max);
        }
        (, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        _pullCollateral(collateral);
        vm.stopPrank();

        _auctionSettleStateReset(_actor);
        (,,, kickTime,,,,,,) = _pool.auctionInfo(_actor);
        if (kickTime == 0) _activeBorrowers.remove(borrowerIndex_);
    }

    /*****************************/
    /*** Lender Exit Functions ***/
    /*****************************/

    function kickAndTakeAuction(
        uint256 borrowerIndex_,
        uint256 kickerIndex_,
        uint256 skippedTime_,
        bool    takeAuction_
    ) external useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPanicExitPoolHandler.kickAndTakeAuction']++;

        borrowerIndex_ = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);
        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);

        address borrower = _borrowers[borrowerIndex_];
        address kicker   = _lenders[kickerIndex_];

        _actor = kicker;
        vm.startPrank(_actor);
        _kickAuction(borrower);

        if (takeAuction_) {
            vm.warp(block.timestamp + 61 minutes);
            ( , uint256 auctionedCollateral, ) = _pool.borrowerInfo(borrower);
            _takeAuction(borrower, auctionedCollateral, _actor);
        }

        vm.stopPrank();
    }

    function kickWithDeposit(
        uint256 kickerIndex_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPanicExitPoolHandler.kickWithDeposit']++;

        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker  = _lenders[kickerIndex_];

        _actor = kicker;
        vm.startPrank(_actor);
        _kickWithDeposit(_lenderBucketIndex);
        vm.stopPrank();
    }

    function withdrawBonds(
        uint256 kickerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BPanicExitPoolHandler.withdrawBonds']++;

        kickerIndex_    = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker  = _lenders[kickerIndex_];

        (uint256 kickerClaimable, ) = _pool.kickerInfo(kicker); 

        _actor = kicker;
        vm.startPrank(_actor);
        _withdrawBonds(kicker, kickerClaimable);
        vm.stopPrank();
    }

    function _setupLendersAndDeposits(uint256 count_) internal virtual {
        uint256[] memory buckets = buckets.values();
        for (uint256 i; i < count_;) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _actor = lender;
            vm.startPrank(_actor);
            _addQuoteToken(100_000 * 1e18, buckets[_randomBucket()]);
            vm.stopPrank();

            actors.push(lender);
            _lenders.push(lender);

            unchecked { ++i; }
        }
    }

    function _setupBorrowersAndLoans(uint256 count_) internal {
        for (uint256 i; i < count_;) {
            address borrower = address(uint160(uint256(keccak256(abi.encodePacked(i, 'borrower')))));

            _actor = borrower;
            vm.startPrank(_actor);
            _drawDebt(_randomDebt() * 1e18);
            vm.stopPrank();

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

}