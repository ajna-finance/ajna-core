// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./interfaces/IQueue.sol";

abstract contract Queue is IQueue {

    address public override loanQueueHead;

    mapping(address => LoanInfo) public override loans;

    /************************/
    /***  Queue functions ***/
    /************************/

    /**
     *  @notice Called by borrower methods to update loan position.
     *  @param  borrower_        Borrower whose loan is being placed
     *  @param  thresholdPrice_  debt / collateralDeposited
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     */
    function _updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_) internal {
        require(oldPrev_ != borrower_ && newPrev_ != borrower_, "B:U:PNT_SELF_REF");
        require(thresholdPrice_ != 0, "B:U:TP_EQ_0");

        address curLoanQueueHead = loanQueueHead;

        LoanInfo storage oldPrevLoan = loans[oldPrev_];
        LoanInfo memory loan = loans[borrower_];

        if (oldPrev_ == address(0)) require(loan.thresholdPrice == 0 || curLoanQueueHead == borrower_, "B:U:OLDPREV_WRNG");
        else require(oldPrevLoan.next == borrower_, "B:U:OLDPREV_NOT_CUR_BRW");

        LoanInfo storage newPrevLoan = loans[newPrev_];

        if (loan.thresholdPrice != 0) {
            // loan already exists and needs to be moved within the queue
            if (oldPrev_ != newPrev_) {
                address borrower;
                if (oldPrev_ == address(0)) {
                    loan          = loans[curLoanQueueHead];
                    borrower      = curLoanQueueHead;
                    loanQueueHead = loan.next;
                } else {
                    loan             = loans[oldPrevLoan.next];
                    borrower         = oldPrevLoan.next;
                    oldPrevLoan.next = loan.next;
                }

                if (newPrev_ == address(0)) {
                    loan.next     = curLoanQueueHead;
                    loanQueueHead = borrower;
                } else {
                    loan.next        = newPrevLoan.next;
                    newPrevLoan.next = borrower;
                }
            }
            loan.thresholdPrice = thresholdPrice_;

        } else if (curLoanQueueHead != address(0)) {
            // loan doesn't exist yet, other loans in queue

            require(oldPrev_ == address(0), "B:U:ALRDY_IN_QUE");

            loan.thresholdPrice = thresholdPrice_;

            if (newPrev_ != address(0)) {
                // loan gets appended to newPrev_
                loan.next        = newPrevLoan.next;
                newPrevLoan.next = borrower_;

            } else {
                // loan becomes new queue head
                loan.next     = curLoanQueueHead;
                loanQueueHead = borrower_;
            }
        } else {
            // first loan in queue
            require(oldPrev_ == address(0) || newPrev_ == address(0), "B:U:PREV_SHD_B_ZRO");
            loanQueueHead       = borrower_;
            loan.thresholdPrice = thresholdPrice_;
        }

        // check that queue has been ordered properly
        if (newPrev_ != address(0))  require(newPrevLoan.thresholdPrice >= thresholdPrice_,      "B:U:QUE_WRNG_ORD_P");
        if (loan.next != address(0)) require(loans[loan.next].thresholdPrice <= thresholdPrice_, "B:U:QUE_WRNG_ORD_N");

        // update loan with the new ordering
        loans[borrower_] = loan;
    }

    /**
     *  @notice Removes a borrower from the loan queue and repairs the queue order.
     *  @dev    Called by _updateLoanQueue if borrower.debt == 0.
     *  @param  borrower_        Borrower whose loan is being placed in queue.
     *  @param  oldPrev_         Previous borrower that came before placed loan (old).
     */
    function _removeLoanQueue(address borrower_, address oldPrev_) internal {
        require(oldPrev_ == address(0) || loans[oldPrev_].next == borrower_, "B:R:OLDPREV_WRNG");
        if (loanQueueHead == borrower_) loanQueueHead = loans[borrower_].next;

        loans[oldPrev_].next = loans[borrower_].next;
        delete loans[borrower_];
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function loanInfo(address borrower_) external view returns (uint256, address) {
        return (loans[borrower_].thresholdPrice, loans[borrower_].next);
    }
}
