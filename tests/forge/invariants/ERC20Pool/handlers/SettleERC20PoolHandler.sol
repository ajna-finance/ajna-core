// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import 'src/ERC20Pool.sol';
import { _priceAt, MAX_FENWICK_INDEX } from 'src/libraries/helpers/PoolHelper.sol';

import { TokenWithNDecimals } from '../../../utils/Tokens.sol';

import { BaseERC20PoolHandler }            from './unbounded/BaseERC20PoolHandler.sol';
import { UnboundedBasicERC20PoolHandler }  from './unbounded/UnboundedBasicERC20PoolHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';

contract SettleERC20PoolHandler is UnboundedLiquidationPoolHandler, UnboundedBasicERC20PoolHandler {
    using EnumerableSet for EnumerableSet.UintSet;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 100;
    uint16 internal constant LOANS_COUNT = 100;
    uint16 nonce;
    uint256 numberOfBuckets;

    EnumerableSet.UintSet internal _activeBorrowers;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        address testContract_
    ) BaseERC20PoolHandler(pool_, ajna_, poolInfo_, 0, testContract_) {
        numberOfBuckets = buckets.length();
        setUp();
    }

    function setUp() internal useTimestamps {
        vm.startPrank(address(this));

        _setupLendersAndDeposits(LENDERS);
        _setupBorrowersAndLoans(LOANS_COUNT);

        uint256 totalLoans = _getLoansInfo().noOfLoans;
        require(totalLoans == LOANS_COUNT, "loans setup failed");

        vm.warp(block.timestamp + 1_000 days);
    }

    function settleDebt(
        uint256 kickerIndex_,
        uint256 borrowerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['SettlePoolHandler.settleDebt']++;

        borrowerIndex_   = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);
        address borrower = _borrowers[borrowerIndex_];

        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker = _lenders[kickerIndex_];

        uint256 kickTime = _getAuctionInfo(borrower).kickTime;

        // Kick auction if not already kicked
        if (kickTime == 0) {
            changePrank(kicker);
            _actor = kicker;
            _kickAuction(borrower);
        }

        kickTime = _getAuctionInfo(borrower).kickTime;

        if (kickTime == 0) return;

        // skip time to make auction settleable
        if (block.timestamp < kickTime + 72 hours) {
            skip(kickTime + 73 hours - block.timestamp);
        }

        changePrank(borrower);
        _actor = borrower;
        _settleAuction(borrower, numberOfBuckets);

        _resetSettledAuction(borrower, borrowerIndex_);
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
        if (_getAuctionInfo(borrower_).kickTime == 0) {
            if (borrowerIndex_ != 0) _activeBorrowers.remove(borrowerIndex_);
        }
    }

}