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

        ( , , uint256 totalLoans) = _pool.loansInfo();
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

        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower);

        // Kick auction if not already kicked
        if (kickTime == 0) {
            changePrank(kicker);
            _actor = kicker;
            _kickAuction(borrower);
        }

        (,,, kickTime,,,,,) = _pool.auctionInfo(borrower);

        if (kickTime == 0) return;

        // skip time to make auction settleable
        if (block.timestamp < kickTime + 72 hours) {
            skip(kickTime + 73 hours - block.timestamp);
        }

        changePrank(borrower);
        _actor = borrower;
        _settle(borrower, numberOfBuckets);

        _resetSettledAuction(borrower, borrowerIndex_);
    }

    function repayDebtByThirdParty(
        uint256 actorIndex_,
        uint256 kickerIndex_,
        uint256 borrowerIndex_,
        uint256 skippedTime_
    ) external useTimestamps skipTime(skippedTime_) writeLogs {
        numberOfCalls['SettlePoolHandler.repayLoan']++;

        borrowerIndex_   = constrictToRange(borrowerIndex_, 0, _activeBorrowers.values().length - 1);
        address borrower = _borrowers[borrowerIndex_];

        kickerIndex_   = constrictToRange(kickerIndex_, 0, LENDERS - 1);
        address kicker = _lenders[kickerIndex_];

        actorIndex_    = constrictToRange(actorIndex_, 0, LENDERS - 1);
        address payer = _lenders[actorIndex_];

        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower);

        // Kick auction if not already kicked
        if (kickTime == 0) {
            changePrank(kicker);
            _actor = kicker;
            _kickAuction(borrower);
        }

        (,,, kickTime,,,,,) = _pool.auctionInfo(borrower);

        if (kickTime == 0) return;

        // skip time to make auction settleable
        if (block.timestamp < kickTime + 72 hours) {
            skip(kickTime + 73 hours - block.timestamp);
        }

        // skip time to make auction settleable
        if (block.timestamp < kickTime + 72 hours) {
            skip(kickTime + 73 hours - block.timestamp);
        }

        changePrank(payer);
        _repayDebtByThirdParty(payer, borrower, type(uint256).max);

        _resetSettledAuction(borrower, borrowerIndex_);
    }

    function _settle(
        address borrower_,
        uint256 maxDepth_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.settleAuction']++;
        (
            uint256 borrowerT0Debt,
            uint256 collateral,
        ) = _pool.borrowerInfo(borrower_);
        (uint256 reservesBeforeAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));
        (uint256 inflator, ) = _pool.inflatorInfo(); 

        _pool.settle(borrower_, maxDepth_);
        // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
        while (maxDepth_ != 0 && borrowerT0Debt != 0 && collateral != 0) {
            uint256 bucketIndex       = fenwickIndexForSum(1);
            uint256 maxSettleableDebt = Maths.floorWmul(collateral, _priceAt(bucketIndex));
            uint256 fenwickDeposit    = fenwickDeposits[bucketIndex];
            uint256 borrowerDebt      = Maths.wmul(borrowerT0Debt, inflator);

            if (fenwickDeposit == 0 && maxSettleableDebt != 0) {
                collateral = 0;
                // Deposits in the tree is zero, insert entire collateral into lowest bucket 7388
                // **B5**: when settle with collateral: record min bucket where collateral added
                buckets.add(7388);
                lenderDepositTime[borrower_][7388] = block.timestamp;
            } else {
                if (bucketIndex != MAX_FENWICK_INDEX) {
                    // enough deposit in bucket and collateral avail to settle entire debt
                    if (fenwickDeposit >= borrowerDebt && maxSettleableDebt >= borrowerDebt) {
                        fenwickDeposits[bucketIndex] -= borrowerDebt;
                        collateral                   -= Maths.ceilWdiv(borrowerDebt, _priceAt(bucketIndex));
                        borrowerT0Debt               = 0;
                    }
                    // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                    else if (maxSettleableDebt >= fenwickDeposit) {
                        fenwickDeposits[bucketIndex] = 0;
                        collateral                   -= Maths.ceilWdiv(fenwickDeposit, _priceAt(bucketIndex));
                        borrowerT0Debt               -= Maths.floorWdiv(fenwickDeposit, inflator);
                    }
                    // exchange all collateral with deposit
                    else {
                        fenwickDeposits[bucketIndex] -= maxSettleableDebt;
                        collateral                   = 0;
                        borrowerT0Debt               -= Maths.floorWdiv(maxSettleableDebt, inflator);
                    }
                } else {
                    collateral = 0;
                    // **B5**: when settle with collateral: record min bucket where collateral added.
                    // Lender doesn't get any LP when settle bad debt.
                    buckets.add(7388);
                }
            }

            maxDepth_ -= 1;
        }

        // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
        if (borrowerT0Debt != 0 && collateral == 0) {

            (uint256 reservesAfterAction, , , , )= _poolInfo.poolReservesInfo(address(_pool));
            if (reservesBeforeAction > reservesAfterAction) {
                // **RE12**: Reserves decrease by amount of reserve used to settle a auction
                decreaseInReserves = reservesBeforeAction - reservesAfterAction;
            } else {
                // Reserves might increase upto 2 WAD due to rounding issue
                increaseInReserves = reservesAfterAction - reservesBeforeAction;
            }
            borrowerT0Debt -= Maths.min(Maths.wdiv(decreaseInReserves, inflator), borrowerT0Debt);

            while (maxDepth_ != 0 && borrowerT0Debt != 0) {
                uint256 bucketIndex    = fenwickIndexForSum(1);
                uint256 fenwickDeposit = fenwickDeposits[bucketIndex];
                uint256 borrowerDebt   = Maths.wmul(borrowerT0Debt, inflator);

                if (bucketIndex != MAX_FENWICK_INDEX) {
                    // debt is greater than bucket deposit
                    if (borrowerDebt > fenwickDeposit) {
                        fenwickDeposits[bucketIndex] = 0;
                        borrowerT0Debt               -= Maths.floorWdiv(fenwickDeposit, inflator);
                    }
                    // bucket deposit is greater than debt
                    else {
                        fenwickDeposits[bucketIndex] -= borrowerDebt;
                        borrowerT0Debt               = 0;
                    }
                }

                maxDepth_ -= 1;
            }
        }
        // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
        (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower_);
        if (kickTime == 0 && collateral % 1e18 != 0 && _pool.poolType() == 1) {
            buckets.add(7388);
            lenderDepositTime[borrower_][7388] = block.timestamp;
        }
    }

    function _repayDebtByThirdParty(
        address payer_,
        address borrower_,
        uint256 amountToRepay_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        // ensure actor always has amount of quote to repay
        _ensureQuoteAmount(payer_, borrowerDebt + 10 * 1e18);

        _erc20Pool.repayDebt(borrower_, amountToRepay_, 0, borrower_, 7388);
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