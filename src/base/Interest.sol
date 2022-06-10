// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { PoolState } from "./PoolState.sol";

import { IBorrowerManager } from "../interfaces/IBorrowerManager.sol";
import { IInterest }        from "../interfaces/IInterest.sol";

import { Maths } from "../libraries/Maths.sol";

/**
 *  @notice Interest related functionality.
 */
abstract contract Interest is IInterest, PoolState {

    /*****************/
    /*** Constants ***/
    /*****************/

    uint256 public constant SECONDS_PER_YEAR   = 3600 * 24 * 365;
    uint256 public constant WAD_WEEKS_PER_YEAR = 52 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override inflatorSnapshot;            // [RAY]
    uint256 public override lastInflatorSnapshotUpdate;  // [SEC]
    uint256 public override minFee;                      // [WAD]
    uint256 public override previousRate;                // [WAD]
    uint256 public override previousRateUpdate;          // [SEC]

    /**************************/
    /*** External Functions ***/
    /**************************/

    function updateInterestRate() external override {
        // RAY
        uint256 actualUtilization = getPoolActualUtilization();
        if (actualUtilization != 0 && previousRateUpdate < block.timestamp && getPoolCollateralization() > Maths.ONE_WAD) {
            uint256 oldRate = previousRate;
            uint256 curUpdateTime = lastInflatorSnapshotUpdate;
            uint256 curInflator   = inflatorSnapshot;
            uint256 curDebt       = totalDebt;

            (uint256 poolDebt, uint256 inflator) = _accumulatePoolInterest(curDebt, curInflator, curUpdateTime);
            totalDebt         = poolDebt;
            if (curInflator   != inflator)        inflatorSnapshot           = inflator;
            if (curUpdateTime != block.timestamp) lastInflatorSnapshotUpdate = block.timestamp;

            previousRate = Maths.wmul(previousRate, (actualUtilization + Maths.ONE_WAD - getPoolTargetUtilization()));
            previousRateUpdate = block.timestamp;

            emit UpdateInterestRate(oldRate, previousRate);
        }
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @dev    Only adds debt if a borrower has already initiated a debt position
     *  @param  borrower_ Pointer to the struct which is accumulating interest on their debt
     *  @param  inflator_ Pool inflator
     */
    function _accumulateBorrowerInterest(IBorrowerManager.BorrowerInfo memory borrower_, uint256 inflator_) pure internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt += _pendingInterest(borrower_.debt, inflator_, borrower_.inflatorSnapshot);
        }
        borrower_.inflatorSnapshot = inflator_;
    }

    /**
     *  @notice Update the global borrower inflator
     *  @dev    Requires time to have passed between update calls
     */
    function _accumulatePoolInterest(uint256 totalDebt_, uint256 inflator_, uint256 lastUpdate_
    ) internal view returns (uint256 updatedDebt_, uint256 newInflator_) {
        newInflator_ = _pendingInflator(previousRate, inflator_, lastUpdate_);    // RAY
        updatedDebt_ = totalDebt_ + _pendingInterest(totalDebt_, newInflator_, inflator_); // WAD
    }

    /**
     *  @notice Calculate the amount of unaccrued interest for a specified amount of debt
     *  @param  debt_            WAD - A debt amount (pool, bucket, or borrower)
     *  @param  pendingInflator_ RAY - The next debt inflator value
     *  @param  currentInflator_ RAY - The current debt inflator value
     *  @return interest_        WAD - The additional debt pending accumulation
     */
    function _pendingInterest(uint256 debt_, uint256 pendingInflator_, uint256 currentInflator_) internal pure returns (uint256) {
        // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
        return Maths.radToWadTruncate(debt_ * (Maths.rdiv(pendingInflator_, currentInflator_) - Maths.ONE_RAY));
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        return debt != 0 ? _pendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    function getPendingInflator() public view returns (uint256) {
        return _pendingInflator(previousRate, inflatorSnapshot, lastInflatorSnapshotUpdate);
    }

    function _pendingInflator(uint256 previousRate_, uint256 inflator_, uint256 lastUpdate_) internal view returns (uint256) {
        uint256 secondsSinceLastUpdate = block.timestamp - lastUpdate_;
        if (secondsSinceLastUpdate != 0) {
            // Calculate annualized interest rate
            uint256 spr = Maths.wadToRay(previousRate_) / SECONDS_PER_YEAR;
            // secondsSinceLastUpdate is unscaled
            return Maths.rmul(inflator_, Maths.rpow(Maths.ONE_RAY + spr, secondsSinceLastUpdate));
        }
        return inflator_;
    }

    function getPendingPoolInterest() external view returns (uint256) {
        return totalDebt != 0 ? _pendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

}
