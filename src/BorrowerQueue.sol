// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

abstract contract BorrowerQueue {

    /***************/
    /*** Structs ***/
    /***************/

    struct LoanInfo {
        uint256 thresholdPrice;
        address next;
    }

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(address => LoanInfo) public loans;
    uint256 public size;
    address public head;

    function _updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_) internal {
        require(oldPrev_ != borrower_ || newPrev_ != borrower_, "B:U:PNT_SELF_REF");

        if (loans[oldPrev_].next != address(0)) {
            require(loans[oldPrev_].next == borrower_, "B:U:OLDPREV_NOT_CUR_BRW");
        }

        LoanInfo memory loan = loans[borrower_];

        if (loan.thresholdPrice > 0) {
            // loan exists
            loan = _move(oldPrev_, newPrev_);
            loan.thresholdPrice = thresholdPrice_;

        } else if (head != address(0)) {
            // loan doesn't exist, other loans in queue
            require(oldPrev_ == address(0), "B:U:ALRDY_IN_QUE");

            // TODO: call updateLoanQueue when new borrower borrows
            loan.thresholdPrice = thresholdPrice_;

            if (newPrev_ != address(0)) {
                loan.next = loans[newPrev_].next;
                loans[newPrev_].next = borrower_;

            } else {
                loan.next = head;
                head = borrower_;
            }
        } else {
            // first loan in queue
            require(oldPrev_ == address(0) || newPrev_ == address(0), "B:U:PREV_SHD_B_ZRO");
            head = borrower_;
            loan.thresholdPrice = thresholdPrice_;
        }

        // protections
        if (newPrev_ != address(0)) {
            require(loans[newPrev_].thresholdPrice > thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }
        if (loan.next != address(0)) {
            require(loans[loan.next].thresholdPrice < thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }
        loans[borrower_] = loan;
    }

    function _move(address oldPrev_, address newPrev_) internal returns (LoanInfo memory loan) {
        address borrower;

        if (oldPrev_ == address(0)) {
            loan = loans[head];
            borrower = head;
            head = loan.next;
        } else {
            LoanInfo memory oldPrevLoan = loans[oldPrev_];
            loan = loans[oldPrevLoan.next];
            borrower = oldPrevLoan.next;
            oldPrevLoan.next = loan.next;
            loans[oldPrev_] = oldPrevLoan;
        }

        if (newPrev_ == address(0)) {
            loan.next = head;
            head = borrower;
        } else {
            LoanInfo memory newPrevLoan = loans[newPrev_];
            loan.next = newPrevLoan.next;
            newPrevLoan.next = borrower;
            loans[newPrev_] = newPrevLoan;
        }
    }
}