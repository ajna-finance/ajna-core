// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IERC20BorrowerManager } from "./interfaces/IERC20BorrowerManager.sol";

import { InterestManager } from "../base/InterestManager.sol";

/**
 *  @notice Interest related functionality.
 */
abstract contract ERC20InterestManager is InterestManager {

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
    function _accumulateBorrowerInterest(IERC20BorrowerManager.BorrowerInfo memory borrower_, uint256 inflator_) pure internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt += _pendingInterest(borrower_.debt, inflator_, borrower_.inflatorSnapshot);
        }
        borrower_.inflatorSnapshot = inflator_;
    }

}
