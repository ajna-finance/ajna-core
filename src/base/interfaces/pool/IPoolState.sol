// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool State
 */
interface IPoolState {

    /**
     *  @notice Returns details of an auction for a given borrower address.
     *  @param  borrower   Address of the borrower that is liquidated.
     *  @return kicker     Address that initiated the auction (kicker).
     *  @return bondFactor The factor used for calculating bond size.
     *  @return kickTime   Time the liquidation was initiated.
     *  @return kickPrice  Highest Price Bucket at time of liquidation.
     *  @return prev       The address of previous borrower in auctions queue.
     *  @return next       The address of next borrower in auctions queue.
     */
    function auctionInfo(address borrower) external view returns (
        address kicker,
        uint256 bondFactor,
        uint256 kickTime,
        uint256 kickPrice,
        address prev,
        address next
    );

    /**
     *  @notice Returns the `borrowerDebt` state variable.
     *  @return borrowerDebt_ Total amount of borrower debt in pool.
     */
    function borrowerDebt() external view returns (uint256 borrowerDebt_);

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower   Address of the borrower.
     *  @return debt       Amount of debt that the borrower has, in quote token.
     *  @return collateral Amount of collateral that the borrower has deposited, in collateral token.
     *  @return mompFactor Momp / borrowerInflatorSnapshot factor used.
     *  @return inflator   Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower)
        external
        view
        returns (
            uint256 debt,
            uint256 collateral,
            uint256 mompFactor,
            uint256 inflator
        );

    /**
     *  @notice Mapping of buckets indexes to {Bucket} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index               Bucket index.
     *  @return lpAccumulator       Amount of LPs accumulated in current bucket.
     *  @return availableCollateral Amount of collateral available in current bucket.
     */
    function buckets(uint256 index)
        external
        view
        returns (
            uint256 lpAccumulator,
            uint256 availableCollateral
        );

    /**
     *  @notice Returns the `debtEma` state variable.
     *  @return Exponential debt moving average.
     */
    function debtEma() external view returns (uint256);

    /**
     *  @notice Returns the `inflatorSnapshot` state variable.
     *  @return A snapshot of the last inflator value, in RAY units.
     */
    function inflatorSnapshot() external view returns (uint256);

    /**
     *  @notice Returns the `interestRate` state variable.
     *  @return interestRate TODO
     */
    function interestRate() external view returns (uint256);

    /**
     *  @notice Returns the `interestRateUpdate` state variable.
     *  @return The timestamp of the last rate update.
     */
    function interestRateUpdate() external view returns (uint256);

    function kickers(address kicker)
        external
        view
        returns (
            uint256 claimable,
            uint256 locked
        );

    /**
     *  @notice Returns the `lastInflatorSnapshotUpdate` state variable.
     *  @return The timestamp of the last `inflatorSnapshot` update.
     */
    function lastInflatorSnapshotUpdate() external view returns (uint256);

    /**
     *  @notice Mapping of buckets indexes and owner addresses to {Lender} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index            Bucket index.
     *  @param  lp               Address of the liquidity provider.
     *  @return lpBalance        Amount of LPs owner has in current bucket.
     *  @return lastQuoteDeposit Time the user last deposited quote token.
     */
    function lenders(
        uint256 index,
        address lp
    )
        external
        view
        returns (
            uint256 lpBalance,
            uint256 lastQuoteDeposit
    );

    /**
     *  @notice Returns the amount of liquidation bond across all liquidators.
     *  @return Total amount of quote token being escrowed.
     */
    function liquidationBondEscrowed() external view returns (uint256);

    /**
     *  @notice Returns the `lupColEma` state variable.
     *  @return Exponential LUP * pledged collateral moving average.
     */
    function lupColEma() external view returns (uint256);

    /**
     *  @notice Returns the borrower address with highest threshold price in pool.
     *  @return Borrower address with highest threshold price.
     */
    function maxBorrower() external view returns (address);

    /**
     *  @notice Returns the highest threshold price in pool.
     *  @return Highest threshold price in pool.
     */
    function maxThresholdPrice() external view returns (uint256);

    /**
     *  @notice Returns the total number of loans within pool.
     *  @return Total number of loans.
     */
    function noOfLoans() external view returns (uint256);

    /**
     *  @notice Returns the `pledgedCollateral` state variable.
     *  @return The total pledged collateral in the system, in WAD units.
     */
    function pledgedCollateral() external view returns (uint256);

    /**
     *  @notice Returns the amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
     *  @return Unclaimed Auction Reserve.
     */
    function reserveAuctionUnclaimed() external view returns (uint256);

    /**
     *  @notice Returns the Time a Claimable Reserve Auction was last kicked.
     *  @return Time a Claimable Reserve Auction was last kicked.
     */
    function reserveAuctionKicked() external view returns (uint256);

}