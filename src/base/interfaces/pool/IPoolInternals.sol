// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Internal structs used by the pool / libraries
 */

/*****************************/
/*** Auction Param Structs ***/
/*****************************/

struct SettleParams {
    address borrower;    // borrower address to settle
    uint256 collateral;  // remaining collateral pledged by borrower that can be used to settle debt
    uint256 t0debt;      // borrower t0 debt to settle 
    uint256 reserves;    // current reserves in pool
    uint256 inflator;    // current pool inflator
    uint256 bucketDepth; // number of buckets to use when settle debt
}

struct BucketTakeParams {
    address borrower;       // borrower address to take from
    uint256 collateral;     // borrower available collateral to take
    bool    depositTake;    // deposit or arb take, used by bucket take
    uint256 index;          // bucket index, used by bucket take
    uint256 inflator;       // current pool inflator
    uint256 t0debt;         // borrower t0 debt
}

struct TakeParams {
    address borrower;       // borrower address to take from
    uint256 collateral;     // borrower available collateral to take
    uint256 t0debt;         // borrower t0 debt
    uint256 takeCollateral; // desired amount to take
    uint256 inflator;       // current pool inflator
}

struct KickResult {
    uint256 amountToCoverBond; // amount of bond that needs to be covered
    uint256 kickPenalty;       // kick penalty
    uint256 kickPenaltyT0;     // t0 kick penalty
    uint256 kickedT0debt;      // new t0 debt after kick
    uint256 lup;               // current lup
}

/******************************************/
/*** Liquidity Management Param Structs ***/
/******************************************/

struct MoveQuoteParams {
    uint256 maxAmountToMove; // max amount to move between deposits
    uint256 fromIndex;       // the deposit index from where amount is moved
    uint256 toIndex;         // the deposit index where amount is moved to
    uint256 thresholdPrice;  // max threshold price in pool
}

struct RemoveQuoteParams {
    uint256 maxAmount;      // max amount to be removed
    uint256 index;          // the deposit index from where amount is removed
    uint256 thresholdPrice; // max threshold price in pool
}