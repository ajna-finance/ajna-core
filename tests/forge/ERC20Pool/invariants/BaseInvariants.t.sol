
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX} from './handlers/Lenders.sol';

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

    ****************************************************************************************************************************************/

    function setUp() public override {
        super.setUp();

        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_poolFactory));
        excludeContract(address(_pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_impl));

        targetSender(address(0x1234));
    }

    // checks pool lps are equal to sum of all lender lps in a bucket 
    function invariant_Lps() public {
        uint256 actorCount = _lenderHandler.getActorsCount();
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            uint256 totalLps;
            for (uint256 i = 0; i < actorCount; i++) {
                address lender = _lenderHandler._actors(i);
                (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
                totalLps += lps;
            }
            (uint256 poolLps, , , , ) = _pool.bucketInfo(bucketIndex);
            assertEq(poolLps, totalLps, "Bucket Invariant A" );
        }
    }

    // checks pool quote token balance is greater than equals total deposits in pool
    // function invariant_quoteTokenBalance() public {
    //     uint256 poolBalance = _quote.balanceOf(address(_pool));
    //     (uint256 pooldebt, , ) = _pool.debtInfo();
    //     // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
    //     assertGe(poolBalance, _pool.depositSize() - pooldebt, "Pool Invariant A");
    // }

    // // checks pools collateral Balance to be equal to collateral pledged
    // function invariant_collateralBalance() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     uint256 totalCollateralPledged;
    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address borrower = _invariantActorManager._actors(i);
    //         ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
    //         totalCollateralPledged += borrowerCollateral;
    //     }

    //     require(_pool.pledgedCollateral() == totalCollateralPledged, "Incorrect Collateral Pledged");
    // }

    // // checks pool debt is equal to sum of all borrowers debt
    // function invariant_pooldebt() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     uint256 totalDebt;
    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address borrower = _invariantActorManager._actors(i);
    //         (uint256 debt, , ) = _pool.borrowerInfo(borrower);
    //         totalDebt += debt;
    //     }

    //     uint256 poolDebt = _pool.totalDebt();

    //     require(poolDebt == totalDebt, "Incorrect pool debt");
    // }

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
        console.log("BLenderHandler.addQuoteToken         ",  _lenderHandler.numberOfCalls("BLenderHandler.addQuoteToken"));
        console.log("UBLenderHandler.addQuoteToken        ",  _lenderHandler.numberOfCalls("UBLenderHandler.addQuoteToken"));
        console.log("BLenderHandler.removeQuoteToken      ",  _lenderHandler.numberOfCalls("BLenderHandler.removeQuoteToken"));
        console.log("UBLenderHandler.removeQuoteToken     ", _lenderHandler.numberOfCalls("UBLenderHandler.removeQuoteToken"));
        console.log("------------------");
        console.log(
            "Sum",
            _lenderHandler.numberOfCalls("BLenderHandler.addQuoteToken") +
            _lenderHandler.numberOfCalls("BLenderHandler.removeQuoteToken")
        );
    }
}