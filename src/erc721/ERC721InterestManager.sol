// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IERC721BorrowerManager } from "./interfaces/IERC721BorrowerManager.sol";

import { InterestManager } from "../base/InterestManager.sol";

/**
 *  @notice Interest related functionality.
 */
abstract contract ERC721InterestManager is InterestManager {

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @param borrower_ Pointer to the struct which is accumulating interest on their debt
     *  @param  inflator_ Pool inflator
     *  @dev Only used by Borrowers using NFTs as collateral
     *  @dev Only adds debt if a borrower has already initiated a debt position
    */
    function _accumulateBorrowerInterest(IERC721BorrowerManager.NFTBorrowerInfo storage borrower_, uint256 inflator_) internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt += _pendingInterest(borrower_.debt, inflator_, borrower_.inflatorSnapshot);
        }
        borrower_.inflatorSnapshot = inflator_;
    }

}
