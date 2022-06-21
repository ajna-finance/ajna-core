// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 *  @title Ajna Pool
 *  @dev   Used to manage lender and borrower positions of ERC-20 tokens.
 */
interface IBorrowerManager {

    /***********************************/
    /*** Borrower View Functions ***/
    /***********************************/

    /**
     *  @notice Estimate the price for which a loan can be taken.
     *  @param  amount_  Amount of debt to draw.
     *  @return price_   Price of the loan.
     */
    function estimatePrice(uint256 amount_) external view returns (uint256 price_);

    /**
     *  @notice Returns the collateralization based on given collateral deposited and debt.
     *  @dev    Supports passage of collateralDeposited and debt to enable calculation of potential borrower collateralization states, not just current.
     *  @param  collateralDeposited_       Collateral amount to calculate a collateralization ratio for, in RAY units.
     *  @param  debt_                      Debt position to calculate encumbered quotient, in RAY units.
     *  @return borrowerCollateralization_ The current collateralization of the borrowers given totalCollateral and totalDebt
     */
    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) external view returns (uint256 borrowerCollateralization_);

}
