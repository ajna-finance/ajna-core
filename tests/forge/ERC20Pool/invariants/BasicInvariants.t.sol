// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Maths } from 'src/libraries/internal/Maths.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    BasicPoolHandler
} from './handlers/BasicPoolHandler.sol';

import { InvariantsTestBase }     from './base/InvariantsTestBase.sol';
import { IBaseHandler } from './interfaces/IBaseHandler.sol';

// contains invariants for the test
contract BasicInvariants is InvariantsTestBase {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Bucket
        *  B1: totalBucketLPs === totalLenderLps
        *  B2: bucketLps == 0 (if bucket quote and collateral is 0)
        *  B3: exchangeRate == 0 (if bucket quote and collateral is 0)
        *  B4: bankrupt bucket LPs accumulator = 0; lender LPs for deposits before bankruptcy time = 0
        *  B5: block.timestamp == lenderDepositTime (if lps are added to lender lp balance)
        *  B6: block.timestamp == max(sender's depositTime, receiver's depositTime), when receiving transferred LPs
        *  B7: lenderDepositTime == block.timestamp (timestamp of block when taker is rewarded by bucketTake)
     * Quote Token
        * QT1: poolQtBal + poolDebt >= totalBondEscrowed + poolDepositSize
        * QT2: pool t0 debt = sum of all borrower's t0 debt

     * Collateral Token
        * CT1: poolCtBal >= sum of all borrower's collateral + sum of all bucket's claimable collateral
        * CT7: pool Pledged collateral = sum of all borrower's pledged collateral
    
     * Loan
        * L1: for each Loan in loans array (LoansState.loans) starting from index 1, the corresponding address (Loan.borrower) is not 0x, the threshold price (Loan.thresholdPrice) is different than 0
        * L2: Loan in loans array (LoansState.loans) at index 0 has the corresponding address (Loan.borrower) equal with 0x address and the threshold price (Loan.thresholdPrice) equal with 0
        * L3: Loans array (LoansState.loans) is a max-heap with respect to t0-threshold price: the t0TP of loan at index i is >= the t0-threshold price of the loans at index 2i and 2i+1

     * Interest Rate
        * I1: Interest rate should only update once in 12 hours
        * I2: ReserveAuctionState.totalInterestEarned accrues only once per block and equals to 1e18 if pool debt = 0
        * I3: Inflator should only update once per block

    * Fenwick tree
        * F1: Value represented at index i (Deposits.valueAt(i)) is equal to the accumulation of scaled values incremented or decremented from index i
        * F2: For any index i, the prefix sum up to and including i is the sum of values stored in indices j<=i
        * F3: For any index i < MAX_FENWICK_INDEX, findIndexOfSum(prefixSum(i)) > i
        * F4: For any index i, there is zero deposit above i and below findIndexOfSum(prefixSum(i) + 1): findIndexOfSum(prefixSum(i)) == findIndexOfSum(prefixSum(j) - deposits.valueAt(j)), where j is the next index from i with deposits != 0
    ****************************************************************************************************************************************/

    uint256          internal constant NUM_ACTORS = 10;
    BasicPoolHandler internal _basicPoolHandler;
    address          internal _handler;

    // bucket exchange rate tracking
    mapping(uint256 => uint256) internal previousBucketExchangeRate;

    uint256 previousInflator;
    uint256 previousInflatorUpdate;

    uint256 previousInterestRateUpdate;
    uint256 previousTotalInterestEarned;
    uint256 previousTotalInterestEarnedUpdate;

    function setUp() public override virtual{

        super.setUp();

        _basicPoolHandler = new BasicPoolHandler(
            address(_pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_basicPoolHandler);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_poolFactory));
        excludeContract(address(_pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_impl));

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( , , , , ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), bucketIndex);
            previousBucketExchangeRate[bucketIndex] = exchangeRate;
        }

        (, previousInterestRateUpdate) = _pool.interestRateInfo();

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

    // checks pool lps are equal to sum of all lender lps in a bucket 
    function invariant_Lps_B1_B4() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;

            for (uint256 i = 0; i < actorCount; i++) {
                address lender = IBaseHandler(_handler).actors(i);
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);

                totalLps += lps;
            }

            (uint256 bucketLps, , , , ) = _pool.bucketInfo(bucketIndex);

            assertEq(bucketLps, totalLps, "Incorrect Bucket/lender lps");
        }
    }

    // checks bucket lps are equal to 0 if bucket quote and collateral are 0
    // checks exchange rate is 1e27 if bucket quote and collateral are 0 
    function invariant_Buckets_B2_B3() public useCurrentTimestamp {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (
                ,
                uint256 deposit,
                uint256 collateral,
                uint256 bucketLps,
                ,
                uint256 exchangeRate
            ) = _poolInfo.bucketInfo(address(_pool), bucketIndex);

            if (collateral == 0 && deposit == 0) {
                require(bucketLps == 0, "Incorrect bucket lps");
                require(exchangeRate == 1e18, "Incorrect exchange rate");
            }
        }
    }

    // checks if lender deposit timestamp is updated when lps are added into lender lp balance
    function invariant_Bucket_deposit_time_B5_B6_B7() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            for (uint256 i = 0; i < actorCount; i++) {
                address lender = IBaseHandler(_handler).actors(i);

                (, uint256 depositTime) = _pool.lenderInfo(bucketIndex, lender);

                require(
                    depositTime == IBaseHandler(_handler).lenderDepositTime(lender, bucketIndex),
                    "Incorrect deposit Time"
                );
            }   
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    function invariant_quoteTokenBalance_QT1() public useCurrentTimestamp {
        // convert pool quote balance into WAD
        uint256 poolBalance    = _quote.balanceOf(address(_pool)) * 10**(18 - _quote.decimals());
        (uint256 poolDebt, , ) = _pool.debtInfo();

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
            "Incorrect pool quote token"
        );
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance_CT1_CT7() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        uint256 totalCollateralPledged;
        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);

            ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);

            totalCollateralPledged += borrowerCollateral;
        }

        assertEq(_pool.pledgedCollateral(), totalCollateralPledged, "Incorrect Collateral Pledged");

        // convert pool collateral balance into WAD
        uint256 collateralBalance = _collateral.balanceOf(address(_pool)) * 10**(18 - _collateral.decimals());
        uint256 bucketCollateral;

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, uint256 collateral, , , ) = _pool.bucketInfo(bucketIndex);

            bucketCollateral += collateral;
        }

        assertGe(collateralBalance, bucketCollateral + _pool.pledgedCollateral());
    }

    // checks pool debt is equal to sum of all borrowers debt
    function invariant_pooldebt_QT2() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalDebt;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);

            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalT0Debt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
    }

    function invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8() public useCurrentTimestamp {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 currentExchangeRate = _pool.bucketExchangeRate(bucketIndex);

            if (IBaseHandler(_handler).exchangeRateShouldNotChange(bucketIndex)) {
                uint256 previousExchangeRate = IBaseHandler(_handler).previousExchangeRate(bucketIndex);

                console.log("======================================");
                console.log("Bucket Index           -->", bucketIndex);
                console.log("Previous exchange Rate -->", previousExchangeRate);
                console.log("Current exchange Rate  -->", currentExchangeRate);
                console.log("======================================");

                requireWithinDiff(
                    currentExchangeRate,
                    previousExchangeRate,
                    1e17,
                    "Incorrect exchange Rate changed"
                );
            }
        }
    }

    function invariant_loan_L1_L2_L3() public useCurrentTimestamp {
        (address borrower, uint256 tp) = _pool.loanInfo(0);

        // first loan in loan heap should be 0
        require(borrower == address(0), "Incorrect borrower");
        require(tp == 0,                "Incorrect threshold price");

        ( , , uint256 totalLoans) = _pool.loansInfo();

        for (uint256 loanId = 1; loanId < totalLoans; loanId++) {
            (borrower, tp) = _pool.loanInfo(loanId);

            // borrower address and threshold price should not 0
            require(borrower != address(0), "Incorrect borrower");
            require(tp != 0,                "Incorrect threshold price");

            // tp of a loan at index 'i' in loan array should be greater than equals to loans at index '2i' and '2i+1'
            (, uint256 tp1) = _pool.loanInfo(2 * loanId);
            (, uint256 tp2) = _pool.loanInfo(2 * loanId + 1);

            require(tp >= tp1, "Incorrect loan heap");
            require(tp >= tp2, "Incorrect loan heap");
        }
    }

    // interest should only update once in 12 hours
    function invariant_interest_rate_I1() public useCurrentTimestamp {

        (, uint256 currentInterestRateUpdate) = _pool.interestRateInfo();

        if (currentInterestRateUpdate != previousInterestRateUpdate) {
            require(
                currentInterestRateUpdate - previousInterestRateUpdate >=  12 hours,
                "Incorrect interest rate update"
            );
        }

        previousInterestRateUpdate = currentInterestRateUpdate;
    }

    // reserve.totalInterestEarned should only update once per block
    function invariant_total_interest_earned_I2() public useCurrentTimestamp {
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

    // inflator should only update once per block
    function invariant_inflator_I3() public useCurrentTimestamp {
        (uint256 currentInflator, uint256 currentInflatorUpdate) = _pool.inflatorInfo();

        if (currentInflatorUpdate == previousInflatorUpdate) {
            require(currentInflator == previousInflator, "Incorrect inflator update");
        }

        uint256 poolT0Debt = _pool.totalT0Debt();
        if(poolT0Debt == 0) require(currentInflator == 1e18, "Incorrect inflator update");

        previousInflator       = currentInflator;
        previousInflatorUpdate = currentInflatorUpdate;
    }

    // deposits at index i (Deposits.valueAt(i)) is equal to the accumulation of scaled values incremented or decremented from index i
    function invariant_fenwick_depositAtIndex_F1() public useCurrentTimestamp {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, , , uint256 depositAtIndex, ) = _pool.bucketInfo(bucketIndex);

            console.log("===================Bucket Index : ", bucketIndex, " ===================");
            console.log("Deposit From Pool               -->", depositAtIndex);
            console.log("Deposit From local fenwick tree -->", IBaseHandler(_handler).fenwickSumAtIndex(bucketIndex));
            console.log("=========================================");

            requireWithinDiff(
                depositAtIndex,
                IBaseHandler(_handler).fenwickSumAtIndex(bucketIndex),
                1e16,
                "Incorrect deposits in bucket"
            );
        }
    }

    // For any index i, the prefix sum up to and including i is the sum of values stored in indices j<=i
    function invariant_fenwick_depositsTillIndex_F2() public useCurrentTimestamp {
        uint256 depositTillIndex;

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, , , uint256 depositAtIndex, ) = _pool.bucketInfo(bucketIndex);

            depositTillIndex += depositAtIndex;

            console.log("===================Bucket Index : ", bucketIndex, " ===================");
            console.log("Deposit From Pool               -->", depositTillIndex);
            console.log("Deposit From local fenwick tree -->", IBaseHandler(_handler).fenwickSumTillIndex(bucketIndex));
            console.log("=========================================");

            requireWithinDiff(
                depositTillIndex,
                IBaseHandler(_handler).fenwickSumTillIndex(bucketIndex),
                1e16,
                "Incorrect deposits prefix sum"
            );
        }
    }

    // For any index i < MAX_FENWICK_INDEX, depositIndex(depositUpToIndex(i)) > i
    function invariant_fenwick_bucket_index_F3() public useCurrentTimestamp {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, , , uint256 depositAtIndex, ) = _pool.bucketInfo(bucketIndex);
            uint256 prefixSum               = _pool.depositUpToIndex(bucketIndex);
            uint256 bucketIndexFromDeposit  = _pool.depositIndex(prefixSum);

            if (depositAtIndex != 0) {
                console.log("===================Bucket Index : ", bucketIndex, " ===================");
                console.log("Bucket Index from deposit -->", bucketIndexFromDeposit);
                console.log("=========================================");

                require(bucketIndexFromDeposit >=  bucketIndex, "Incorrect bucket index");
            }
        }
    }

    // **F4**: For any index i, there is zero deposit above i and below findIndexOfSum(prefixSum(i) + 1): `depositAt(j) == 0 for i<j<findIndexOfSum(prefixSum(i) + 1) and depositAt(findIndexOfSum(prefixSum(i) + 1))>0
    function invariant_fenwick_prefixSumIndex_F4() public useCurrentTimestamp {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; ) {
            uint256 nextNonzeroBucket = _pool.depositIndex(_pool.depositUpToIndex(bucketIndex)+1);
            console.log("bucketIndex:         ", bucketIndex);
            console.log("Next nonzero bucket: ", nextNonzeroBucket);
            for(uint256 j = bucketIndex + 1; j < nextNonzeroBucket && j < LENDER_MAX_BUCKET_INDEX; j++) {
                (, , , uint256 depositAtJ, ) = _pool.bucketInfo(j);
                //                console.log("Deposit at %s is %s", j, depositAtJ);
                require(
                        depositAtJ == 0,
                        "F4: incorrect buckets with 0 deposit"
                );
            }
            (, , , uint256 depositAtNextIndex, ) = _pool.bucketInfo(nextNonzeroBucket);
            console.log("Deposit at nonzero bucket %s is %s", nextNonzeroBucket, depositAtNextIndex);
            assertGe(depositAtNextIndex, 0, "F4: incorrect buckets with 0 deposit");
            assertGe(nextNonzeroBucket+1, bucketIndex);
            bucketIndex = nextNonzeroBucket+1;  // can skip ahead
        }
    }

    function invariant_call_summary() external virtual useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BBasicHandler.addQuoteToken         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBBasicHandler.addQuoteToken        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BBasicHandler.removeQuoteToken      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBBasicHandler.removeQuoteToken     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BBasicHandler.addCollateral         ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBBasicHandler.addCollateral        ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BBasicHandler.removeCollateral      ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBBasicHandler.removeCollateral     ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("--Borrower--------");
        console.log("BBasicHandler.drawDebt              ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBBasicHandler.drawDebt             ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BBasicHandler.repayDebt             ",  IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBBasicHandler.repayDebt            ",  IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("------------------");
        console.log(
            "Sum",
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.addCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.removeCollateral") +
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.drawDebt") + 
            IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt")
        );
    }

}
