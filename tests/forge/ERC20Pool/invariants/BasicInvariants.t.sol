
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX, BasicPoolHandler } from './handlers/BasicPoolHandler.sol';

interface Handler {
    function getActorsCount() external view returns(uint256);

    function _actors(uint256) external view returns(address);

    function numberOfCalls(bytes32) external view returns(uint256);
}

// struct FuzzSelector {
//     address addr;
//     bytes4[] selectors;
// }

// contains invariants for the test
contract BasicInvariants is TestBase {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Bucket
        * Invariant A: totlaBucketLPs === totalLenderLps

     * Pool
        * Invariant A: poolQtBal >= poolDepositSize - poolDebt

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
    function invariant_Lps() public {
        uint256 actorCount = Handler(_handler).getActorsCount();
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;
            for (uint256 i = 0; i < actorCount; i++) {
                address lender = Handler(_handler)._actors(i);
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
                totalLps += lps;
            }
            (uint256 poolLps, , , , ) = _pool.bucketInfo(bucketIndex);
            assertEq(poolLps, totalLps, "Bucket Invariant A");
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    function invariant_quoteTokenBalance() public {
        uint256 poolBalance = _quote.balanceOf(address(_pool));
        (uint256 pooldebt, , ) = _pool.debtInfo();
        (uint256 totalPoolBond, , ) = _pool.reservesInfo();
        // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
        assertGe(poolBalance + pooldebt, totalPoolBond + _pool.depositSize() , "Pool Invariant A");
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance() public {
        uint256 actorCount = Handler(_handler).getActorsCount();
        uint256 totalCollateralPledged;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = Handler(_handler)._actors(i);
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
    function invariant_pooldebt() public {
        uint256 actorCount = Handler(_handler).getActorsCount();
        uint256 totalDebt;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = Handler(_handler)._actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalDebt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
    }

    function invariant_call_summary() external view {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BBasicHandler.addQuoteToken         ",  Handler(_handler).numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBBasicHandler.addQuoteToken        ",  Handler(_handler).numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BBasicHandler.removeQuoteToken      ",  Handler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBBasicHandler.removeQuoteToken     ",  Handler(_handler).numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BBasicHandler.addCollateral         ",  Handler(_handler).numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBBasicHandler.addCollateral        ",  Handler(_handler).numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BBasicHandler.removeCollateral      ",  Handler(_handler).numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBBasicHandler.removeCollateral     ",  Handler(_handler).numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("--Borrower--------");
        console.log("BBasicHandler.drawDebt              ",  Handler(_handler).numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBBasicHandler.drawDebt             ",  Handler(_handler).numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BBasicHandler.repayDebt              ", Handler(_handler).numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBBasicHandler.repayDebt             ", Handler(_handler).numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("------------------");
        console.log(
            "Sum",
            Handler(_handler).numberOfCalls("BBasicHandler.addQuoteToken") +
            Handler(_handler).numberOfCalls("BBasicHandler.removeQuoteToken") +
            Handler(_handler).numberOfCalls("BBasicHandler.addCollateral") +
            Handler(_handler).numberOfCalls("BBasicHandler.removeCollateral") +
            Handler(_handler).numberOfCalls("BBasicHandler.drawDebt") + 
            Handler(_handler).numberOfCalls("BBasicHandler.repayDebt")
        );
    }
}