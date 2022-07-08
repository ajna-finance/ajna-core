// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./interfaces/IQueue.sol";

abstract contract Queue is IQueue {

    address public override head;

    mapping(address => LoanInfo) public override loans;

    /************************/
    /***  Queue functions ***/
    /************************/

    function getHighestThresholdPrice() external override view returns (uint256 thresholdPrice){
        if (head != address(0)) {
            return loans[head].thresholdPrice;
        }
        return 0;
    }

    function _searchRadius(uint256 radius_, uint256 thresholdPrice_, address newPrev_) internal view returns (address prev_, LoanInfo memory prevLoan) {

        address current = newPrev_;
        LoanInfo memory currentLoan;

        for (uint256 i = 0; i <= radius_; ) {
            prev_ = current;
            current = loans[prev_].next;
            currentLoan = loans[current];

            if (currentLoan.thresholdPrice <= thresholdPrice_ || currentLoan.thresholdPrice == 0) {
                return (prev_, loans[prev_]);
            }

            unchecked {
                ++i;
            }
        }
        require(currentLoan.thresholdPrice <= thresholdPrice_, "B:S:SRCH_RDS_FAIL");
    }

    function updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_, uint256 radius_) external override {

        require(oldPrev_ != borrower_ || newPrev_ != borrower_, "B:U:PNT_SELF_REF");
        LoanInfo memory oldPrevLoan = loans[oldPrev_];
        LoanInfo memory newPrevLoan = loans[newPrev_];

        if (oldPrevLoan.next != address(0)) {
            require(oldPrevLoan.next == borrower_, "B:U:OLDPREV_NOT_CUR_BRW");
        }

        // protections
        if (newPrev_ != address(0) && loans[newPrevLoan.next].thresholdPrice > thresholdPrice_ ) {
            // newPrev is not accurate, search radius
            (newPrev_, newPrevLoan) = _searchRadius(radius_, thresholdPrice_, newPrevLoan.next);
        }

        LoanInfo memory loan = loans[borrower_];
        
        if (loan.thresholdPrice > 0) {
            // loan exists
            (loan, oldPrevLoan, newPrevLoan)= _move(oldPrev_, oldPrevLoan, newPrev_, newPrevLoan);
            loan.thresholdPrice = thresholdPrice_;

        } else if (head != address(0)) {
            // loan doesn't exist, other loans in queue
            require(oldPrev_ == address(0), "B:U:ALRDY_IN_QUE");

            // TODO: call updateLoanQueue when new borrower borrows
            loan.thresholdPrice = thresholdPrice_;

            if (newPrev_ != address(0)) {
                loan.next = newPrevLoan.next;
                newPrevLoan.next = borrower_;

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
        if (loan.next != address(0)) {
            require(loans[loan.next].thresholdPrice < thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }

        loans[oldPrev_] = oldPrevLoan;
        loans[newPrev_] = newPrevLoan;
        loans[borrower_] = loan;
    }

    function removeLoanQueue(address borrower_, address oldPrev_) external override {
        require(loans[oldPrev_].next == borrower_);
        if (head == borrower_) {
            head = loans[borrower_].next;
        }

        loans[oldPrev_].next = loans[borrower_].next;
        loans[borrower_].next = address(0);
        loans[borrower_].thresholdPrice = 0;
    }

    function _move(address oldPrev_, LoanInfo memory oldPrevLoan_, address newPrev_, LoanInfo memory newPrevLoan_) internal returns (LoanInfo memory loan, LoanInfo memory, LoanInfo memory) {

        address borrower;

        if (oldPrev_ == address(0)) {
            loan = loans[head];
            borrower = head;
            head = loan.next;
        } else {
            loan = loans[oldPrevLoan_.next];
            borrower = oldPrevLoan_.next;
            oldPrevLoan_.next = loan.next;
        }

        if (newPrev_ == address(0)) {
            loan.next = head;
            head = borrower;
        } else {
            loan.next = newPrevLoan_.next;
            newPrevLoan_.next = borrower;
        }
        return (loan, oldPrevLoan_, newPrevLoan_);
    }
}