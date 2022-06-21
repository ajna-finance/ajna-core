// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IBorrowerManager } from "../../base/interfaces/IBorrowerManager.sol";

/**
 *  @title Ajna NFT Borrower Manager
 *  @dev   Used to manage borrower positions of ERC-721 tokens.
 */
interface IERC721BorrowerManager is IBorrowerManager {

    /***************/
    /*** Structs ***/
    /***************/

     /**
     *  @notice Struct holding borrower related info per price bucket, for borrowers using NFTs as collateral.
     *  @param  debt                Borrower debt, WAD units.
     *  @param  collateralDeposited OZ Enumberable Set tracking the tokenIds of collateral that have been deposited
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY units.
     */
    struct NFTBorrowerInfo {
        uint256   debt;
        EnumerableSet.UintSet collateralDeposited;
        uint256   inflatorSnapshot;
    }

    /***********************************/
    /*** Borrower View Functions ***/
    /***********************************/

    /**
     *  @notice Returns a tuple of information about a given NFT borrower.
     *  @param  borrower_                 Address of the borrower.
     *  @return debt_                     Amount of debt that the borrower has, in quote token.
     *  @return pendingDebt_              Amount of unaccrued debt that the borrower has, in quote token.
     *  @return collateralDeposited_      Amount of collateral that tne borrower has deposited, in NFT tokens.
     *  @return collateralEncumbered_     Amount of collateral that the borrower has encumbered, in NFT token.
     *  @return collateralization_        Collateral ratio of the borrower's pool position.
     *  @return borrowerInflatorSnapshot_ Snapshot of the borrower's inflator value.
     *  @return inflatorSnapshot_         Snapshot of the pool's inflator value.
     */
    function getBorrowerInfo(address borrower_) external view returns (
        uint256 debt_,
        uint256 pendingDebt_,
        uint256[] memory collateralDeposited_,
        uint256 collateralEncumbered_,
        uint256 collateralization_,
        uint256 borrowerInflatorSnapshot_,
        uint256 inflatorSnapshot_
    );

}
