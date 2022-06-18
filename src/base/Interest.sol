// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

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

    uint256 public constant SECONDS_PER_YEAR    = 3_600 * 24 * 365;
    uint256 public constant SECONDS_PER_HALFDAY = 43_200;
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
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @dev    Only adds debt if a borrower has already initiated a debt position
     *  @dev    Only used by Borrowers using fungible tokens as collateral     
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
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @param borrower_ Pointer to the struct which is accumulating interest on their debt
     *  @param  inflator_ Pool inflator
     *  @dev Only used by Borrowers using NFTs as collateral
     *  @dev Only adds debt if a borrower has already initiated a debt position
    */
    function _accumulateNFTBorrowerInterest(IBorrowerManager.NFTBorrowerInfo storage borrower_, uint256 inflator_) internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt += _pendingInterest(borrower_.debt, inflator_, borrower_.inflatorSnapshot);
        }
        borrower_.inflatorSnapshot = inflator_;
    }

    /**
     *  @notice Update the global borrower inflator
     *  @dev    Requires time to have passed between update calls
     */
    function _accumulatePoolInterest(uint256 totalDebt_, uint256 inflator_) internal returns (uint256 curDebt_, uint256 curInflator_) {
        uint256 elapsed  = block.timestamp - lastInflatorSnapshotUpdate;
        if (elapsed != 0) {
            curInflator_ = _pendingInflator(interestRate, inflator_, elapsed);                 // RAY
            curDebt_     = totalDebt_ + _pendingInterest(totalDebt_, curInflator_, inflator_); // WAD

            totalDebt                  = curDebt_;
            inflatorSnapshot           = curInflator_; // RAY
            lastInflatorSnapshotUpdate = block.timestamp;
        } else {
            curInflator_ = inflator_;
            curDebt_     = totalDebt_;
        }
    }

    /**
     *  @notice Calculate the pending inflator
     *  @param  interestRate_    WAD - The current interest rate value.
     *  @param  inflator_        RAY - The current inflator value
     *  @param  elapsed_         Seconds since last inflator update
     *  @return pendingInflator_ WAD - The pending inflator value
     */
    function _pendingInflator(uint256 interestRate_, uint256 inflator_, uint256 elapsed_) internal pure returns (uint256) {
        // Calculate annualized interest rate
        uint256 spr = Maths.wadToRay(interestRate_) / SECONDS_PER_YEAR;
        // secondsSinceLastUpdate is unscaled
        return Maths.rmul(inflator_, Maths.rpow(Maths.ONE_RAY + spr, elapsed_));
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

    function _updateInterestRate(uint256 curDebt_) internal {
        uint256 poolCollateralization = _poolCollateralization(curDebt_);
        if (block.timestamp - interestRateUpdate > SECONDS_PER_HALFDAY && poolCollateralization > Maths.ONE_WAD) {
            uint256 oldRate          = interestRate;
            int256 actualUtilization = int256(_poolActualUtilization(curDebt_));
            int256 targetUtilization = int256(Maths.wdiv(Maths.ONE_WAD, poolCollateralization));

            int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
            int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

            if (decreaseFactor < increaseFactor - 10**18) {
                interestRate = Maths.wmul(interestRate, RATE_INCREASE_COEFFICIENT);
            } else if (decreaseFactor > 10**18 - increaseFactor) {
                interestRate = Maths.wmul(interestRate, RATE_DECREASE_COEFFICIENT);
            }
            interestRateUpdate = block.timestamp;

            emit UpdateInterestRate(oldRate, interestRate);
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        return debt != 0 ? _pendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    function getPendingInflator() public view returns (uint256) {
        return _pendingInflator(interestRate, inflatorSnapshot, block.timestamp - lastInflatorSnapshotUpdate);
    }

    function getPendingPoolInterest() external view returns (uint256) {
        return totalDebt != 0 ? _pendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

}
