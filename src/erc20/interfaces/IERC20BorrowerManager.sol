// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IBorrowerManager } from "../../base/interfaces/IBorrowerManager.sol";

/**
 *  @title Ajna ERC20 Borrower Manager
 *  @dev   Used to manage borrower positions of ERC-20 tokens.
 */

interface IERC20BorrowerManager is IBorrowerManager {

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Mapping of borrower addresses to {BorrowerInfo} structs.
     *  @dev    NOTE: Cannot use appended underscore syntax for return params since struct is used.
     *  @param  borrower_           Address of the borrower.
     *  @return debt                Amount of debt that the borrower has, in quote token.
     *  @return collateralDeposited Amount of collateral that the borrower has deposited, in collateral token.
     *  @return inflatorSnapshot    Snapshot of inflator value used to track interest on loans.
     */
    function borrowers(address borrower_) external view returns (uint256 debt, uint256 collateralDeposited, uint256 inflatorSnapshot);


    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding borrower related info per price bucket.
     *  @param  debt                Borrower debt, WAD units.
     *  @param  collateralDeposited Collateral deposited by borrower, WAD units.
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY units.
     */
    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot;
    }

    /***********************************/
    /*** Borrower View Functions ***/
    /***********************************/

    /**
     *  @notice Returns a tuple of information about a given borrower.
     *  @param  borrower_                 Address of the borrower.
     *  @return debt_                     Amount of debt that the borrower has, in quote token.
     *  @return pendingDebt_              Amount of unaccrued debt that the borrower has, in quote token.
     *  @return collateralDeposited_      Amount of collateral that tne borrower has deposited, in collateral token.
     *  @return collateralEncumbered_     Amount of collateral that the borrower has encumbered, in collateral token.
     *  @return collateralization_        Collateral ratio of the borrower's pool position.
     *  @return borrowerInflatorSnapshot_ Snapshot of the borrower's inflator value.
     *  @return inflatorSnapshot_         Snapshot of the pool's inflator value.
     */
    function getBorrowerInfo(address borrower_) external view returns (
        uint256 debt_,
        uint256 pendingDebt_,
        uint256 collateralDeposited_,
        uint256 collateralEncumbered_,
        uint256 collateralization_,
        uint256 borrowerInflatorSnapshot_,
        uint256 inflatorSnapshot_
    );

}
