// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '../../../../utils/DSTestPlus.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Math }           from '@openzeppelin/contracts/utils/math/Math.sol';

import { Maths }                                    from 'src/libraries/internal/Maths.sol';
import { _priceAt, _indexOf, MIN_PRICE, MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';
import { MAX_FENWICK_INDEX }                        from 'src/libraries/helpers/PoolHelper.sol';
import { Buckets }                                  from 'src/libraries/internal/Buckets.sol'; 

import { BaseHandler } from './BaseHandler.sol';
import '@std/Vm.sol';

abstract contract UnboundedLiquidationPoolHandler is BaseHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    struct LocalTakeVars {
        uint256 kickerLps;
        uint256 takerLps;
        uint256 deposit;
        uint256 kickerBond;
        uint256 borrowerLps;
        uint256 borrowerCollateral;
        uint256 borrowerDebt;
    }

    /*******************************/
    /*** Kicker Helper Functions ***/
    /*******************************/

    function _kickAuction(
        address borrower_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.kickAuction']++;

        BorrowerInfo memory borrowerInfo = _getBorrowerInfo(borrower_);
        KickerInfo   memory kickerInfoBeforeKick = _getKickerInfo(_actor);

        // ensure actor always has the amount to pay for bond
        _ensureQuoteAmount(_actor, borrowerInfo.debt);

        try _pool.kick(
            borrower_,
            7388
        ) {
            numberOfActions['kick']++;

            KickerInfo memory kickerInfoAfterKick = _getKickerInfo(_actor);

            // **A7**: totalBondEscrowed should increase when auctioned kicked with the difference needed to cover the bond 
            increaseInBonds += kickerInfoAfterKick.totalBond - kickerInfoBeforeKick.totalBond;
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _lenderKickAuction(
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.lenderKickAuction']++;
        
        address maxBorrower = _getLoansInfo().maxBorrower;

        BorrowerInfo memory borrowerInfo = _getBorrowerInfo(maxBorrower);
        if (borrowerInfo.debt == 0) return;

        BucketInfo memory bucketInfoBeforeKick = _getBucketInfo(bucketIndex_);
        KickerInfo memory kickerInfoBeforeKick = _getKickerInfo(_actor);

        // record fenwick tree state before action
        fenwickDeposits[bucketIndex_] = bucketInfoBeforeKick.deposit;

        // ensure actor always has the amount to add for kick
        _ensureQuoteAmount(_actor, borrowerInfo.debt);

        try _pool.lenderKick(
            bucketIndex_,
            7388
        ) {
            numberOfActions['lenderKick']++;

            BucketInfo memory bucketInfoAfterKick = _getBucketInfo(bucketIndex_);
            KickerInfo memory kickerInfoAfterKick = _getKickerInfo(_actor);

            // **A7**: totalBondEscrowed should increase when auctioned kicked with the difference needed to cover the bond 
            increaseInBonds += kickerInfoAfterKick.totalBond - kickerInfoBeforeKick.totalBond;

            _fenwickRemove(bucketInfoBeforeKick.deposit - bucketInfoAfterKick.deposit, bucketIndex_);
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _withdrawBonds(
        address kicker_,
        uint256 maxAmount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBLiquidationHandler.withdrawBonds']++;

        KickerInfo memory kickerInfoBeforeWithdraw = _getKickerInfo(_actor);
        uint256 poolBalanceBeforeWithdraw = _getPoolQuoteBalance();

        try _pool.withdrawBonds(
            kicker_,
            maxAmount_
        ) {
            KickerInfo memory kickerInfoAfterWithdraw = _getKickerInfo(_actor);
            uint256 poolBalanceAfterWithdraw = _getPoolQuoteBalance();

            // **A7** Claimable bonds should be available for withdrawal from pool at any time (bonds are guaranteed by the protocol).
            require(
                kickerInfoAfterWithdraw.claimableBond < kickerInfoBeforeWithdraw.claimableBond,
                "A7: claimable bond not available to withdraw"
            );

            // **A7**: totalBondEscrowed should decrease only when kicker bonds withdrawned 
            decreaseInBonds += poolBalanceBeforeWithdraw - poolBalanceAfterWithdraw;
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

        AuctionInfo  memory auctionInfo     = _getAuctionInfo(borrower_);
        LocalTakeVars memory beforeTakeVars = _getTakeInfo(
            auctionInfo.auctionPriceIndex,
            auctionInfo.kicker,
            _actor,
            auctionInfo.auctionPriceIndex,
            borrower_
        );

        uint256 totalBalanceBeforeTake = _getPoolQuoteBalance();

        // ensure actor always has the amount to take collateral
        _ensureQuoteAmount(taker_, 1e45);

        try _pool.take(
            borrower_,
            amount_,
            taker_,
            bytes("")
        ) {
            numberOfActions['take']++;

            uint256 totalBalanceAfterTake = _getPoolQuoteBalance();

            LocalTakeVars memory afterTakeVars = _getTakeInfo(
                auctionInfo.auctionPriceIndex,
                auctionInfo.kicker,
                _actor,
                auctionInfo.auctionPriceIndex,
                borrower_
            );

            // **RE7**: Reserves decrease with debt covered by take.
            decreaseInReserves += beforeTakeVars.borrowerDebt - afterTakeVars.borrowerDebt;

            // **A8**: kicker reward <= Borrower penalty
            // Borrower penalty is difference between borrower collateral taken at auction price to amount of borrower debt reduced.
            borrowerPenalty = Maths.ceilWmul(beforeTakeVars.borrowerCollateral - afterTakeVars.borrowerCollateral, auctionInfo.auctionPrice) - (beforeTakeVars.borrowerDebt - afterTakeVars.borrowerDebt);

            if (afterTakeVars.borrowerLps > beforeTakeVars.borrowerLps) {
                // Borrower gets Lps at auction price against fractional collateral added to the bucket.
                borrowerPenalty -= _rewardedLpToQuoteToken(afterTakeVars.borrowerLps - beforeTakeVars.borrowerLps, auctionInfo.auctionPriceIndex);
            }

            if (beforeTakeVars.kickerBond > afterTakeVars.kickerBond) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += beforeTakeVars.kickerBond - afterTakeVars.kickerBond;

                // **A7**: Total Bond decrease by bond penalty on take.
                decreaseInBonds    += beforeTakeVars.kickerBond - afterTakeVars.kickerBond;
            } else {
                // **RE7**: Reserves decrease by bond reward on take.
                decreaseInReserves += afterTakeVars.kickerBond - beforeTakeVars.kickerBond;

                // **A7**: Total Bond increase by bond penalty on take.
                increaseInBonds += afterTakeVars.kickerBond - beforeTakeVars.kickerBond;

                // **A8**: kicker reward <= Borrower penalty
                kickerReward += afterTakeVars.kickerBond - beforeTakeVars.kickerBond;
            }

            // Reserves can increase by up to 2e-18 (1/5e17) due to rounding error in inflator value multiplied with t0Debt
            (uint256 inflator, ) = _pool.inflatorInfo();
            reservesErrorMargin = Math.max(reservesErrorMargin, inflator/5e17);

            // **RE7**: Reserves increase with the quote token paid by taker.
            increaseInReserves += totalBalanceAfterTake - totalBalanceBeforeTake;

            // **RE9**: Reserves unchanged by takes and bucket takes below TP(at the time of kick)
            if (auctionInfo.auctionPrice < Maths.min(auctionInfo.debtToCollateral, auctionInfo.neutralPrice)) {
                increaseInReserves = 0;
                decreaseInReserves = 0;
            }

            if (_pool.poolType() == 1) {
                _recordSettleBucket(
                    borrower_,
                    beforeTakeVars.borrowerCollateral,
                    auctionInfo.kickTime,
                    auctionInfo.auctionPrice
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

        AuctionInfo  memory auctionInfo     = _getAuctionInfo(borrower_);
        LocalTakeVars memory beforeTakeVars = _getTakeInfo(
            bucketIndex_,
            auctionInfo.kicker,
            _actor,
            auctionInfo.auctionPriceIndex,
            borrower_
        );

        // Record event emitted in bucketTake method call to calculate `borrowerPenalty` and `kickerReward`
        vm.recordLogs();

        try _pool.bucketTake(
            borrower_,
            depositTake_,
            bucketIndex_
        ) {
            numberOfActions['bucketTake']++;

            LocalTakeVars memory afterTakeVars = _getTakeInfo(
                bucketIndex_,
                auctionInfo.kicker,
                _actor,
                auctionInfo.auctionPriceIndex,
                borrower_
            );

            // **B7**: when awarded bucket take LP : taker deposit time = timestamp of block when award happened
            if (afterTakeVars.takerLps > beforeTakeVars.takerLps) lenderDepositTime[taker_][bucketIndex_] = block.timestamp;

            if (afterTakeVars.kickerLps > beforeTakeVars.kickerLps) {
                // **B7**: when awarded bucket take LP : kicker deposit time = timestamp of block when award happened
                lenderDepositTime[auctionInfo.kicker][bucketIndex_] = block.timestamp;
            }

            // Get emitted events logs in bucketTake
            Vm.Log[] memory entries = vm.getRecordedLogs();
            (borrowerPenalty, kickerReward) = _getBorrowerPenaltyAndKickerReward(
                entries,
                bucketIndex_,
                beforeTakeVars.borrowerDebt - afterTakeVars.borrowerDebt,
                depositTake_,
                auctionInfo.auctionPrice
            );
                
            // reserves are increased by take penalty of borrower (Deposit used from bucket - Borrower debt reduced)
            increaseInReserves += borrowerPenalty;

            // reserves are decreased by kicker reward
            decreaseInReserves += kickerReward;
            
            if (beforeTakeVars.kickerBond > afterTakeVars.kickerBond) {
                // **RE7**: Reserves increase by bond penalty on take.
                increaseInReserves += beforeTakeVars.kickerBond - afterTakeVars.kickerBond;

                // **A7**: Total Bond decrease by bond penalty on take.
                decreaseInBonds    += beforeTakeVars.kickerBond - afterTakeVars.kickerBond;
            }

            // **R7**: Exchange rates are unchanged under depositTakes
            // **R8**: Exchange rates are unchanged under arbTakes
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // Reserves can increase with roundings in deposit calculations when auction Price is very small
            if (auctionInfo.auctionPrice != 0 && auctionInfo.auctionPrice < 100) {
                reservesErrorMargin = (beforeTakeVars.deposit - afterTakeVars.deposit) / auctionInfo.auctionPrice;
            }

            // Reserves can increase by up to 2e-18 (1/5e17) due to rounding error in inflator value multiplied with t0Debt
            (uint256 inflator, ) = _pool.inflatorInfo();
            reservesErrorMargin = Math.max(reservesErrorMargin, inflator/5e17);

            // In case of bucket take, collateral is taken at bucket price.
            uint256 takePrice = _priceAt(bucketIndex_);

            // **RE9**: Reserves unchanged by takes and bucket takes below TP(at the time of kick)
            if (takePrice < auctionInfo.debtToCollateral) {
                increaseInReserves = 0;
                decreaseInReserves = 0;
            }

            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            if (
                _getAuctionInfo(borrower_).kickTime == 0
                &&
                _pool.poolType() == 1
            ) {
                buckets.add(auctionInfo.auctionPriceIndex);
                if (beforeTakeVars.borrowerLps < afterTakeVars.borrowerLps) {
                    lenderDepositTime[borrower_][auctionInfo.auctionPriceIndex] = block.timestamp;
                }
            }

            // assign value to fenwick tree to mitigate rounding error that could be created in a _fenwickRemove call
            fenwickDeposits[bucketIndex_] = afterTakeVars.deposit;
        } catch (bytes memory err) {
            // Reset event Logs
            vm.getRecordedLogs();

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

        BorrowerInfo memory borrowerInfo = _getBorrowerInfo(borrower_);

        uint256 reservesBeforeAction = _getReservesInfo().reserves;
        (uint256 inflator, ) = _pool.inflatorInfo();

        try _pool.settle(
            borrower_,
            maxDepth_
        ) {
            numberOfActions['settle']++;

            // settle borrower debt with exchanging borrower collateral with quote tokens starting from hpb
            while (maxDepth_ != 0 && borrowerInfo.t0Debt != 0 && borrowerInfo.collateral != 0) {
                uint256 bucketIndex       = fenwickIndexForSum(1);
                uint256 maxSettleableDebt = Maths.floorWmul(borrowerInfo.collateral, _priceAt(bucketIndex));
                uint256 fenwickDeposit    = fenwickDeposits[bucketIndex];
                uint256 borrowerDebt      = Maths.wmul(borrowerInfo.t0Debt, inflator);

                if (fenwickDeposit == 0 && maxSettleableDebt != 0) {
                    borrowerInfo.collateral = 0;
                    // Deposits in the tree is zero, insert entire collateral into lowest bucket 7388
                    // **B5**: when settle with collateral: record min bucket where collateral added
                    buckets.add(7388);
                    lenderDepositTime[borrower_][7388] = block.timestamp;
                } else {
                    if (bucketIndex != MAX_FENWICK_INDEX) {
                        // enough deposit in bucket and collateral avail to settle entire debt
                        if (fenwickDeposit >= borrowerDebt && maxSettleableDebt >= borrowerDebt) {
                            fenwickDeposits[bucketIndex] -= borrowerDebt;

                            borrowerInfo.collateral -= Maths.ceilWdiv(borrowerDebt, _priceAt(bucketIndex));
                            borrowerInfo.t0Debt     = 0;
                        }
                        // enough collateral, therefore not enough deposit to settle entire debt, we settle only deposit amount
                        else if (maxSettleableDebt >= fenwickDeposit) {
                            fenwickDeposits[bucketIndex] = 0;

                            borrowerInfo.collateral -= Maths.ceilWdiv(fenwickDeposit, _priceAt(bucketIndex));
                            borrowerInfo.t0Debt     -= Maths.floorWdiv(fenwickDeposit, inflator);
                        }
                        // exchange all collateral with deposit
                        else {
                            fenwickDeposits[bucketIndex] -= maxSettleableDebt;

                            borrowerInfo.collateral = 0;
                            borrowerInfo.t0Debt     -= Maths.floorWdiv(maxSettleableDebt, inflator);
                        }
                    } else {
                        borrowerInfo.collateral = 0;
                        // **B5**: when settle with collateral: record min bucket where collateral added.
                        // Lender doesn't get any LP when settle bad debt.
                        buckets.add(7388);
                    }
                }

                maxDepth_ -= 1;
            }

            // if collateral becomes 0 and still debt is left, settle debt by reserves and hpb making buckets bankrupt
            if (borrowerInfo.t0Debt != 0 && borrowerInfo.collateral == 0) {

                uint256 reservesAfterAction = _getReservesInfo().reserves;

                if (reservesBeforeAction > reservesAfterAction) {
                    // **RE12**: Reserves decrease by amount of reserve used to settle a auction
                    decreaseInReserves = reservesBeforeAction - reservesAfterAction;
                } else {
                    // Reserves might increase upto 2 WAD due to rounding issue
                    increaseInReserves = reservesAfterAction - reservesBeforeAction;
                }
                borrowerInfo.t0Debt -= Maths.min(
                    Maths.wdiv(decreaseInReserves, inflator),
                    borrowerInfo.t0Debt
                );

                while (maxDepth_ != 0 && borrowerInfo.t0Debt != 0) {
                    uint256 bucketIndex    = fenwickIndexForSum(1);
                    uint256 fenwickDeposit = fenwickDeposits[bucketIndex];
                    uint256 borrowerDebt   = Maths.wmul(borrowerInfo.t0Debt, inflator);

                    if (bucketIndex != MAX_FENWICK_INDEX) {
                        // debt is greater than bucket deposit
                        if (borrowerDebt > fenwickDeposit) {
                            fenwickDeposits[bucketIndex] = 0;

                            borrowerInfo.t0Debt -= Maths.floorWdiv(fenwickDeposit, inflator);
                        }
                        // bucket deposit is greater than debt
                        else {
                            fenwickDeposits[bucketIndex] -= borrowerDebt;

                            borrowerInfo.t0Debt = 0;
                        }
                    }

                    maxDepth_ -= 1;
                }
            }
            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            if (
                _getAuctionInfo(borrower_).kickTime == 0
                &&
                borrowerInfo.collateral % 1e18 != 0
                &&
                _pool.poolType() == 1
            ) {
                buckets.add(7388);
                lenderDepositTime[borrower_][7388] = block.timestamp;
            }
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _getTakeInfo(
        uint256 bucketIndex_,
        address kicker_,
        address taker_,
        uint256 auctionBucketIndex_,
        address borrower_
    ) internal view returns(LocalTakeVars memory takeVars) {
        takeVars.kickerLps   = _getLenderInfo(bucketIndex_, kicker_).lpBalance;
        takeVars.takerLps    = _getLenderInfo(bucketIndex_, taker_).lpBalance;
        takeVars.borrowerLps = _getLenderInfo(auctionBucketIndex_, borrower_).lpBalance;

        takeVars.deposit = _getBucketInfo(bucketIndex_).deposit;
        takeVars.kickerBond = _getKickerInfo(kicker_).totalBond;

        BorrowerInfo memory borrowerInfo = _getBorrowerInfo(borrower_);
        takeVars.borrowerDebt = borrowerInfo.debt;
        takeVars.borrowerCollateral = borrowerInfo.collateral;
    }

    // Helper function to calculate borrower penalty and kicker reward in bucket take through events emitted.
    function _getBorrowerPenaltyAndKickerReward(
        Vm.Log[] memory entries,
        uint256 bucketIndex_,
        uint256 borrowerDebtRepaid_,
        bool depositTake_,
        uint256 auctionPrice_
    ) internal view returns(uint256 borrowerPenalty_, uint256 kickerReward_) {
        // Kicker lp reward read from `BucketTakeLPAwarded(taker, kicker, lpAwardedTaker, lpAwardedKicker)` event.
        (, uint256 kickerLpAward) = abi.decode(entries[0].data, (uint256, uint256));
        kickerReward_ = _rewardedLpToQuoteToken(kickerLpAward, bucketIndex_);

        // Collateral Taken calculated from `BucketTake(borrower, index, amount, collateral, bondChange, isReward)` event.
        (, , uint256 collateralTaken, ,) = abi.decode(entries[1].data, (uint256, uint256, uint256, uint256, bool));

        if (depositTake_) {
            borrowerPenalty_ = Maths.ceilWmul(collateralTaken, _priceAt(bucketIndex_));
        } else {
            borrowerPenalty_ = Maths.ceilWmul(collateralTaken, auctionPrice_);
        }

        borrowerPenalty_ -= borrowerDebtRepaid_;
    }

    // Helper function to calculate quote tokens from lps in a bucket irrespective of deposit available.
    // LP rewarded -> quote token rounded up (as LP rewarded are calculated as rewarded quote token -> LP rounded down)
    function _rewardedLpToQuoteToken(
        uint256 lps_,
        uint256 bucketIndex_
    ) internal view returns(uint256 quoteTokens_) {
        BucketInfo memory bucketInfo = _getBucketInfo(bucketIndex_);
        quoteTokens_ = Buckets.lpToQuoteTokens(
            bucketInfo.collateral,
            bucketInfo.lpBalance,
            bucketInfo.deposit,
            lps_,
            _priceAt(bucketIndex_),
            Math.Rounding.Up
        );
    }
}