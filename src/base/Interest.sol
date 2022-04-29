// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {Maths} from "../libraries/Maths.sol";
import {IPool} from "../interfaces/IPool.sol";

/// @notice Interest related functionality
abstract contract Interest {

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;
    uint256 public previousRate; // WAD
    uint256 public inflatorSnapshot; // RAY
    uint256 public lastInflatorSnapshotUpdate;

    // uint256 public previousRateUpdate;

    // event UpdateInterestRate(uint256 oldRate, uint256 newRate);

    // /// @notice Update the global borrower inflator
    // /// @dev Requires time to have passed between update calls
    // function accumulatePoolInterest() private {
    //     if (block.timestamp - lastInflatorSnapshotUpdate != 0) {
    //         // RAY
    //         uint256 pendingInflator = getPendingInflator();

    //         // RAD
    //         totalDebt += getPendingInterest(totalDebt, pendingInflator, inflatorSnapshot);

    //         inflatorSnapshot = pendingInflator;
    //         lastInflatorSnapshotUpdate = block.timestamp;
    //     }
    // }

    // /// @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
    // /// @param _borrower Pointer to the struct which is accumulating interest on their debt
    // /// @dev Only adds debt if a borrower has already initiated a debt position
    // function accumulateBorrowerInterest(BorrowerInfo storage _borrower) private {
    //     if (_borrower.debt != 0 && _borrower.inflatorSnapshot != 0) {
    //         _borrower.debt += getPendingInterest(
    //             _borrower.debt,
    //             inflatorSnapshot,
    //             _borrower.inflatorSnapshot
    //         );
    //     }
    //     _borrower.inflatorSnapshot = inflatorSnapshot;
    // }

    /// @notice Calculate the pending inflator based upon previous rate and last update
    /// @return The new pending inflator value as a RAY
    function getPendingInflator() public view returns (uint256) {
        // calculate annualized interest rate
        uint256 spr = Maths.wadToRay(previousRate) / SECONDS_PER_YEAR;
        // secondsSinceLastUpdate is unscaled
        uint256 secondsSinceLastUpdate = Maths.sub(block.timestamp, lastInflatorSnapshotUpdate);

        return
            Maths.rmul(
                inflatorSnapshot,
                Maths.rpow(Maths.add(Maths.ONE_RAY, spr), secondsSinceLastUpdate)
            );
    }

    /// @notice Calculate the amount of unaccrued interest for a specified amount of debt
    /// @param _debt RAD - The total book debt
    /// @param _pendingInflator RAY - The next debt inflator value
    /// @param _currentInflator RAY - The current debt inflator value
    /// @return RAD - The additional debt pending accumulation
    function getPendingInterest(
        uint256 _debt,
        uint256 _pendingInflator,
        uint256 _currentInflator
    ) internal pure returns (uint256) {
        return
            Maths.rayToRad(
                Maths.rmul(
                    Maths.radToRay(_debt),
                    Maths.sub(Maths.rmul(_pendingInflator, _currentInflator), Maths.ONE_RAY)
                )
            );
    }

    // // TODO: fix this
    // /// @notice Called by lenders to update interest rate of the pool when actual > target utilization
    // function updateInterestRate() external {
    //     // RAY
    //     uint256 actualUtilization = IPool(address(this)).getPoolActualUtilization();
    //     if (
    //         actualUtilization != 0 &&
    //         previousRateUpdate < block.timestamp &&
    //         IPool(address(this)).getPoolCollateralization() > Maths.ONE_RAY
    //     ) {
    //         uint256 oldRate = previousRate;
    //         // IPool(address(this)).accumulatePoolInterest();

    //         previousRate = Maths.wmul(
    //             previousRate,
    //             (
    //                 Maths.sub(
    //                     Maths.add(Maths.rayToWad(actualUtilization), Maths.ONE_WAD),
    //                     Maths.rayToWad(IPool(address(this)).getPoolTargetUtilization())
    //                 )
    //             )
    //         );
    //         previousRateUpdate = block.timestamp;
    //         emit UpdateInterestRate(oldRate, previousRate);
    //     }
    // }

}
