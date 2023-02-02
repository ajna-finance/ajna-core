
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';

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
    ****************************************************************************************************************************************/

    uint256                   internal constant NUM_ACTORS = 10;
    BasicPoolHandler          internal _basicPoolHandler;
    address                   internal _handler;

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

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

    // checks pool lps are equal to sum of all lender lps in a bucket 
    function invariant_Lps_B1() public {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;
            for (uint256 i = 0; i < actorCount; i++) {
                address lender = IBaseHandler(_handler)._actors(i);
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
                totalLps += lps;
            }
            (uint256 bucketLps, , , , ) = _pool.bucketInfo(bucketIndex);
            assertEq(bucketLps, totalLps, "Incorrect Bucket/lender lps");
        }
    }

    // checks bucket lps are equal to 0 if bucket quote and collateral are 0
    // checks exchange rate is 1e27 if bucket quote and collateral are 0 
    function invariant_Buckets_B2_B3() public {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( ,uint256 deposit, uint256 collateral, uint256 bucketLps, ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), bucketIndex);

            if (collateral == 0 && deposit == 0) {
                require(bucketLps == 0, "Incorrect bucket lps");
                require(exchangeRate == 1e27, "Incorrect exchange rate");
            }
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    function invariant_quoteTokenBalance_QT1() public {
        uint256 poolBalance = _quote.balanceOf(address(_pool));
        (uint256 pooldebt, , ) = _pool.debtInfo();
        (uint256 totalPoolBond, , ) = _pool.reservesInfo();
        // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
        assertGe(poolBalance + pooldebt, totalPoolBond + _pool.depositSize() , "Incorrect pool debt");
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance_CT1_CT7() public {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalCollateralPledged;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler)._actors(i);
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
    function invariant_pooldebt_QT2() public {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 totalDebt;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler)._actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalDebt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
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