// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";
import '../../utils/DSTestPlus.sol';

import { IERC20Token } from 'src/interfaces/pool/IPool.sol';
import { IERC20Pool }  from 'src/interfaces/pool/erc20/IERC20Pool.sol';
import { Maths }       from 'src/libraries/internal/Maths.sol';

import { IBaseHandler }  from '../interfaces/IBaseHandler.sol';
import { BaseInvariants } from '../base/BaseInvariants.sol';

// contains invariants for the test
abstract contract BasicInvariants is BaseInvariants {

    /******************************/
    /*** Common Pool Invariants ***/
    /******************************/

    function invariant_bucket() public useCurrentTimestamp {
        _invariant_B1();
        _invariant_B2_B3();
        _invariant_B4();
        _invariant_B5_B6_B7();
    }

    function invariant_quote() public useCurrentTimestamp {
        _invariant_QT1();
        _invariant_QT2();
        _invariant_QT3();
    }

    function invariant_exchange_rate() public useCurrentTimestamp {
        _invariant_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function invariant_loan() public useCurrentTimestamp {
        _invariant_L1_L2_L3();
    }

    function invariant_interest_rate() public useCurrentTimestamp {
        _invariant_I1();
        _invariant_I2();
        _invariant_I3();
        _invariant_I4();
    }

    function invariant_fenwick() public useCurrentTimestamp {
        _invariant_F1();
        _invariant_F2();
        _invariant_F3();
        _invariant_F4();
        _invariant_F5();
    }

    /*************************/
    /*** Bucket Invariants ***/
    /*************************/

    /// @dev checks pool lps are equal to sum of all lender lps in a bucket 
    function _invariant_B1() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            uint256 totalLps;

            for (uint256 j = 0; j < actorCount; j++) {
                address lender = IBaseHandler(_handler).actors(j);
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
                totalLps += lps;
            }

            (uint256 bucketLps, , , , ) = _pool.bucketInfo(bucketIndex);

            require(bucketLps == totalLps, "Buckets Invariant B1");
        }
    }

    /// @dev checks pool lps are equal to sum of all lender lps in a bucket 
    function _invariant_B4() internal view {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            // if bucket bankruptcy occured, then previousBankruptcy should be equal to current timestamp
            if (IBaseHandler(_handler).previousBankruptcy(bucketIndex) == block.timestamp) {
                (uint256 bucketLps, , , , ) = _pool.bucketInfo(bucketIndex);

                require(bucketLps == 0, "Buckets Invariant B4");
            }
        }
    }

    /// @dev checks bucket lps are equal to 0 if bucket quote and collateral are 0
    /// @dev checks exchange rate is 1e18 if bucket quote and collateral are 0 
    function _invariant_B2_B3() internal view {
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            (
                ,
                uint256 deposit,
                uint256 collateral,
                uint256 bucketLps,
                ,
                uint256 exchangeRate
            ) = _poolInfo.bucketInfo(address(_pool), bucketIndex);

            if (collateral == 0 && deposit == 0) {
                require(bucketLps == 0,       "Buckets Invariant B2");
                require(exchangeRate == 1e18, "Buckets Invariant B3");
            }
        }
    }

    /// @dev checks if lender deposit timestamp is updated when lps are added into lender lp balance
    function _invariant_B5_B6_B7() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            for (uint256 j = 0; j < actorCount; j++) {
                address lender = IBaseHandler(_handler).actors(j);
                (, uint256 depositTime) = _pool.lenderInfo(bucketIndex, lender);

                require(
                    depositTime == IBaseHandler(_handler).lenderDepositTime(lender, bucketIndex),
                    "Buckets Invariant B5, B6 or B7"
                );
            }   
        }
    }

    /************************/
    /*** Quote Invariants ***/
    /************************/

    /// @dev checks pool quote token balance is greater than equals total deposits in pool
    function _invariant_QT1() internal view {
        // convert pool quote balance into WAD
        uint256 poolBalance     = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();
        (uint256 poolDebt, , ,) = _pool.debtInfo();

        (
            uint256 totalBondEscrowed,
            uint256 unClaimed,
            ,
        ) = _pool.reservesInfo();

        uint256 assets      = poolBalance + poolDebt;
        uint256 liabilities = totalBondEscrowed + _pool.depositSize() + unClaimed;

        console.log("assets      -> ", assets);
        console.log("liabilities -> ", liabilities);

        greaterThanWithinDiff(
            assets,
            liabilities,
            1e13,
            "QT1: assets and liabilities not with a `1e13` margin"
        );
    }

    /// @dev checks pool debt is equal to sum of all borrowers debt
    function _invariant_QT2() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalDebt;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);

            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalT0Debt();

        require(poolDebt == totalDebt, "Quote Token Invariant QT2");
    }

    /// @dev checks pool quote token balance is greater than or equal with sum of escrowed bonds and unclaimed reserves
    function _invariant_QT3() internal view {
        // convert pool quote balance into WAD
        uint256 poolBalance = _quote.balanceOf(address(_pool)) * _pool.quoteTokenScale();
        (
            uint256 totalBondEscrowed,
            uint256 unClaimed,
            ,
        ) = _pool.reservesInfo();

        require(
            poolBalance >= totalBondEscrowed + unClaimed,
            "QT3: escrowed bonds and claimable reserves not guaranteed"
        );
    }

    /********************************/
    /*** Exchange Rate Invariants ***/
    /********************************/

    function _invariant_R1_R2_R3_R4_R5_R6_R7_R8() internal view {

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 currentExchangeRate = _pool.bucketExchangeRate(bucketIndex);
            (uint256 bucketLps, , , , ) = _pool.bucketInfo(bucketIndex);

            if (IBaseHandler(_handler).exchangeRateShouldNotChange(bucketIndex)) {
                uint256 previousExchangeRate = IBaseHandler(_handler).previousExchangeRate(bucketIndex);

                console.log("======================================");
                console.log("Bucket Index           -->", bucketIndex);
                console.log("Previous exchange Rate -->", previousExchangeRate);
                console.log("Current exchange Rate  -->", currentExchangeRate);
                console.log("Current bucket lps     -->", bucketLps);
                console.log("======================================");

                // If the bucket is small (less than 10 LP), require total change in bucket value to be less than .01 quote token
                if (bucketLps < Maths.wad(10)) {
                    requireWithinDiff(
                        Maths.wmul(currentExchangeRate, bucketLps),
                        Maths.wmul(previousExchangeRate, bucketLps),
                        1e16,
                        "Exchange Rate Invariant R1, R2, R3, R4, R5, R6, R7 or R8"
                    );
                } else {
                    // Common case, 1 one millionth (0.000_001) of a quote token or greater is inserted into a single bucket
                    requireWithinDiff(
                        currentExchangeRate,
                        previousExchangeRate,
                        1e8,  // otherwise require exchange rates to be within 1e-10,
                        "Exchange Rate Invariant R1, R2, R3, R4, R5, R6, R7 or R8"
                    );
                }
            }
        }
    }

    /************************/
    /*** Loans Invariants ***/
    /************************/

    function _invariant_L1_L2_L3() internal view {
        (address borrower, uint256 tp) = _pool.loanInfo(0);

        // first loan in loan heap should be 0
        require(borrower == address(0), "Loan Invariant L2");
        require(tp == 0,                "Loan Invariant L2");

        ( , , uint256 totalLoans) = _pool.loansInfo();

        for (uint256 loanId = 1; loanId < totalLoans; loanId++) {
            (borrower, tp) = _pool.loanInfo(loanId);

            // borrower address and threshold price should not 0
            require(borrower != address(0), "Loan Invariant L1");
            require(tp != 0,                "Loan Invariant L1");

            // tp of a loan at index 'i' in loan array should be greater than equals to loans at index '2i' and '2i+1'
            (, uint256 tp1) = _pool.loanInfo(2 * loanId);
            (, uint256 tp2) = _pool.loanInfo(2 * loanId + 1);

            require(tp >= tp1, "Loan Invariant L3");
            require(tp >= tp2, "Loan Invariant L3");
        }
    }

    /********************************/
    /*** Interest Rate Invariants ***/
    /********************************/

    /// @dev interest should only update once in 12 hours
    function _invariant_I1() internal {

        (, uint256 currentInterestRateUpdate) = _pool.interestRateInfo();

        if (currentInterestRateUpdate != previousInterestRateUpdate) {
            require(
                currentInterestRateUpdate - previousInterestRateUpdate >=  12 hours,
                "Incorrect interest rate update"
            );
        }

        previousInterestRateUpdate = currentInterestRateUpdate;
    }

    /// @dev reserve.totalInterestEarned should only update once per block
    function _invariant_I2() internal {
        (, , , uint256 totalInterestEarned) = _pool.reservesInfo();

        if (previousTotalInterestEarnedUpdate == block.number) {
            require(
                totalInterestEarned == previousTotalInterestEarned,
                "Incorrect total interest earned"
            );
        }

        previousTotalInterestEarnedUpdate = block.number;
        previousTotalInterestEarned       = totalInterestEarned;
    }

    /// @dev inflator should only update once per block
    function _invariant_I3() internal {
        (uint256 currentInflator, uint256 currentInflatorUpdate) = _pool.inflatorInfo();

        if (currentInflatorUpdate == previousInflatorUpdate) {
            require(currentInflator == previousInflator, "Incorrect inflator update");
        }

        uint256 poolT0Debt = _pool.totalT0Debt();
        if (poolT0Debt == 0) require(currentInflator == 1e18, "Incorrect inflator update");

        previousInflator       = currentInflator;
        previousInflatorUpdate = currentInflatorUpdate;
    }

    function _invariant_I4() internal view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 manualDebt2ToCollateral;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);

            (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

            if (kickTime == 0) {
                (uint256 borrowerT0Debt, uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
                uint256 weight = borrowerCollateral != 0 ? borrowerT0Debt ** 2 / borrowerCollateral : 0;

                manualDebt2ToCollateral += weight;
            }
        }

        (,,, uint256 t0Debt2ToCollateral) = _pool.debtInfo();

        require(t0Debt2ToCollateral == manualDebt2ToCollateral, "Incorrect debt2ToCollateral");

    }

    /*******************************/
    /*** Fenwick Tree Invariants ***/
    /*******************************/

    /// @dev deposits at index i (Deposits.valueAt(i)) is equal to the accumulation of scaled values incremented or decremented from index i
    function _invariant_F1() internal view {
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            (, , , uint256 depositAtIndex, ) = _pool.bucketInfo(bucketIndex);

            console.log("===================Bucket Index : ", bucketIndex, " ===================");
            console.log("Deposit From Pool               -->", depositAtIndex);
            console.log("Deposit From local fenwick tree -->", IBaseHandler(_handler).fenwickSumAtIndex(bucketIndex));
            console.log("=========================================");

            uint256 localDepositAtIndex = IBaseHandler(_handler).fenwickSumAtIndex(bucketIndex);

            // Require local and Fenwick deposits to be within 1 part in a billion relativelty, or 1 one one-millionth absolutely
            requireWithinDiff(
                depositAtIndex,
                localDepositAtIndex,
                (depositAtIndex + localDepositAtIndex) / 1e9 + Maths.max(_pool.quoteTokenScale(), 1e12), // deviation not lower than 1e12
                "Incorrect deposits in bucket"
            );
        }
    }

    /// @dev For any index i, the prefix sum up to and including i is the sum of values stored in indices j<=i
    function _invariant_F2() internal view {
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            uint256 depositTillIndex = _pool.depositUpToIndex(bucketIndex);

            console.log("===================Bucket Index : ", bucketIndex, " ===================");
            console.log("Deposit From Pool               -->", depositTillIndex);
            console.log("Deposit From local fenwick tree -->", IBaseHandler(_handler).fenwickSumTillIndex(bucketIndex));
            console.log("=========================================");

            uint256 localDepositTillIndex = IBaseHandler(_handler).fenwickSumTillIndex(bucketIndex);

            // Require local and Fenwick deposits to be within 1 part in a billion relativelty, or 1 one one-millionth absolutely
            requireWithinDiff(
                depositTillIndex,
                localDepositTillIndex,
                (depositTillIndex + localDepositTillIndex) / 1e9 + Maths.max(_pool.quoteTokenScale(), 1e12), // deviation not lower than 1e12
                "Incorrect deposits prefix sum"
            );
        }
    }

    /// @dev For any index i < MAX_FENWICK_INDEX, depositIndex(depositUpToIndex(i)) > i
    function _invariant_F3() internal view {
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            (, , , uint256 depositAtIndex, ) = _pool.bucketInfo(bucketIndex);
            uint256 prefixSum               = _pool.depositUpToIndex(bucketIndex);
            uint256 bucketIndexFromDeposit  = _pool.depositIndex(Maths.ceilWmul(prefixSum, 1e18 + 1e1));

            if (depositAtIndex != 0) {
                console.log("===================Bucket Index : ", bucketIndex, " ===================");
                console.log("Bucket Index from deposit -->", bucketIndexFromDeposit);
                console.log("=========================================");

                require(bucketIndexFromDeposit >=  bucketIndex, "Incorrect bucket index");
            }
        }
    }

    /// @dev **F4**: For any index i < MAX_FENWICK_INDEX, Deposits.valueAt(findIndexOfSum(prefixSum(i) + 1)) > 0
    function _invariant_F4() internal view {
        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        uint256 maxBucket;
        for (uint256 i = 0; i < buckets.length; i++) {
            if (buckets[i] > maxBucket) maxBucket = buckets[i];
        }

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 nextNonzeroBucket = _pool.depositIndex(_pool.depositUpToIndex(bucketIndex) + 1);

            if (nextNonzeroBucket < maxBucket) {
                (, , , uint256 depositAtNextNonzeroBucket, ) = _pool.bucketInfo(nextNonzeroBucket);

                require(depositAtNextNonzeroBucket >= 0, "F4: incorrect bucket with nonzero deposit");
            }
        }
    }

    /// @dev **F5**: Global scalar is never updated (`DepositsState.scaling[8192]` is always 0)
    function _invariant_F5() internal view {
        require(_pool.depositScale(8192) == 0, "F5: Global scalar was updated");
    }

    function invariant_call_summary() public virtual useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BBasicHandler.addQuoteToken         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBBasicHandler.addQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BBasicHandler.removeQuoteToken      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBBasicHandler.moveQuoteToken       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.moveQuoteToken"));
        console.log("BBasicHandler.moveQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.moveQuoteToken"));
        console.log("UBBasicHandler.removeQuoteToken     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BBasicHandler.addCollateral         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBBasicHandler.addCollateral        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BBasicHandler.removeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBBasicHandler.removeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("BBasicHandler.incLPAllowance        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.incLPAllowance"));
        console.log("UBBasicHandler.incLPAllowance       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.incLPAllowance"));
        console.log("BBasicHandler.transferLps           ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps"));
        console.log("UBBasicHandler.transferLps          ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.transferLps"));
        console.log("--Borrower--------");
        console.log("BBasicHandler.drawDebt              ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBBasicHandler.drawDebt             ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BBasicHandler.repayDebt             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBBasicHandler.repayDebt            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("BBasicHandler.pledgeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pledgeCollateral"));
        console.log("UBBasicHandler.pledgeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pledgeCollateral"));
        console.log("BBasicHandler.pullCollateral        ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.pullCollateral"));
        console.log("UBBasicHandler.pullCollateral       ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.pullCollateral"));
        console.log("BBasicHandler.stampLoan             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.stampLoan"));
        console.log("UBBasicHandler.stampLoan            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.stampLoan"));
        console.log("--Liquidation--------");
        console.log("BLiquidationHandler.kickAuction             ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction"));
        console.log("UBLiquidationHandler.kickAuction            ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.kickAuction"));
        console.log("BLiquidationHandler.lenderKickAuction       ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.lenderKickAuction"));
        console.log("UBLiquidationHandler.lenderKickAuction      ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.lenderKickAuction"));
        console.log("BLiquidationHandler.takeAuction             ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction"));
        console.log("UBLiquidationHandler.takeAuction            ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.takeAuction"));
        console.log("BLiquidationHandler.bucketTake              ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake"));
        console.log("UBLiquidationHandler.bucketTake             ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.bucketTake"));
        console.log("BLiquidationHandler.withdrawBonds           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds"));
        console.log("UBLiquidationHandler.withdrawBonds          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.withdrawBonds"));
        console.log("BLiquidationHandler.settleAuction           ",  IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction"));
        console.log("UBLiquidationHandler.settleAuction          ",  IBaseHandler(_handler).numberOfCalls("UBLiquidationHandler.settleAuction"));
        console.log("--Reserves--------");
        console.log("BReserveHandler.takeReserves        ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves"));
        console.log("UBReserveHandler.takeReserves       ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.takeReserves"));
        console.log("BReserveHandler.kickReserves        ",  IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserves"));
        console.log("UBReserveHandler.kickReserves       ",  IBaseHandler(_handler).numberOfCalls("UBReserveHandler.kickReserves"));
        console.log("--Rewards--------");
        console.log("BRewardsHandler.stake               ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake"));
        console.log("UBRewardsHandler.stake              ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.stake"));
        console.log("BRewardsHandler.unstake             ",  IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake"));
        console.log("UBRewardsHandler.unstake            ",  IBaseHandler(_handler).numberOfCalls("UBRewardsHandler.unstake"));
        console.log("--Positions--------");
        console.log("UBPositionHandler.mint              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.mint"));
        console.log("BPositionHandler.mint               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint"));
        console.log("UBPositionHandler.burn              ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.burn"));
        console.log("BPositionHandler.burn               ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn"));
        console.log("UBPositionHandler.memorialize       ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.memorialize"));
        console.log("BPositionHandler.memorialize        ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize"));
        console.log("UBPositionHandler.redeem            ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.redeem"));
        console.log("BPositionHandler.redeem             ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem"));
        console.log("UBPositionHandler.moveLiquidity     ",  IBaseHandler(_handler).numberOfCalls("UBPositionHandler.moveLiquidity"));
        console.log("BPositionHandler.moveLiquidity      ",  IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity"));
        console.log("------------------");
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.moveQuoteToken") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.pledgeCollateral") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.pullCollateral") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.incLPAllowance") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.transferLps") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.stampLoan") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.kickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.lenderKickAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.takeAuction") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.bucketTake") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.withdrawBonds") +
            IBaseHandler(_handler).numberOfCalls("BLiquidationHandler.settleAuction") +
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.takeReserves") +
            IBaseHandler(_handler).numberOfCalls("BReserveHandler.kickReserves") +
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.stake") + 
            IBaseHandler(_handler).numberOfCalls("BRewardsHandler.unstake") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.mint") + 
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.burn") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.memorialize") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.redeem") +
            IBaseHandler(_handler).numberOfCalls("BPositionHandler.moveLiquidity") 
        );
    }

}
