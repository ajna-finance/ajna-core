// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Internal structs used by the pool / libraries
 */

/*****************************/
/*** Auction Param Structs ***/
/*****************************/

struct BucketTakeResult {
    uint256 collateralAmount;            // [WAD] amount of collateral taken
    uint256 compensatedCollateral;       // [WAD] amount of borrower collateral that is compensated with LPs
    uint256 t0DebtPenalty;               // [WAD] t0 penalty applied on first take
    uint256 remainingCollateral;         // [WAD] amount of borrower collateral remaining after take
    uint256 poolDebt;                    // [WAD] current pool debt
    uint256 t0PoolDebt;                  // [WAD] t0 pool debt
    uint256 newLup;                      // [WAD] current lup
    uint256 t0DebtInAuctionChange;       // [WAD] the amount of t0 debt recovered by take action
    uint256 t0PoolUtilizationDebtWeight; // [WAD] utilization weight accumulator, tracks debt and collateral relationship accross borrowers
    bool    settledAuction;              // true if auction is settled by take action
}

struct KickResult {
    uint256 amountToCoverBond;           // [WAD] amount of bond that needs to be covered
    uint256 t0PoolDebt;                  // [WAD] t0 debt in pool after kick
    uint256 t0KickedDebt;                // [WAD] new t0 debt after kick
    uint256 lup;                         // [WAD] current lup
    uint256 t0PoolUtilizationDebtWeight; // [WAD] utilization weight accumulator, tracks debt and collateral relationship accross borrowers
}

struct SettleParams {
    address borrower;    // borrower address to settle
    uint256 reserves;    // current reserves in pool
    uint256 inflator;    // current pool inflator
    uint256 bucketDepth; // number of buckets to use when settle debt
    uint256 poolType;    // number of buckets to use when settle debt
}

struct TakeResult {
    uint256 collateralAmount;            // [WAD] amount of collateral taken
    uint256 compensatedCollateral;       // [WAD] amount of borrower collateral that is compensated with LPs
    uint256 quoteTokenAmount;            // [WAD] amount of quote tokens paid by taker for taken collateral
    uint256 t0DebtPenalty;               // [WAD] t0 penalty applied on first take
    uint256 excessQuoteToken;            // [WAD] (NFT only) amount of quote tokens to be paid by taker to borrower for fractional collateral
    uint256 remainingCollateral;         // [WAD] amount of borrower collateral remaining after take
    uint256 poolDebt;                    // [WAD] current pool debt
    uint256 t0PoolDebt;                  // [WAD] t0 pool debt
    uint256 newLup;                      // [WAD] current lup
    uint256 t0DebtInAuctionChange;       // [WAD] the amount of t0 debt recovered by take action
    bool    settledAuction;              // true if auction is settled by take action
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
    uint256 newLup;                      // [WAD] new pool LUP after draw debt
    uint256 poolCollateral;              // [WAD] total amount of collateral in pool after pledge collateral
    uint256 poolDebt;                    // [WAD] total accrued debt in pool after draw debt
    uint256 remainingCollateral;         // [WAD] amount of borrower collateral after draw debt (for NFT can be diminished if auction settled)
    bool    settledAuction;              // true if collateral pledged settles auction
    uint256 t0DebtInAuctionChange;       // [WAD] change of t0 pool debt in auction after pledge collateral
    uint256 t0PoolDebt;                  // [WAD] amount of t0 debt in pool after draw debt
    uint256 t0PoolUtilizationDebtWeight; // [WAD] utilization weight accumulator, tracks debt and collateral relationship accross borrowers
}

struct RepayDebtResult {
    uint256 newLup;                      // [WAD] new pool LUP after draw debt
    uint256 poolCollateral;              // [WAD] total amount of collateral in pool after pull collateral
    uint256 poolDebt;                    // [WAD] total accrued debt in pool after repay debt
    uint256 remainingCollateral;         // [WAD] amount of borrower collateral after pull collateral
    bool    settledAuction;              // true if repay debt settles auction
    uint256 t0DebtInAuctionChange;       // [WAD] change of t0 pool debt in auction after repay debt
    uint256 t0PoolDebt;                  // [WAD] amount of t0 debt in pool after repay
    uint256 quoteTokenToRepay;           // [WAD] quote token amount to be transferred from sender to pool
    uint256 t0PoolUtilizationDebtWeight; // [WAD] utilization weight accumulator, tracks debt and collateral relationship accross borrowers
}