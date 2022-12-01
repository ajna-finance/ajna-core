// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/pool/IPoolState.sol';

import '../libraries/Auctions.sol';
import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';

abstract contract Storage is IPoolState{
    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 10**18;

    uint256 internal constant LAMBDA_EMA_7D      = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR = 1e18 - LAMBDA_EMA_7D;
    int256  internal constant PERCENT_102        = 1.02 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint208 public override interestRate;       // [WAD]
    uint48  public override interestRateUpdate; // [SEC]

    uint208 internal inflatorSnapshot;           // [WAD]
    uint48  internal lastInflatorSnapshotUpdate; // [SEC]

    uint256 public override pledgedCollateral;  // [WAD]

    uint256 internal debtEma;   // [WAD]
    uint256 internal lupColEma; // [WAD]

    uint256 internal reserveAuctionKicked;    // Time a Claimable Reserve Auction was last kicked.
    uint256 internal reserveAuctionUnclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
    uint256 internal t0DebtInAuction;         // Total debt in auction used to restrict LPB holder from withdrawing [WAD]

    uint256 internal poolInitializations;
    uint256 internal t0poolDebt;           // Pool debt as if the whole amount was incurred upon the first loan. [WAD]

    mapping(address => mapping(address => mapping(uint256 => uint256))) internal _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    Auctions.Data                      internal auctions;
    mapping(uint256 => Buckets.Bucket) internal buckets;              // deposit index -> bucket
    Deposits.Data                      internal deposits;
    Loans.Data                         internal loans;
}
