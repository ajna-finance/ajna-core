
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "@std/console.sol";

import { TestBase } from './TestBase.sol';

import { Maths } from 'src/libraries/internal/Maths.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX, BasicPoolHandler } from './handlers/BasicPoolHandler.sol';

import { IBaseHandler } from './handlers/IBaseHandler.sol';

// contains invariants for the test
contract BasicInvariants is TestBase {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Bucket
        *  B1: totalBucketLPs === totalLenderLps
        *  B2: bucketLps == 0 (if bucket quote and collateral is 0)
        *  B3: exchangeRate == 0 (if bucket quote and collateral is 0)
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
        * I3: Inflator should only update once per block
    ****************************************************************************************************************************************/

    uint256          internal constant NUM_ACTORS = 10;
    BasicPoolHandler internal _basicPoolHandler;
    address          internal _handler;

    // bucket exchange rate tracking
    mapping(uint256 => uint256) internal previousBucketExchangeRate;

    uint256 previousInterestRateUpdate;

    uint256 previousInflator;

    uint256 previousInflatorUpdate;

    function setUp() public override virtual{

        super.setUp();

        _basicPoolHandler = new BasicPoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
        _handler = address(_basicPoolHandler);
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
    function invariant_Lps_B1() public {
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
    function invariant_Buckets_B2_B3() public view {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( ,uint256 deposit, uint256 collateral, uint256 bucketLps, ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), bucketIndex);

            if (collateral == 0 && deposit == 0) {
                require(bucketLps == 0, "Incorrect bucket lps");
                require(exchangeRate == 1e18, "Incorrect exchange rate");
            }
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    function invariant_quoteTokenBalance_QT1() public {
        uint256 poolBalance  = _quote.balanceOf(address(_pool));
        uint256 t0debt       = _pool.totalT0Debt();
        (uint256 inflator, ) = _pool.inflatorInfo();
        uint256 poolDebt     = Maths.wmul(t0debt, inflator);
        (uint256 totalBondEscrowed, uint256 unClaimed, , ) = _pool.reservesInfo();

        assertGe(poolBalance + poolDebt, totalBondEscrowed + _pool.depositSize() + unClaimed, "Incorrect pool quote token");
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance_CT1_CT7() public {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalCollateralPledged;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
            totalCollateralPledged += borrowerCollateral;
        }

        assertEq(_pool.pledgedCollateral(), totalCollateralPledged, "Incorrect Collateral Pledged");

        uint256 collateralBalance = _collateral.balanceOf(address(_pool));
        uint256 bucketCollateral;

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, , uint256 collateral , , ) = _pool.bucketInfo(bucketIndex);
            bucketCollateral += collateral;
        }

        assertGe(collateralBalance, bucketCollateral + _pool.pledgedCollateral());
    }

    // checks pool debt is equal to sum of all borrowers debt
    function invariant_pooldebt_QT2() public view {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalDebt;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalT0Debt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
    }

    function _invariant_exchangeRate_RE1_RE2_R3_R4_R5_R6() public {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( , , , , ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), bucketIndex);
            if (!IBaseHandler(_handler).shouldExchangeRateChange()) {
                console.log("======================================");
                console.log("Bucket Index -->", bucketIndex);
                console.log("Previous exchange Rate -->", previousBucketExchangeRate[bucketIndex]);
                console.log("Current exchange Rate -->", exchangeRate);
                requireWithinDiff(exchangeRate, previousBucketExchangeRate[bucketIndex], 1e12, "Incorrect exchange Rate changed");
                console.log("======================================");
            }
            previousBucketExchangeRate[bucketIndex] = exchangeRate;
        }
    }

    function invariant_loan_L1_L2_L3() public view {
        (address borrower, uint256 tp) = _pool.loanInfo(0);

        // first loan in loan heap should be 0
        require(borrower == address(0), "Incorrect borrower");
        require(tp == 0, "Incorrect threshold price");

        ( , , uint256 totalLoans) = _pool.loansInfo();

        for(uint256 loanId = 1; loanId < totalLoans; loanId++) {
            (borrower, tp) = _pool.loanInfo(loanId);

            // borrower address and threshold price should not 0
            require(borrower != address(0), "Incorrect borrower");
            require(tp != 0, "Incorrect threshold price");

            // tp of a loan at index 'i' in loan array should be greater than equals to loans at index '2i' and '2i+1'
            (, uint256 tp1) = _pool.loanInfo(2 * loanId);
            (, uint256 tp2) = _pool.loanInfo(2 * loanId + 1);

            require(tp >= tp1, "Incorrect loan heap");
            require(tp >= tp2, "Incorrect loan heap");
        }
    }

    // interest should only update once in 12 hours
    function invariant_interest_rate_I1() public {

        (, uint256 currentInterestRateUpdate) = _pool.interestRateInfo();

        if (currentInterestRateUpdate != previousInterestRateUpdate) {
            require(currentInterestRateUpdate - previousInterestRateUpdate >=  12 hours, "Incorrect interest rate update");
        }
        previousInterestRateUpdate = currentInterestRateUpdate;
    }

    // inflator should only update once per block
    function invariant_inflator_I3() public {
        (uint256 currentInflator, uint256 currentInflatorUpdate) = _pool.inflatorInfo();
        if(currentInflatorUpdate == previousInflatorUpdate) {
            require(currentInflator == previousInflator, "Incorrect inflator update");
        }
        previousInflator = currentInflator;
        previousInflatorUpdate = currentInflatorUpdate;
    }

    function invariant_call_summary() external view virtual {
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
        console.log("BBasicHandler.repayDebt              ", IBaseHandler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBBasicHandler.repayDebt             ", IBaseHandler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
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