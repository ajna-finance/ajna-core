// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { Maths }                                    from 'src/libraries/internal/Maths.sol';
import { _priceAt, _indexOf, MIN_PRICE, MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX }                        from 'src/libraries/helpers/PoolHelper.sol';

import { BaseHandler } from './BaseHandler.sol';

abstract contract UnboundedLiquidationPoolHandler is BaseHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    struct LocalBucketTakeVars {
        uint256 kickerLps;
        uint256 takerLps;
        uint256 deposit;
        uint256 kickerBond;
        uint256 borrowerLps;
    }

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _kickAuction(
        address borrower_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiqHandler.kickAuction']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        (uint256 interestRate, )   = _pool.interestRateInfo();

        // ensure actor always has the amount to pay for bond
        _ensureQuoteAmount(_actor, borrowerDebt);

        try _pool.kick(borrower_, 7388) {

            // **RE9**:  Reserves increase by 3 months of interest when a loan is kicked
            increaseInReserves += Maths.wmul(borrowerDebt, Maths.wdiv(interestRate, 4 * 1e18));

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _kickWithDeposit(
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.kickWithDeposit']++;
        
        (address maxBorrower, , )              = _pool.loansInfo();
        (uint256 borrowerDebt, , )             = _poolInfo.borrowerInfo(address(_pool), maxBorrower);
        (uint256 interestRate, )               = _pool.interestRateInfo();
        ( , , , uint256 depositBeforeAction, ) = _pool.bucketInfo(bucketIndex_);
        fenwickDeposits[bucketIndex_] = depositBeforeAction;

        // ensure actor always has the amount to add for kick
        _ensureQuoteAmount(_actor, borrowerDebt);

        try _pool.kickWithDeposit(bucketIndex_, 7388) {

            ( , , , uint256 depositAfterAction, ) = _pool.bucketInfo(bucketIndex_);

            // **RE9**:  Reserves increase by 3 months of interest when a loan is kicked
            increaseInReserves += Maths.wdiv(Maths.wmul(borrowerDebt, interestRate), 4 * 1e18);

            _fenwickRemove(depositBeforeAction - depositAfterAction, bucketIndex_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _withdrawBonds(
        address kicker_,
        uint256 maxAmount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.withdrawBonds']++;

        try _pool.withdrawBonds(kicker_, maxAmount_) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /******************************/
    /*** Taker Helper Functions ***/
    /******************************/

    function _takeAuction(
        address borrower_,
        uint256 amount_,
        address taker_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiqHandler.takeAuction']++;

        (address kicker, , , , , , , , , ) = _pool.auctionInfo(borrower_);

        (
            uint256 borrowerDebtBeforeTake,
            uint256 borrowerCollateralBeforeTake, 
        ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        uint256 totalBondBeforeTake          = _getKickerBond(kicker);
        uint256 totalBalanceBeforeTake       = _quote.balanceOf(address(_pool)) * 10**(18 - _quote.decimals());

        ( , , , , uint256 auctionPrice, )    = _poolInfo.auctionStatus(address(_pool), borrower_);

        // ensure actor always has the amount to take collateral
        _ensureQuoteAmount(taker_, 1e45);

        try _pool.take(borrower_, amount_, taker_, bytes("")) {

            (uint256 borrowerDebtAfterTake, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
            uint256 totalBondAfterTake          = _getKickerBond(kicker);
            uint256 totalBalanceAfterTake       = _quote.balanceOf(address(_pool)) * 10**(18 - _quote.decimals());

            if (borrowerDebtBeforeTake > borrowerDebtAfterTake) {
                // **RE7**: Reserves decrease with debt covered by take.
                decreaseInReserves += borrowerDebtBeforeTake - borrowerDebtAfterTake;
            } else {
                // **RE7**: Reserves increase by take penalty on first take.
                increaseInReserves += borrowerDebtAfterTake - borrowerDebtBeforeTake;
            }

            if (totalBondBeforeTake > totalBondAfterTake) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += totalBondBeforeTake - totalBondAfterTake;
            } else {
                // **RE7**: Reserves decrease by bond reward on take.
                decreaseInReserves += totalBondAfterTake - totalBondBeforeTake;
            }

            // **RE7**: Reserves increase with the quote token paid by taker.
            increaseInReserves += totalBalanceAfterTake - totalBalanceBeforeTake;

            // **CT2**: Keep track of bucketIndex when auction is settled and borrower compensated for fractional collateral
            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower_);
            if (kickTime == 0 && borrowerCollateralBeforeTake % 1e18 != 0 && _pool.poolType() == 1) {
                if (auctionPrice < MIN_PRICE) {
                    buckets.add(7388);
                    lenderDepositTime[borrower_][7388] = block.timestamp;
                } else if (auctionPrice > MAX_PRICE) {
                    buckets.add(0);
                    lenderDepositTime[borrower_][0] = block.timestamp;
                } else {
                    buckets.add(_indexOf(auctionPrice));
                    lenderDepositTime[borrower_][_indexOf(auctionPrice)] = block.timestamp;
                }
            }

            if (!alreadyTaken[borrower_]) {
                alreadyTaken[borrower_] = true;

                firstTake = true;

            } else firstTake = false;

            // reset taken flag in case auction was settled by take action
            _auctionSettleStateReset(borrower_);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _bucketTake(
        address taker_,
        address borrower_,
        bool depositTake_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiqHandler.bucketTake']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        (address kicker, , , , , , , , , )     = _pool.auctionInfo(borrower_);
        ( , , , , uint256 auctionPrice, )      = _poolInfo.auctionStatus(address(_pool), borrower_);
        uint256 auctionBucketIndex             = auctionPrice < MIN_PRICE ? 7388 : (auctionPrice > MAX_PRICE ? 0 : _indexOf(auctionPrice));
        
        LocalBucketTakeVars memory beforeBucketTakeVars = getBucketTakeInfo(bucketIndex_, kicker, _actor, auctionBucketIndex, borrower_);

        try _pool.bucketTake(borrower_, depositTake_, bucketIndex_) {

            LocalBucketTakeVars memory afterBucketTakeVars = getBucketTakeInfo(bucketIndex_, kicker, _actor, auctionBucketIndex, borrower_);

            // **B7**: when awarded bucket take LP : taker deposit time = timestamp of block when award happened
            if (afterBucketTakeVars.takerLps > beforeBucketTakeVars.takerLps) lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            if (afterBucketTakeVars.kickerLps > beforeBucketTakeVars.kickerLps) {
                // **B7**: when awarded bucket take LP : kicker deposit time = timestamp of block when award happened
                lenderDepositTime[kicker][bucketIndex_] = block.timestamp;
            }
            
            if (beforeBucketTakeVars.kickerBond > afterBucketTakeVars.kickerBond) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += beforeBucketTakeVars.kickerBond - afterBucketTakeVars.kickerBond;
            }
            // **R7**: Exchange rates are unchanged under depositTakes
            // **R8**: Exchange rates are unchanged under arbTakes
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower_);
            if (kickTime == 0 && _pool.poolType() == 1) {
                buckets.add(auctionBucketIndex);
                if (beforeBucketTakeVars.borrowerLps < afterBucketTakeVars.borrowerLps) {
                    lenderDepositTime[borrower_][auctionBucketIndex] = block.timestamp;
                }
            }

            // assign value to fenwick tree to mitigate rounding error that could be created in a _fenwickRemove call
            fenwickDeposits[bucketIndex_] = afterBucketTakeVars.deposit;

            _updateCurrentTakeState(borrower_, borrowerDebt);

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /********************************/
    /*** Settler Helper Functions ***/
    /********************************/

    function _settleAuction(
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

        try _pool.settle(borrower_, maxDepth_) {

            // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
            while (maxDepth_ != 0 && borrowerT0Debt != 0 && collateral != 0) {
                uint256 bucketIndex       = fenwickIndexForSum(1);
                uint256 maxSettleableDebt = Maths.wmul(collateral, _priceAt(bucketIndex));
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
                            collateral                   -= Maths.wdiv(borrowerDebt, _priceAt(bucketIndex));
                            borrowerT0Debt               = 0;
                        }
                        // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                        else if (maxSettleableDebt >= fenwickDeposit) {
                            fenwickDeposits[bucketIndex] = 0;
                            collateral                   -= Maths.wdiv(fenwickDeposit, _priceAt(bucketIndex));
                            borrowerT0Debt               -= Maths.wdiv(fenwickDeposit, inflator);
                        }
                        // exchange all collateral with deposit
                        else {
                            fenwickDeposits[bucketIndex] -= maxSettleableDebt;
                            collateral                   = 0;
                            borrowerT0Debt               -= Maths.wdiv(maxSettleableDebt, inflator);
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
                            borrowerT0Debt               -= Maths.wdiv(fenwickDeposit, inflator);
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
            (, , , uint256 kickTime, , , , , , ) = _pool.auctionInfo(borrower_);
            if (kickTime == 0 && collateral % 1e18 != 0 && _pool.poolType() == 1) {
                buckets.add(7388);
                lenderDepositTime[borrower_][7388] = block.timestamp;
            }
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function getBucketTakeInfo(uint256 bucketIndex_, address kicker_, address taker_, uint256 auctionBucketIndex_, address borrower_) internal view returns(LocalBucketTakeVars memory bucketTakeVars) {
        (bucketTakeVars.kickerLps, )      = _pool.lenderInfo(bucketIndex_, kicker_);
        (bucketTakeVars.takerLps, )       = _pool.lenderInfo(bucketIndex_, taker_);
        ( , , , bucketTakeVars.deposit, ) = _pool.bucketInfo(bucketIndex_);
        bucketTakeVars.kickerBond         = _getKickerBond(kicker_);
        (bucketTakeVars.borrowerLps, )    = _pool.lenderInfo(auctionBucketIndex_, borrower_);
    }

}
