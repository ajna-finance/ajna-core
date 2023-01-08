// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Internal structs used by the pool / libraries
 */

/*****************************/
/*** Auction Param Structs ***/
/*****************************/

struct BucketTakeResult {
    uint256 collateralAmount;
    uint256 t0RepayAmount;
    uint256 t0DebtPenalty;
    uint256 remainingCollateral;
    uint256 poolDebt;
    uint256 newLup;
    uint256 t0DebtInAuctionChange;
    bool    settledAuction;
}

struct KickResult {
    uint256 amountToCoverBond; // amount of bond that needs to be covered
    uint256 kickPenalty;       // kick penalty
    uint256 t0KickPenalty;     // t0 kick penalty
    uint256 t0KickedDebt;      // new t0 debt after kick
    uint256 lup;               // current lup
}

struct SettleParams {
    address borrower;    // borrower address to settle
    uint256 reserves;    // current reserves in pool
    uint256 inflator;    // current pool inflator
    uint256 bucketDepth; // number of buckets to use when settle debt
    uint256 poolType;    // number of buckets to use when settle debt
}

struct TakeResult {
    uint256 collateralAmount;
    uint256 quoteTokenAmount;
    uint256 t0RepayAmount;
    uint256 t0DebtPenalty;
    uint256 excessQuoteToken;
    uint256 remainingCollateral;
    uint256 poolDebt;
    uint256 newLup;
    uint256 t0DebtInAuctionChange;
    bool    settledAuction;
}

/******************************************/
/*** Liquidity Management Param Structs ***/
/******************************************/

struct AddQuoteParams {
    uint256 amount;          // [WAD] amount to be added
    uint256 index;           // the index in which to deposit
}

struct MoveQuoteParams {
    uint256 fromIndex;       // the deposit index from where amount is moved
    uint256 maxAmountToMove; // [WAD] max amount to move between deposits
    uint256 toIndex;         // the deposit index where amount is moved to
    uint256 thresholdPrice;  // [WAD] max threshold price in pool
}

struct RemoveQuoteParams {
    uint256 index;           // the deposit index from where amount is removed
    uint256 maxAmount;       // [WAD] max amount to be removed
    uint256 thresholdPrice;  // [WAD] max threshold price in pool
}

/*************************************/
/*** Loan Management Param Structs ***/
/*************************************/

struct DrawDebtResult {
    uint256 newLup;                // [WAD] new pool LUP after draw debt
    uint256 poolCollateral;        // [WAD] total amount of collateral in pool after pledge collateral
    uint256 poolDebt;              // [WAD] total accrued debt in pool after draw debt
    uint256 remainingCollateral;   // [WAD] amount of borrower collateral after draw debt (for NFT can be diminished if auction settled)
    bool    settledAuction;        // true if collateral pledged settles auction
    uint256 t0DebtInAuctionChange; // [WAD] change of t0 pool debt in auction after pledge collateral
    uint256 t0DebtChange;          // [WAD] change of total t0 pool debt after after draw debt
}

struct RepayDebtResult {
    uint256 newLup;                // [WAD] new pool LUP after draw debt
    uint256 poolCollateral;        // [WAD] total amount of collateral in pool after pull collateral
    uint256 poolDebt;              // [WAD] total accrued debt in pool after repay debt
    uint256 remainingCollateral;   // [WAD] amount of borrower collateral after pull collateral
    bool    settledAuction;        // true if repay debt settles auction
    uint256 t0DebtInAuctionChange; // [WAD] change of t0 pool debt in auction after repay debt
    uint256 t0RepaidDebt;          // [WAD] amount of t0 repaid debt
    uint256 quoteTokenToRepay;     // [WAD] quote token amount to be transferred from sender to pool
}