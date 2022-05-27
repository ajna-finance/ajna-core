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
     *  @notice Returns the `previousRateUpdate` state variable.
     *  @return previousRateUpdate_ The timestamp of the last rate update.
     */
    function previousRateUpdate() external view returns (uint256 previousRateUpdate_);

    /**********************************************/
    /*** Interest Management External Functions ***/
    /**********************************************/

    /**
     *  @notice Called to update the pool interest rate when actual > target utilization.
     */
    function updateInterestRate() external;
}
