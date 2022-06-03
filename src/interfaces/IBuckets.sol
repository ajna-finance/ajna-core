// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IBuckets {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `hpb` state variable.
     *  @return hpb_ The price value of the current Highest Price Bucket (HPB), in WAD units.
     */
    function hpb() external view returns (uint256 hpb_);

    /**
     *  @notice Returns the `lup` state variable.
     *  @return lup_ The price value of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     */
    function lup() external view returns (uint256 lup_);

    /**
     *  @notice Returns the `pdAccumulator` state variable.
     *  @return pdAccumulator_ The sum of all available deposits * price, in WAD units.
     */
    function pdAccumulator() external view returns (uint256 pdAccumulator_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice struct holding bucket info
     *  @param price            Current bucket price, WAD
     *  @param up               Upper utilizable bucket price, WAD
     *  @param down             Next utilizable bucket price, WAD
     *  @param onDeposit        Quote token on deposit in bucket, WAD
     *  @param debt             Accumulated bucket debt, WAD
     *  @param inflatorSnapshot Bucket inflator snapshot, RAY
     *  @param lpOutstanding    Outstanding Liquidity Provider LP tokens in a bucket, RAY
     *  @param collateral       Current collateral tokens deposited in the bucket, RAY
     */
    struct Bucket {
        uint256 price;
        uint256 up;
        uint256 down;
        uint256 onDeposit;
        uint256 debt;
        uint256 inflatorSnapshot;
        uint256 lpOutstanding;
        uint256 collateral;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Get a bucket struct for a given price.
     *  @param  price_            The price of the bucket to retrieve.
     *  @return bucketPrice_      The price of the bucket.
     *  @return up_               The price of the next higher priced utlized bucket.
     *  @return down_             The price of the next lower price utilized bucket.
     *  @return onDeposit_        The amount of quote token available as liquidity in the bucket.
     *  @return debt_             The amount of quote token debt in the bucket.
     *  @return bucketInflator_   The inflator snapshot value in the bucket.
     *  @return lpOutstanding_    The amount of outstanding LP tokens in the bucket.
     *  @return bucketCollateral_ The amount of collateral posted in the bucket.
     */
    function bucketAt(uint256 price_)
        external
        view
        returns (
            uint256 bucketPrice_,
            uint256 up_,
            uint256 down_,
            uint256 onDeposit_,
            uint256 debt_,
            uint256 bucketInflator_,
            uint256 lpOutstanding_,
            uint256 bucketCollateral_
        );

    /**
     *  @notice Estimate the price at which a loan can be taken
     *  @param  amount_ The amount of quote tokens desired to borrow, WAD
     *  @param  hpb_    The current highest price bucket of the pool, WAD
     *  @return price_  The estimated price at which the loan can be taken, WAD
     */
    function estimatePrice(uint256 amount_, uint256 hpb_) external view returns (uint256 price_);

    /**
     *  @notice Returns whether a bucket price has been initialized or not.
     *  @param  price_         The price of the bucket.
     *  @return isInitialized_ Boolean indicating if the bucket has been initialized at this price.
     */
    function isBucketInitialized(uint256 price_) external view returns (bool isInitialized_);

    /**
     *  @notice Returns the current Highest Price Bucket (HPB).
     *  @dev    Starting at the current HPB, iterate through down pointers until a new HPB found.
     *  @dev    HPB should have at on deposit or debt different than 0.
     *  @return newHpb_ The current Highest Price Bucket (HPB).
     */
    function getHpb() external view returns (uint256 newHpb_);

    /**
     *  @notice Returns the current Highest Utilizable Price (HUP) bucket.
     *  @dev    Starting at the LUP, iterate through down pointers until no quote tokens are available.
     *  @dev    LUP should always be >= HUP.
     *  @return hup_ The current Highest Utilizable Price (HUP) bucket.
     */
    function getHup() external view returns (uint256 hup_);

}
