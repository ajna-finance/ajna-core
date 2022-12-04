// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool State
 */
interface IPoolState {

    /**
     *  @notice Returns details of an auction for a given borrower address.
     *  @param  borrower          Address of the borrower that is liquidated.
     *  @return kicker            Address of the kicker that is kicking the auction.
     *  @return bondFactor        The factor used for calculating bond size.
     *  @return bondSize          The bond amount in quote token terms.
     *  @return kickTime          Time the liquidation was initiated.
     *  @return kickPrice         Highest Price Bucket at time of liquidation.
     *  @return neutralPrice      Neutral Price of auction.
     */
    function auctionInfo(address borrower)
    external
    view
    returns (
        address kicker,
        uint256 bondFactor,
        uint256 bondSize,
        uint256 kickTime,
        uint256 kickPrice,
        uint256 neutralPrice
    );

    /**
     *  @notice Returns pool related debt values.
     *  @return debt_            Current amount of debt owed by borrowers in pool.
     *  @return accruedDebt_     Debt owed by borrowers based on last inflator snapshot.
     *  @return debtInAuction_   Total amount of debt in auction.
     */
    function debtInfo() external view returns (uint256 debt_, uint256 accruedDebt_, uint256 debtInAuction_);

    /**
     *  @notice Mapping of borrower addresses to {Borrower} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower   Address of the borrower.
     *  @return t0debt     Amount of debt borrower would have had if their loan was the first debt drawn from the pool
     *  @return collateral Amount of collateral that the borrower has deposited, in collateral token.
     *  @return t0Np       Np / borrowerInflatorSnapshot
     */
    function borrowerInfo(address borrower)
        external
        view
        returns (
            uint256 t0debt,
            uint256 collateral,
            uint256 t0Np
        );

    /**
     *  @notice Mapping of buckets indexes to {Bucket} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  index               Bucket index.
     *  @return lpAccumulator       Amount of LPs accumulated in current bucket.
     *  @return availableCollateral Amount of collateral available in current bucket.
     *  @return bankruptcyTime      Timestamp when bucket become insolvent, 0 if healthy.
     *  @return bucketDeposit       Amount of quote tokens in bucket.
     *  @return bucketScale         Bucket multiplier.
     */
    function bucketInfo(uint256 index)
        external
        view
        returns (
            uint256 lpAccumulator,
            uint256 availableCollateral,
            uint256 bankruptcyTime,
            uint256 bucketDeposit,
            uint256 bucketScale
        );

    /**
     *  @notice Returns information about the pool EMA (Exponential Moving Average) variables.
     *  @return debtEma   Exponential debt moving average.
     *  @return lupColEma Exponential LUP * pledged collateral moving average.
     */
    function emasInfo()
        external
        view
        returns (
            uint256 debtEma,
            uint256 lupColEma
    );

    /**
     *  @notice Returns information about pool inflator.
     *  @return inflatorSnapshot A snapshot of the last inflator value.
     *  @return lastUpdate       The timestamp of the last `inflatorSnapshot` update.
     */
    function inflatorInfo()
        external
        view
        returns (
            uint256 inflatorSnapshot,
            uint256 lastUpdate
    );

    /**
     *  @notice Returns information about pool interest rate.
     *  @return interestRate       Current interest rate in pool.
     *  @return interestRateUpdate The timestamp of the last interest rate update.
     */
    function interestRateInfo()
        external
        view
        returns (
            uint256 interestRate,
            uint256 interestRateUpdate
        );


    /**
     *  @notice Returns details about kicker balances.
     *  @param  kicker    The address of the kicker to retrieved info for.
     *  @return claimable Amount of quote token kicker can claim / withdraw from pool at any time.
     *  @return locked    Amount of quote token kicker locked in auctions (as bonds).
     */
    function kickerInfo(address kicker)
        external
        view
        returns (
            uint256 claimable,
            uint256 locked
        );

    /**
     *  @notice Mapping of buckets indexes and owner addresses to {Lender} structs.
     *  @param  index            Bucket index.
     *  @param  lp               Address of the liquidity provider.
     *  @return lpBalance        Amount of LPs owner has in current bucket.
     *  @return lastQuoteDeposit Time the user last deposited quote token.
     */
    function lenderInfo(
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
     *  @notice Returns information about pool loans.
     *  @return maxBorrower       Borrower address with highest threshold price.
     *  @return maxThresholdPrice Highest threshold price in pool.
     *  @return noOfLoans         Total number of loans.
     */
    function loansInfo()
        external
        view
        returns (
            address maxBorrower,
            uint256 maxThresholdPrice,
            uint256 noOfLoans
    );

    /**
     *  @notice Returns information about pool reserves.
     *  @return liquidationBondEscrowed Amount of liquidation bond across all liquidators.
     *  @return reserveAuctionUnclaimed Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
     *  @return reserveAuctionKicked    Time a Claimable Reserve Auction was last kicked.
     */
    function reservesInfo()
        external
        view
        returns (
            uint256 liquidationBondEscrowed,
            uint256 reserveAuctionUnclaimed,
            uint256 reserveAuctionKicked
    );

    /**
     *  @notice Returns the `pledgedCollateral` state variable.
     *  @return The total pledged collateral in the system, in WAD units.
     */
    function pledgedCollateral() external view returns (uint256);

}