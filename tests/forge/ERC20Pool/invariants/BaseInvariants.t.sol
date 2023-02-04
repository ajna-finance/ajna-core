
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';
import { BaseHandler } from './handlers/Base.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX, BoundedBasicPoolHandler } from './handlers/BasicPool.sol';

// struct FuzzSelector {
//     address addr;
//     bytes4[] selectors;
// }

// contains invariants for the test
contract BaseInvariants is TestBase {

    /**************************************************************************************************************************************/
    /*** Invariant Tests                                                                                                                ***/
    /***************************************************************************************************************************************
     * Bucket
        * Invariant A: totlaBucketLPs === totalLenderLps

     * Pool
        * Invariant A: poolQtBal >= poolDepositSize - poolDebt

     * Fenwick
        - **F1**: Value represented at index `i` (`Deposits.valueAt(i)`) is equal to the accumulation of scaled values incremented or decremented from index `i`

    ****************************************************************************************************************************************/

    uint256                   internal constant NUM_ACTORS = 10;
    BoundedBasicPoolHandler   internal _basicPoolHandler;

    function setUp() public override virtual{

        super.setUp();

        _basicPoolHandler = new BoundedBasicPoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
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
        uint256 actorCount = _basicPoolHandler.getActorsCount();
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;
            for (uint256 i = 0; i < actorCount; i++) {
                address lender = _basicPoolHandler._actors(i);
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
        // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
        assertGe(poolBalance + pooldebt, _pool.depositSize() , "Pool Invariant A");
    }

    // checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateralBalance() public {
        uint256 actorCount = _basicPoolHandler.getActorsCount();
        uint256 totalCollateralPledged;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = _basicPoolHandler._actors(i);
            ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
            totalCollateralPledged += borrowerCollateral;
        }

        require(_pool.pledgedCollateral() == totalCollateralPledged, "Incorrect Collateral Pledged");
        
    }

    // checks pool debt is equal to sum of all borrowers debt
    function invariant_pooldebt() public {
        uint256 actorCount = _basicPoolHandler.getActorsCount();
        uint256 totalDebt;
        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = _basicPoolHandler._actors(i);
            (uint256 debt, , ) = _pool.borrowerInfo(borrower);
            totalDebt += debt;
        }

        uint256 poolDebt = _pool.totalDebt();

        require(poolDebt == totalDebt, "Incorrect pool debt");
    }

    function invariant_fenwickTreeSum() public {
        assertEq(_basicPoolHandler.fenwickTreeSum(), _pool.depositSize(), "Fenwick Tree Invariant A");
    }

    // // checks sum of all kicker bond is equal to total pool bond
    // function invariant_bond() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     uint256 totalKickerBond;
    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address kicker = _invariantActorManager._actors(i);
    //         (, uint256 bond) = _pool.kickerInfo(kicker);
    //         totalKickerBond += bond;
    //     }

    //     uint256 totalBondInAuction;

    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address borrower = _invariantActorManager._actors(i);
    //         (, , uint256 bondSize, , , , , , ) = _pool.auctionInfo(borrower);
    //         totalBondInAuction += bondSize;
    //     }

    //     require(totalBondInAuction == totalKickerBond, "Incorrect bond");

    //     (uint256 totalPoolBond, , ) = _pool.reservesInfo();

    //     require(totalPoolBond == totalKickerBond, "Incorrect bond");
    // }

    function invariant_call_summary() external view {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BBasicHandler.addQuoteToken         ",  _basicPoolHandler.numberOfCalls("BBasicHandler.addQuoteToken"));
        console.log("UBBasicHandler.addQuoteToken        ",  _basicPoolHandler.numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("BBasicHandler.removeQuoteToken      ",  _basicPoolHandler.numberOfCalls("BBasicHandler.removeQuoteToken"));
        console.log("UBBasicHandler.removeQuoteToken     ", _basicPoolHandler.numberOfCalls("UBBasicHandler.removeQuoteToken"));
        console.log("BBasicHandler.addCollateral         ",  _basicPoolHandler.numberOfCalls("BBasicHandler.addCollateral"));
        console.log("UBBasicHandler.addCollateral        ",  _basicPoolHandler.numberOfCalls("UBBasicHandler.addCollateral"));
        console.log("BBasicHandler.removeCollateral      ",  _basicPoolHandler.numberOfCalls("BBasicHandler.removeCollateral"));
        console.log("UBBasicHandler.removeCollateral     ", _basicPoolHandler.numberOfCalls("UBBasicHandler.removeCollateral"));
        console.log("--Borrower--------");
        console.log("BBasicHandler.drawDebt              ",  _basicPoolHandler.numberOfCalls("BBasicHandler.drawDebt"));
        console.log("UBBasicHandler.drawDebt             ",  _basicPoolHandler.numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("BBasicHandler.repayDebt              ",  _basicPoolHandler.numberOfCalls("BBasicHandler.repayDebt"));
        console.log("UBBasicHandler.repayDebt             ",  _basicPoolHandler.numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("------------------");
        console.log(
            "Sum",
            _basicPoolHandler.numberOfCalls("BBasicHandler.addQuoteToken") +
            _basicPoolHandler.numberOfCalls("BBasicHandler.removeQuoteToken") +
            _basicPoolHandler.numberOfCalls("BBasicHandler.addCollateral") +
            _basicPoolHandler.numberOfCalls("BBasicHandler.removeCollateral") +
            _basicPoolHandler.numberOfCalls("BBasicHandler.drawDebt") + 
            _basicPoolHandler.numberOfCalls("BBasicHandler.repayDebt")
        );
    }
}