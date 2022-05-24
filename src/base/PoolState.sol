// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { Buckets } from "./Buckets.sol";

import { IPool }          from "../interfaces/IPool.sol";
import { IPoolState }          from "../interfaces/IPoolState.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";


// TODO: MOVE totalDebt here and derive Interest from PoolState

/**
 * @notice Pool State Management related functionality
*/
abstract contract PoolState is IPoolState, Buckets {

    uint256 public override totalCollateral;    // [WAD]
    uint256 public override totalQuoteToken;    // [WAD]

    /// @dev WAD The total global debt, in quote tokens, across all buckets in the pool
    uint256 public totalDebt;

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256 encumbrance_) {
        // Calculate encumbrance as RAY to maintain precision
        encumbrance_ = debt_ != 0 ? Maths.wwdivr(debt_, lup) : 0;
    }

    function getMinimumPoolPrice() public view override returns (uint256 minPrice_) {
        minPrice_ = totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getPoolActualUtilization() public view override returns (uint256 poolActualUtilization_) {
        if (totalDebt == 0) {
            return 0;
        }
        return Maths.wdiv(totalDebt, totalQuoteToken + totalDebt);
    }

    function getPoolCollateralization() public view override returns (uint256 poolCollateralization_) {
        if (lup != 0 && totalDebt != 0) {
            return Maths.wdiv(totalCollateral, getEncumberedCollateral(totalDebt));
        }
        return Maths.ONE_WAD;
    }

    function getPoolTargetUtilization() public view override returns (uint256 poolTargetUtilization_) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
    }
}
