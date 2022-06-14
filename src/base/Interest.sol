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

    uint256 public constant SECONDS_PER_YEAR    = 3600 * 24 * 365;
    uint256 public constant SECONDS_PER_HALFDAY = 43200;
    uint256 public constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;

    uint256 public constant RATE_INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 public constant RATE_DECREASE_COEFFICIENT = 0.9 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override inflatorSnapshot;            // [RAY]
    uint256 public override lastInflatorSnapshotUpdate;  // [SEC]
    uint256 public override minFee;                      // [WAD]
    uint256 public override interestRate;                // [WAD]
    uint256 public override interestRateUpdate;          // [SEC]

    /**************************/
    /*** External Functions ***/
    /**************************/

    function updateInterestRate() internal {
        // RAY
        uint256 poolCollateralization =  getPoolCollateralization();
        if (block.timestamp - interestRateUpdate > SECONDS_PER_HALFDAY && poolCollateralization > Maths.ONE_WAD) {
            uint256 oldRate           = interestRate;
            uint256 actualUtilization = getPoolActualUtilization();
            uint256 targetUtilization = Maths.wdiv(Maths.ONE_WAD, poolCollateralization);

            if (actualUtilization * 2 > targetUtilization + Maths.ONE_WAD) {
                interestRate = Maths.wmul(interestRate, RATE_INCREASE_COEFFICIENT);
            } else if (targetUtilization >  (actualUtilization + Maths.ONE_WAD) / 2) {
                interestRate = Maths.wmul(interestRate, RATE_DECREASE_COEFFICIENT);
            }
            interestRateUpdate = block.timestamp;

            emit UpdateInterestRate(oldRate, interestRate);
        }
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @dev    Only adds debt if a borrower has already initiated a debt position
     *  @param  borrower_ Pointer to the struct which is accumulating interest on their debt
     */
    function accumulateBorrowerInterest(IBorrowerManager.BorrowerInfo memory borrower_) internal view {
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

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        return debt != 0 ? getPendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    function getPendingInflator() public view returns (uint256) {
        // Calculate annualized interest rate
        uint256 spr = Maths.wadToRay(interestRate) / SECONDS_PER_YEAR;
        // secondsSinceLastUpdate is unscaled
        uint256 secondsSinceLastUpdate = block.timestamp - lastInflatorSnapshotUpdate;
        return Maths.rmul(inflatorSnapshot, Maths.rpow(Maths.ONE_RAY + spr, secondsSinceLastUpdate));
    }

    function getPendingPoolInterest() external view returns (uint256) {
        return totalDebt != 0 ? getPendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

}
