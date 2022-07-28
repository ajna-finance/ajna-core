// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./IQueue.sol";

abstract contract Queue is IQueue {

    address public override loanQueueHead;

    mapping(address => LoanInfo) public override loans;

    /************************/
    /***  Queue functions ***/
    /************************/

    /**
     *  @notice Search to the given radius for the correct previous borrower.
     *  @dev    Called by _updateLoanQueue if the newPrev_ position is incorrect
     *  @param  radius_         Distance checked to find lower thresholdPrice
     *  @param  thresholdPrice_ Debt / collateralDeposited
     *  @param  newPrev_        Previous location the caller believes points to their loan
     *  @param  borrower_       Borrower whose TP might be changing, thus should be ignored
     *  @return newPrev         Corrected previous borrower that now comes before placed loan (new)
     *  @return newPrevLoan     Corrected previous loan that now comes before placed loan (new)
     */
    function _searchRadius(uint256 radius_, uint256 thresholdPrice_, address newPrev_, address borrower_) internal returns (address, LoanInfo memory) {
        address current = newPrev_;
        LoanInfo memory currentLoan = loans[current];
        LoanInfo memory nextLoan;

        for (uint256 i = 0; i < radius_;) {
            nextLoan = loans[currentLoan.next];

            if (current != borrower_ && (nextLoan.thresholdPrice <= thresholdPrice_)) {
                break;
            }

            current = loans[current].next;
            currentLoan = nextLoan;
            unchecked {
                ++i;
            }
        }

        require(currentLoan.next == borrower_ || loans[currentLoan.next].thresholdPrice <= thresholdPrice_, "B:S:SRCH_RDS_FAIL");
        return (current, currentLoan);
    }

    /**
     *  @notice Called by borrower methods to update a loan position.
     *  @param  borrower_        Borrower whose loan is being placed
     *  @param  thresholdPrice_  debt / collateralDeposited
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     *  @param  radius_          Distance checked to find lower thresholdPrice
     */
    function _updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_, uint256 radius_) internal {
        require(oldPrev_ != borrower_ && newPrev_ != borrower_, "B:U:PNT_SELF_REF");

        LoanInfo memory oldPrevLoan = loans[oldPrev_];
        LoanInfo memory newPrevLoan = loans[newPrev_];
        LoanInfo memory loan = loans[borrower_];

        if (oldPrev_ == address(0)) {
            require(loan.thresholdPrice == 0 || loanQueueHead == borrower_, "B:U:OLDPREV_WRNG");
        } else {
            require(oldPrevLoan.next == borrower_, "B:U:OLDPREV_NOT_CUR_BRW");
        }

        // search for the correct previous borrower given the incoming threshold price
        (newPrev_, newPrevLoan) = _searchRadius(radius_, thresholdPrice_, newPrev_, borrower_);

        if (loan.thresholdPrice > 0) {
            // loan already exists and needs to be moved within the queue
            if (oldPrev_ != newPrev_) {
                (loan, oldPrevLoan, newPrevLoan) = _move(oldPrev_, oldPrevLoan, newPrev_, newPrevLoan);
            }
            loan.thresholdPrice = thresholdPrice_;

        } else if (loanQueueHead != address(0)) {
            // loan doesn't exist yet, other loans in queue
            require(oldPrev_ == address(0), "B:U:ALRDY_IN_QUE");

            loan.thresholdPrice = thresholdPrice_;

            if (newPrev_ != address(0)) {
                loan.next = newPrevLoan.next;
                newPrevLoan.next = borrower_;

            } else {
                loan.next = loanQueueHead;
                loanQueueHead = borrower_;
            }
        } else {
            // first loan in queue
            require(oldPrev_ == address(0) || newPrev_ == address(0), "B:U:PREV_SHD_B_ZRO");
            loanQueueHead = borrower_;
            loan.thresholdPrice = thresholdPrice_;
        }

        // check that queue has been ordered properly
        if (newPrev_ != address(0)) {
            require(newPrevLoan.thresholdPrice >= thresholdPrice_, "B:U:QUE_WRNG_ORD_P");
        }
        if (loan.next != address(0)) {
            require(loans[loan.next].thresholdPrice <= thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }

        // update structs with the new ordering
        loans[oldPrev_] = oldPrevLoan;
        loans[newPrev_] = newPrevLoan;
        loans[borrower_] = loan;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_        Borrower whose loan is being placed in queue.
     *  @param  oldPrev_         Previous borrower that came before placed loan (old).
     */
    function _removeLoanQueue(address borrower_, address oldPrev_) internal {
        require(oldPrev_ == address(0) || loans[oldPrev_].next == borrower_);
        if (loanQueueHead == borrower_) {
            loanQueueHead = loans[borrower_].next;
        }

        loans[oldPrev_].next = loans[borrower_].next;
        loans[borrower_].next = address(0);
        loans[borrower_].thresholdPrice = 0;
    }

    /**
     *  @notice Move a given loan within the queue.
     *  @dev    Called by _updateLoanQueue if loan exists in the queue and needs to be moved.
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  oldPrevLoan_     Previous loan that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     *  @param  newPrevLoan_     Previous loan that now comes before placed loan (new)
     *  @return loan             Updated loan that is being placed in queue
     *  @return oldPrevLoan_     Previous loan that came before placed loan (old)
     *  @return newPrevLoan_     Previous loan that now comes before placed loan (new)
     */
    function _move(address oldPrev_, LoanInfo memory oldPrevLoan_, address newPrev_, LoanInfo memory newPrevLoan_) internal returns (LoanInfo memory loan, LoanInfo memory, LoanInfo memory) {
        require(oldPrev_ != newPrev_, "B:U:QUE_INV_MOVE");
        address borrower;

        if (oldPrev_ == address(0)) {
            loan = loans[loanQueueHead];
            borrower = loanQueueHead;
            loanQueueHead = loan.next;
        } else {
            loan = loans[oldPrevLoan_.next];
            borrower = oldPrevLoan_.next;
            oldPrevLoan_.next = loan.next;
        }

        if (newPrev_ == address(0)) {
            loan.next = loanQueueHead;
            loanQueueHead = borrower;
        } else {
            loan.next = newPrevLoan_.next;
            newPrevLoan_.next = borrower;
        }
        return (loan, oldPrevLoan_, newPrevLoan_);
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function getHighestThresholdPrice() external view override returns (uint256 thresholdPrice){
        if (loanQueueHead != address(0)) {
            return loans[loanQueueHead].thresholdPrice;
        }
        return 0;
    }

    function loanInfo(address borrower_) external view returns (uint256, address) {
        return (loans[borrower_].thresholdPrice, loans[borrower_].next);
    }
}
