// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Buckets } from "./Buckets.sol";

import { IPool }      from "../interfaces/IPool.sol";
import { IPoolState } from "../interfaces/IPoolState.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

/**
 *  @notice Pool State Management related functionality
 */
abstract contract PoolState is IPoolState, Buckets {

    uint256 public override totalCollateral;    // [WAD]
    uint256 public override totalQuoteToken;    // [WAD]

    /** @dev WAD The total global debt, in quote tokens, across all buckets in the pool */
    uint256 public totalDebt;

    /** @dev The count of unique borrowers in pool */
    uint256 public totalBorrowers;

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _encumberedCollateral(uint256 debt_) internal view returns (uint256) {
        // Calculate encumbrance as RAY to maintain precision
        return debt_ != 0 ? Maths.wwdivr(debt_, lup) : 0;
    }

    function _poolActualUtilization(uint256 totalDebt_) internal view returns (uint256) {
        if (totalDebt_ != 0) {
            uint256 lupMulDebt = Maths.wmul(lup, totalDebt_);
            return Maths.wdiv(lupMulDebt, lupMulDebt + pdAccumulator);
        }
        return 0;
    }

    function _poolCollateralization(uint256 totalDebt_) internal view returns (uint256) {
        if (totalDebt_ != 0) {
            return Maths.wrdivw(totalCollateral, Maths.wwdivr(totalDebt_, lup));
        }
        return Maths.ONE_WAD;
    }

    function _poolMinDebtAmount(uint256 totalDebt_, uint256 totalBorrowers_) internal pure returns (uint256) {
        return totalDebt_ != 0 ? Maths.wdiv(totalDebt_, Maths.wad(Maths.max(1000, totalBorrowers_ * 10))) : 0;
    }

    function _poolTargetUtilization(uint256 totalDebt_) internal view returns (uint256) {
        return Maths.wdiv(Maths.ONE_WAD, _poolCollateralization(totalDebt_));
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256) {
        // Calculate encumbrance as RAY to maintain precision
        return _encumberedCollateral(debt_);
    }

    function getMinimumPoolPrice() public view override returns (uint256) {
        return totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getPoolActualUtilization() public view override returns (uint256) {
        return _poolActualUtilization(totalDebt);
    }

    function getPoolCollateralization() public view override returns (uint256) {
        return _poolCollateralization(totalDebt);
    }

    function getPoolMinDebtAmount() public view override returns (uint256) {
        return _poolMinDebtAmount(totalDebt, totalBorrowers);
    }

    function getPoolTargetUtilization() public view override returns (uint256) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
    }
}
