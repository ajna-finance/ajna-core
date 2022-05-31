// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

/**
 *  @title Ajna Pool Interest Manager
 *  @dev   Used for TODO:
 */
interface IInterest {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate_ Old pool interest rate.
     *  @param  newRate_ New pool interest rate.
     */
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `inflatorSnapshot` state variable.
     *  @return inflatorSnapshot_ A snapshot of the last inflator value, in RAY units.
     */
    function inflatorSnapshot() external view returns (uint256 inflatorSnapshot_);

    /**
     *  @notice Returns the `lastInflatorSnapshotUpdate` state variable.
     *  @return lastInflatorSnapshotUpdate_ The timestamp of the last `inflatorSnapshot` update.
     */
    function lastInflatorSnapshotUpdate() external view returns (uint256 lastInflatorSnapshotUpdate_);

    /**
     *  @notice Returns the `minFee` state variable.
     *  @return minFee_ TODO
     */
    function minFee() external view returns (uint256 minFee_);

    /**
     *  @notice Returns the `previousRate` state variable.
     *  @return previousRate_ TODO
     */
    function previousRate() external view returns (uint256 previousRate_);

    /**
     *  @notice Returns the `previousRateUpdate` state variable.
     *  @return previousRateUpdate_ The timestamp of the last rate update.
     */
    function previousRateUpdate() external view returns (uint256 previousRateUpdate_);

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Called to update the pool interest rate when actual > target utilization.
     */
    function updateInterestRate() external;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns the amount of pending (unaccrued) interest for a given bucket.
     *  @param  price_    The price of the bucket to query.
     *  @return interest_ The current amount of unaccrued interest againt the queried bucket.
     */
    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_);

    /**
     *  @notice Calculate unaccrued interest for the pool, which may be added to totalDebt
     *          to discover pending pool debt.
     *  @return interest_ Unaccumulated pool interest, in WAD units.
     */
    function getPendingPoolInterest() external view returns (uint256 interest_);

    /**
     *  @notice Calculate the pending inflator based upon previous rate and last update
     *  @return pendingInflator_ new pending inflator value as a RAY
     */
    function getPendingInflator() external view returns (uint256 pendingInflator_);
}
