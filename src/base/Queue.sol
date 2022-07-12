// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IQueue } from "./interfaces/IQueue.sol";

abstract contract Queue is IQueue {

    address public override loanQueueHead;

    mapping(address => LoanInfo) public override loans;

    /************************/
    /***  Queue functions ***/
    /************************/

    function getHighestThresholdPrice() external override view returns (uint256 thresholdPrice){
        if (loanQueueHead != address(0)) {
            return loans[loanQueueHead].thresholdPrice;
        }
        return 0;
    }

    /**
     *  @notice Called _updateLoanQueue if the newPrev_ position is incorrect
     *  @param  radius_         Distance that should be checked to find lower thresholdPrice
     *  @param  thresholdPrice_ Debt / collateralDeposited
     *  @param  newPrev__       Previous borrower that now comes before placed loan (new)
     *  @return prev_           Previous borrower that now comes before placed loan (new)
     *  @return prevLoan        Previous loan that now comes before placed loan (new)
     */
    function _searchRadius(uint256 radius_, uint256 thresholdPrice_, address newPrev_) internal view returns (address prev_, LoanInfo memory prevLoan) {

        address current = newPrev_;
        LoanInfo memory currentLoan;

        for (uint256 i = 0; i <= radius_;) {
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

    /**
     *  @notice Called by borrower methods to update loan position
     *  @param  borrower_        Borrower whose loan is being placed
     *  @param  thresholdPrice_  debt / collateralDeposited
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     *  @param  radius_          Distance that should be checked to find lower thresholdPrice
     */
    function _updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_, uint256 radius_) internal {
        require(oldPrev_ != borrower_ && newPrev_ != borrower_, "B:U:PNT_SELF_REF");
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

        } else if (loanQueueHead != address(0)) {
            // loan doesn't exist, other loans in queue
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

        // protections
        if (loan.next != address(0)) {
            require(loans[loan.next].thresholdPrice <= thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }

        loans[oldPrev_] = oldPrevLoan;
        loans[newPrev_] = newPrevLoan;
        loans[borrower_] = loan;
    }


    /**
     *  @notice Called _updateLoanQueue if the newPrev_ position is incorrect
     *  @param  borrower_        Borrower whose loan is being placed in queue
     *  @param  thresholdPrice_  debt / collateralDeposited
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     *  @param  radius_          Distance that should be checked to find lower thresholdPrice
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
     *  @notice Called by _updateLoanQueue if loan exists in the queue
     *  @param  oldPrev_         Previous borrower that came before placed loan (old)
     *  @param  oldPrevLoan_     Previous loan that came before placed loan (old)
     *  @param  newPrev_         Previous borrower that now comes before placed loan (new)
     *  @param  newPrevLoan_     Previous loan that now comes before placed loan (new)
     *  @return loan             Updated loan that is being placed in queue
     *  @return oldPrevLoan_     Previous loan that came before placed loan (old)
     *  @return newPrevLoan_     Previous loan that now comes before placed loan (new)
     */
    function _move(address oldPrev_, LoanInfo memory oldPrevLoan_, address newPrev_, LoanInfo memory newPrevLoan_) internal returns (LoanInfo memory loan, LoanInfo memory, LoanInfo memory) {

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
}