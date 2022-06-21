// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { InterestManager } from "./InterestManager.sol";

import { IBorrowerManager } from "./interfaces/IBorrowerManager.sol";

import { Maths } from "../libraries/Maths.sol";

/**
 *  @notice Borrower Management related functionality
 */
abstract contract BorrowerManager is IBorrowerManager, InterestManager {

    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) public view override returns (uint256) {
        if (lup != 0 && debt_ != 0) {
            return Maths.wrdivw(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.WAD;
    }

    function estimatePrice(uint256 amount_) public view override returns (uint256) {
        return _estimatePrice(amount_, lup == 0 ? hpb : lup);
    }

}
