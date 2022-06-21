// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 *  @title Ajna Pool State
 *  @dev   Used for TODO: 
 */
interface IPoolState {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `totalCollateral` state variable.
     *  @return totalCollateral_ THe total amount of collateral in the system, in WAD units.
     */
    function totalCollateral() external view returns (uint256 totalCollateral_);

    /**
     *  @notice Returns the `totalQuoteToken` state variable.
     *  @return totalQuoteToken_ The total amount of quote token in the system, in WAD units.
     */
    function totalQuoteToken() external view returns (uint256 totalQuoteToken_);

    /***************************/
    /*** Pool View Functions ***/
    /***************************/

    /**
     *  @notice Returns the total encumbered collateral resulting from a given amount of debt.
     *  @dev    Used for both pool and borrower level debt.
     *  @param  debt_        Amount of debt for corresponding collateral encumbrance.
     *  @return encumbrance_ The current encumbrance of a given debt balance, in WAD units.
     */
    function getEncumberedCollateral(uint256 debt_) external view returns (uint256 encumbrance_);

    /**
     *  @notice Returns the current minimum pool price.
     *  @return minPrice_ The current minimum pool price.
     */
    function getMinimumPoolPrice() external view returns (uint256 minPrice_);

    /**
     *  @notice Gets the current utilization of the pool
     *  @dev    Will return 0 unless the pool has been borrowed from.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     */
    function getPoolActualUtilization() external view returns (uint256 poolActualUtilization_);

    /**
     *  @notice Calculate the current collateralization ratio of the pool, based on `totalDebt` and `totalCollateral`.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     */
    function getPoolCollateralization() external view returns (uint256 poolCollateralization_);

    /**
     *  @notice Gets the accepted minimum debt amount in the pool
     *  @return poolMinDebtAmount_ The accepted minimum debt amount, in WAD units.
     */
    function getPoolMinDebtAmount() external view returns (uint256 poolMinDebtAmount_);

    /**
     *  @notice Gets the current target utilization of the pool
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function getPoolTargetUtilization() external view returns (uint256 poolTargetUtilization_);

}
