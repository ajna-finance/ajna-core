// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { PoolState } from "./PoolState.sol";

import { IBorrowerManager } from "../interfaces/IBorrowerManager.sol";
import { IInterest }        from "../interfaces/IInterest.sol";

import { Maths } from "../libraries/Maths.sol";

/**
 *  @notice Interest related functionality
 */
abstract contract Interest is IInterest, PoolState {

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;

    uint256 public inflatorSnapshot; // RAY
    uint256 public lastInflatorSnapshotUpdate;
    uint256 public previousRate; // WAD
    uint256 public override previousRateUpdate;

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @dev    Only adds debt if a borrower has already initiated a debt position
     *  @param  borrower_ Pointer to the struct which is accumulating interest on their debt
     */
    function accumulateBorrowerInterest(IBorrowerManager.BorrowerInfo storage borrower_) internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt += getPendingInterest(
                borrower_.debt,
                inflatorSnapshot,
                borrower_.inflatorSnapshot
            );
        }
        borrower_.inflatorSnapshot = inflatorSnapshot;
    }

    /**
     *  @notice Update the global borrower inflator
     *  @dev    Requires time to have passed between update calls
     */
    function accumulatePoolInterest() internal {
        if (block.timestamp - lastInflatorSnapshotUpdate != 0) {
            uint256 pendingInflator    = getPendingInflator();                                              // RAY
            totalDebt                  += getPendingInterest(totalDebt, pendingInflator, inflatorSnapshot); // WAD
            inflatorSnapshot           = pendingInflator;                                                   // RAY
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    /**
     *  @notice Calculate the pending inflator based upon previous rate and last update
     *  @return The new pending inflator value as a RAY
     */
    function getPendingInflator() public view returns (uint256) {
        // calculate annualized interest rate
        uint256 spr = Maths.wadToRay(previousRate) / SECONDS_PER_YEAR;
        // secondsSinceLastUpdate is unscaled
        uint256 secondsSinceLastUpdate = block.timestamp - lastInflatorSnapshotUpdate;
        return Maths.rmul(inflatorSnapshot, Maths.rpow(Maths.ONE_RAY + spr, secondsSinceLastUpdate));
    }

    /**
     *  @notice Calculate the amount of unaccrued interest for a specified amount of debt
     *  @param  debt_            WAD - A debt amount (pool, bucket, or borrower)
     *  @param  pendingInflator_ RAY - The next debt inflator value
     *  @param  currentInflator_ RAY - The current debt inflator value
     *  @return interest_        WAD - The additional debt pending accumulation
     */
    function getPendingInterest(uint256 debt_, uint256 pendingInflator_, uint256 currentInflator_) internal pure returns (uint256) {
        // To preserve precision, multiply WAD * RAY = RAD, and then scale back down to WAD
        return Maths.radToWadTruncate(debt_ * (Maths.rdiv(pendingInflator_, currentInflator_) - Maths.ONE_RAY));
    }

    /**
     *  @notice Returns the amount of pending (unaccrued) interest for a given bucket.
     *  @param  price_    The price of the bucket to query.
     *  @return interest_ The current amount of unaccrued interest againt the queried bucket.
     */
    function getPendingBucketInterest(uint256 price_) external view returns (uint256) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        return debt != 0 ? getPendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    /**
     *  @notice Calculate unaccrued interest for the pool, which may be added to totalDebt
     *  @notice to discover pending pool debt
     *  @return interest_ - Unaccumulated pool interest, WAD
     */
    function getPendingPoolInterest() external view returns (uint256) {
        return totalDebt != 0 ? getPendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

    function updateInterestRate() external override {
        // RAY
        uint256 actualUtilization = getPoolActualUtilization();
        if (actualUtilization != 0 && previousRateUpdate < block.timestamp && getPoolCollateralization() > Maths.ONE_WAD) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(previousRate, (actualUtilization + Maths.ONE_WAD - getPoolTargetUtilization()));
            previousRateUpdate = block.timestamp;

            emit UpdateInterestRate(oldRate, previousRate);
        }
    }

}
