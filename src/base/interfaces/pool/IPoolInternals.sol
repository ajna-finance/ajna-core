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
    uint256 amount;          // amount to be added
    uint256 index;           // the index in which to deposit
}

struct MoveQuoteParams {
    uint256 fromIndex;       // the deposit index from where amount is moved
    uint256 maxAmountToMove; // max amount to move between deposits
    uint256 toIndex;         // the deposit index where amount is moved to
    uint256 thresholdPrice;  // max threshold price in pool
}

struct RemoveQuoteParams {
    uint256 index;           // the deposit index from where amount is removed
    uint256 maxAmount;       // max amount to be removed
    uint256 thresholdPrice;  // max threshold price in pool
}

/*************************************/
/*** Loan Management Param Structs ***/
/*************************************/

struct DrawDebtResult {
    uint256 newLup;
    uint256 poolCollateral;
    uint256 poolDebt;
    uint256 remainingCollateral;
    bool    settledAuction;
    uint256 t0DebtInAuctionChange;
    uint256 t0DebtChange;
}

struct RepayDebtResult {
    uint256 newLup;
    uint256 poolCollateral;
    uint256 poolDebt;
    uint256 remainingCollateral;
    bool    settledAuction;
    uint256 t0DebtInAuctionChange;
    uint256 t0RepaidDebt;
    uint256 quoteTokenToRepay;
}