// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { Interest } from "./Interest.sol";

import { IBorrowerManager } from "../interfaces/IBorrowerManager.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

/**
 * @notice Lender Management related functionality
*/
abstract contract BorrowerManager is IBorrowerManager, Interest {

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public override borrowers;

    function getBorrowerInfo(address borrower_)
        public view override returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256 collateralDeposited_,
            uint256 collateralEncumbered_,
            uint256 collateralization_,
            uint256 borrowerInflatorSnapshot_,
            uint256 inflatorSnapshot_
        )
    {
        BorrowerInfo memory borrower = borrowers[borrower_];
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization = Maths.ONE_WAD;

        if (borrower.debt > 0 && borrower.inflatorSnapshot != 0) {
            borrowerPendingDebt  += getPendingInterest(borrower.debt, getPendingInflator(), borrower.inflatorSnapshot);
            collateralEncumbered  = getEncumberedCollateral(borrowerPendingDebt);
            collateralization     = Maths.wrdivw(borrower.collateralDeposited, collateralEncumbered);
        }

        return (
            borrower.debt,
            borrowerPendingDebt,
            borrower.collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
    }

    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) public view override returns (uint256 borrowerCollateralization_) {
        if (lup != 0 && debt_ != 0) {
            return Maths.wrdivw(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.ONE_WAD;
    }

    function estimatePriceForLoan(uint256 amount_) public view override returns (uint256 price_) {
        return estimatePrice(amount_, lup == 0 ? hpb : lup);
    }

}
