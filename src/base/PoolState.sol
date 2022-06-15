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

    function getPoolMinDebtAmount() public view override returns (uint256) {
        return totalDebt != 0 ? Maths.wdiv(totalDebt, Maths.wad(Maths.max(1000, totalBorrowers * 10))) : 0;
    }

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256) {
        // Calculate encumbrance as RAY to maintain precision
        return debt_ != 0 ? Maths.wwdivr(debt_, lup) : 0;
    }

    function getMinimumPoolPrice() public view override returns (uint256) {
        return totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getPoolActualUtilization() public view override returns (uint256) {
        if (totalDebt != 0) {
            uint256 lupMulDebt = Maths.wmul(lup, totalDebt);
            return Maths.wdiv(lupMulDebt, lupMulDebt + pdAccumulator);
        }
        return 0;
    }

    function getPoolCollateralization() public view override returns (uint256) {
        if (lup != 0 && totalDebt != 0) {
            return Maths.wrdivw(totalCollateral, getEncumberedCollateral(totalDebt));
        }
        return Maths.ONE_WAD;
    }

    function getPoolTargetUtilization() public view override returns (uint256) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
    }
}
