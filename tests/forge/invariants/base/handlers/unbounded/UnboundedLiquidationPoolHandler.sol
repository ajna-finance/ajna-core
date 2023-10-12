// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Math }           from '@openzeppelin/contracts/utils/math/Math.sol';

import { Maths }                                    from 'src/libraries/internal/Maths.sol';
import { _priceAt, _indexOf, MIN_PRICE, MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX }                        from 'src/libraries/helpers/PoolHelper.sol';
import { Buckets }                                  from 'src/libraries/internal/Buckets.sol'; 

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
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        (uint256 borrowerDebt, , ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        // ensure actor always has the amount to pay for bond
        _ensureQuoteAmount(_actor, borrowerDebt);

        uint256 kickerBondBefore = _getKickerBond(_actor);

        try _pool.kick(borrower_, 7388) {
            numberOfActions['kick']++;

            uint256 kickerBondAfter = _getKickerBond(_actor);

            // **A7**: totalBondEscrowed should increase when auctioned kicked with the difference needed to cover the bond 
            increaseInBonds += kickerBondAfter - kickerBondBefore;

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _lenderKickAuction(
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.lenderKickAuction']++;
        
        (address maxBorrower, , )              = _pool.loansInfo();
        (uint256 borrowerDebt, , )             = _poolInfo.borrowerInfo(address(_pool), maxBorrower);
        ( , , , uint256 depositBeforeAction, ) = _pool.bucketInfo(bucketIndex_);
        fenwickDeposits[bucketIndex_] = depositBeforeAction;

        uint256 kickerBondBefore = _getKickerBond(_actor);

        // ensure actor always has the amount to add for kick
        _ensureQuoteAmount(_actor, borrowerDebt);

        try _pool.lenderKick(bucketIndex_, 7388) {
            numberOfActions['lenderKick']++;

            ( , , , uint256 depositAfterAction, ) = _pool.bucketInfo(bucketIndex_);

            uint256 kickerBondAfter = _getKickerBond(_actor);

            // **A7**: totalBondEscrowed should increase when auctioned kicked with the difference needed to cover the bond 
            increaseInBonds += kickerBondAfter - kickerBondBefore;

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

        uint256 balanceBeforeWithdraw = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();
        (uint256 claimableBondBeforeWithdraw, ) = _pool.kickerInfo(_actor);

        try _pool.withdrawBonds(kicker_, maxAmount_) {

            uint256 balanceAfterWithdraw           = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();
            (uint256 claimableBondAfterWithdraw, ) = _pool.kickerInfo(_actor);

            // **A7** Claimable bonds should be available for withdrawal from pool at any time (bonds are guaranteed by the protocol).
            require(
                claimableBondAfterWithdraw < claimableBondBeforeWithdraw,
                "A7: claimable bond not available to withdraw"
            );

            // **A7**: totalBondEscrowed should decrease only when kicker bonds withdrawned 
            decreaseInBonds += balanceBeforeWithdraw - balanceAfterWithdraw;

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
        numberOfCalls['UBLiquidationHandler.takeAuction']++;

        (address kicker, , , , , , , , ) = _pool.auctionInfo(borrower_);

        (
            uint256 borrowerDebtBeforeTake,
            uint256 borrowerCollateralBeforeTake, 
        ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
        uint256 totalBondBeforeTake    = _getKickerBond(kicker);
        uint256 totalBalanceBeforeTake = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();

        (uint256 kickTimeBefore, , , , uint256 auctionPrice, )    = _poolInfo.auctionStatus(address(_pool), borrower_);

        // ensure actor always has the amount to take collateral
        _ensureQuoteAmount(taker_, 1e45);

        try _pool.take(borrower_, amount_, taker_, bytes("")) {
            numberOfActions['take']++;

            (uint256 borrowerDebtAfterTake, uint256 borrowerCollateralAfterTake, ) = _poolInfo.borrowerInfo(address(_pool), borrower_);
            uint256 totalBondAfterTake          = _getKickerBond(kicker);
            uint256 totalBalanceAfterTake       = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();

            // **RE7**: Reserves decrease with debt covered by take.
            decreaseInReserves += borrowerDebtBeforeTake - borrowerDebtAfterTake;
            
            // **A8**: kicker reward <= Borrower penalty
            borrowerPenalty = Maths.wmul(borrowerCollateralBeforeTake - borrowerCollateralAfterTake, auctionPrice) - (borrowerDebtBeforeTake - borrowerDebtAfterTake);

            if (totalBondBeforeTake > totalBondAfterTake) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += totalBondBeforeTake - totalBondAfterTake;

                // **A7**: Total Bond decrease by bond penalty on take.
                decreaseInBonds    += totalBondBeforeTake - totalBondAfterTake;
            } else {
                // **RE7**: Reserves decrease by bond reward on take.
                decreaseInReserves += totalBondAfterTake - totalBondBeforeTake;

                // **A7**: Total Bond increase by bond penalty on take.
                increaseInBonds += totalBondAfterTake - totalBondBeforeTake;

                // **A8**: kicker reward <= Borrower penalty
                kickerReward += totalBondAfterTake - totalBondBeforeTake;
            }

            // **RE7**: Reserves increase with the quote token paid by taker.
            increaseInReserves += totalBalanceAfterTake - totalBalanceBeforeTake;

            if (_pool.poolType() == 1) {
                _recordSettleBucket(
                    borrower_,
                    borrowerCollateralBeforeTake,
                    kickTimeBefore,
                    auctionPrice
                );
            }

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
        numberOfCalls['UBLiquidationHandler.bucketTake']++;

        ( uint256 borrowerDebtBeforeTake, uint256 borrowerCollateralBeforeTake,) = _poolInfo.borrowerInfo(address(_pool), borrower_);

        (address kicker, , , , , , , , ) = _pool.auctionInfo(borrower_);
        ( , , , , uint256 auctionPrice, )  = _poolInfo.auctionStatus(address(_pool), borrower_);
        uint256 auctionBucketIndex         = auctionPrice < MIN_PRICE ? 7388 : (auctionPrice > MAX_PRICE ? 0 : _indexOf(auctionPrice));
        
        LocalBucketTakeVars memory beforeBucketTakeVars = getBucketTakeInfo(bucketIndex_, kicker, _actor, auctionBucketIndex, borrower_);

        try _pool.bucketTake(borrower_, depositTake_, bucketIndex_) {
            numberOfActions['bucketTake']++;

            LocalBucketTakeVars memory afterBucketTakeVars = getBucketTakeInfo(bucketIndex_, kicker, _actor, auctionBucketIndex, borrower_);

            // **B7**: when awarded bucket take LP : taker deposit time = timestamp of block when award happened
            if (afterBucketTakeVars.takerLps > beforeBucketTakeVars.takerLps) lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            (uint256 borrowerDebtAfterTake, uint256 borrowerCollateralAfterTake, ) = _poolInfo.borrowerInfo(address(_pool), borrower_);

            if (afterBucketTakeVars.kickerLps > beforeBucketTakeVars.kickerLps) {
                // **B7**: when awarded bucket take LP : kicker deposit time = timestamp of block when award happened
                lenderDepositTime[kicker][bucketIndex_] = block.timestamp;

                // when kicker and taker are same, kicker Reward = total Reward (lps) - taker Reward (Collateral Price * difference of bucket used and auction price)
                if (!depositTake_ && kicker == _actor) {
                    uint256 totalReward = lpToQuoteToken(afterBucketTakeVars.kickerLps - beforeBucketTakeVars.kickerLps, bucketIndex_);
                    uint256 takerReward = Maths.wmul(borrowerCollateralBeforeTake - borrowerCollateralAfterTake, _priceAt(bucketIndex_) - auctionPrice);

                    // **A8**: kicker reward <= Borrower penalty
                    kickerReward = totalReward - takerReward;
                } else {
                    // **A8**: kicker reward <= Borrower penalty
                    kickerReward = lpToQuoteToken(afterBucketTakeVars.kickerLps - beforeBucketTakeVars.kickerLps, bucketIndex_);
                }
            }

            // **A8**: kicker reward <= Borrower penalty
            if (depositTake_) {
                borrowerPenalty = Maths.wmul(borrowerCollateralBeforeTake - borrowerCollateralAfterTake, _priceAt(bucketIndex_)) - (borrowerDebtBeforeTake - borrowerDebtAfterTake);
            } else {
                borrowerPenalty = Maths.wmul(borrowerCollateralBeforeTake - borrowerCollateralAfterTake, auctionPrice) - (borrowerDebtBeforeTake - borrowerDebtAfterTake);
            }
                
            // reserves are increased by take penalty of borrower (Deposit used from bucket - Borrower debt reduced)
            increaseInReserves += borrowerPenalty;

            // reserves are decreased by kicker reward
            decreaseInReserves += kickerReward;
            
            if (beforeBucketTakeVars.kickerBond > afterBucketTakeVars.kickerBond) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += beforeBucketTakeVars.kickerBond - afterBucketTakeVars.kickerBond;

                // **A7**: Total Bond decrease by bond penalty on take.
                decreaseInBonds    += beforeBucketTakeVars.kickerBond - afterBucketTakeVars.kickerBond;
            }
            // **R7**: Exchange rates are unchanged under depositTakes
            // **R8**: Exchange rates are unchanged under arbTakes
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower_);
            if (kickTime == 0 && _pool.poolType() == 1) {
                buckets.add(auctionBucketIndex);
                if (beforeBucketTakeVars.borrowerLps < afterBucketTakeVars.borrowerLps) {
                    lenderDepositTime[borrower_][auctionBucketIndex] = block.timestamp;
                }
            }

            // assign value to fenwick tree to mitigate rounding error that could be created in a _fenwickRemove call
            fenwickDeposits[bucketIndex_] = afterBucketTakeVars.deposit;

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
            numberOfActions['settle']++;

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

    // Helper function to calculate quote tokens from lps in a bucket irrespective of deposit available.
    function lpToQuoteToken(uint256 lps_, uint256 bucketIndex_) internal view returns(uint256 quoteTokens_) {
        (uint256 bucketLP, uint256 bucketCollateral , , uint256 bucketDeposit, ) = _pool.bucketInfo(bucketIndex_);

        quoteTokens_ =  Buckets.lpToQuoteTokens(
            bucketCollateral,
            bucketLP,
            bucketDeposit,
            lps_,
            _priceAt(bucketIndex_),
            Math.Rounding.Down
        );
    }

}
