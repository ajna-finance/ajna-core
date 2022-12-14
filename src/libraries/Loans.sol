// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Borrower, LoansState, Loan } from '../base/interfaces/IPool.sol';

import './Maths.sol';

library Loans {

    uint256 constant ROOT_INDEX = 1;

    /**
     *  @notice The threshold price of the loan to be inserted in loans heap is zero.
     */
    error ZeroThresholdPrice();

    /***********************/
    /***  Initialization ***/
    /***********************/

    /**
     *  @notice Initializes Loans Max Heap.
     *  @dev    Organizes loans so Highest Threshold Price can be retreived easily.
     *  @param loans_ Holds tree loan data.
     */
    function init(LoansState storage loans_) internal {
        loans_.loans.push(Loan(address(0), 0));
    }

    /***********************************/
    /***  Loans Management Functions ***/
    /***********************************/

    /**
     *  @notice Updates a loan: updates heap (upsert if TP not 0, remove otherwise) and borrower balance.
     *  @param loans_ Holds tree loan data.
     *  @param borrowerAddress_ Borrower's address to update.
     *  @param borrower_        Borrower struct with borrower details.
     *  @param loanIndex_       Current index of the loan (can be 0 if new loan to be inserted in heap)
     */
    function update(
        LoansState storage loans_,
        address borrowerAddress_,
        Borrower memory borrower_,
        uint256 loanIndex_
    ) internal {
        // update loan heap
        if (borrower_.t0debt != 0 && borrower_.collateral != 0) {
            _upsert(
                loans_,
                borrowerAddress_,
                loanIndex_,
                uint96(Maths.wdiv(borrower_.t0debt, borrower_.collateral))
            );

        } else if (loanIndex_ != 0) {
            remove(loans_, borrowerAddress_, loanIndex_);
        }

        loans_.borrowers[borrowerAddress_] = borrower_;
    }

    /**************************************/
    /***  Loans Heap Internal Functions ***/
    /**************************************/

    /**
     *  @notice Moves a Loan up the tree.
     *  @param loans_ Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleUp(LoansState storage loans_, Loan memory loan_, uint i_) private {
        uint256 count = loans_.loans.length;
        if (i_ == ROOT_INDEX || loan_.thresholdPrice <= loans_.loans[i_ / 2].thresholdPrice){
          _insert(loans_, loan_, i_, count);
        } else {
          _insert(loans_, loans_.loans[i_ / 2], i_, count);
          _bubbleUp(loans_, loan_, i_ / 2);
        }
    }

    /**
     *  @notice Moves a Loan down the tree.
     *  @param loans_ Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleDown(LoansState storage loans_, Loan memory loan_, uint i_) private {
        // Left child index.
        uint cIndex = i_ * 2;

        uint256 count = loans_.loans.length;
        if (count <= cIndex) {
            _insert(loans_, loan_, i_, count);
        } else {
            Loan memory largestChild = loans_.loans[cIndex];

            if (count > cIndex + 1 && loans_.loans[cIndex + 1].thresholdPrice > largestChild.thresholdPrice) {
                largestChild = loans_.loans[++cIndex];
            }

            if (largestChild.thresholdPrice <= loan_.thresholdPrice) {
              _insert(loans_, loan_, i_, count);
            } else {
              _insert(loans_, largestChild, i_, count);
              _bubbleDown(loans_, loan_, cIndex);
            }
        }
    }

    /**
     *  @notice Inserts a Loan in the tree.
     *  @param loans_ Holds tree loan data.
     *  @param loan_ Loan to be inserted.
     *  @param i_    index for Loan to be inserted at.
     */
    function _insert(LoansState storage loans_, Loan memory loan_, uint i_, uint256 count_) private {
        if (i_ == count_) loans_.loans.push(loan_);
        else loans_.loans[i_] = loan_;

        loans_.indices[loan_.borrower] = i_;
    }

    /**
     *  @notice Removes loan for given borrower address.
     *  @param loans_      Holds tree loan data.
     *  @param borrower_ Borrower address whose loan is being updated or inserted.
     *  @param id_       Loan id.
     */
    function remove(LoansState storage loans_, address borrower_, uint256 id_) internal {
        delete loans_.indices[borrower_];
        uint256 tailIndex = loans_.loans.length - 1;
        if (id_ == tailIndex) loans_.loans.pop(); // we're removing the tail, pop without sorting
        else {
            Loan memory tail = loans_.loans[tailIndex];
            loans_.loans.pop();            // remove tail loan
            _bubbleUp(loans_, tail, id_);
            _bubbleDown(loans_, loans_.loans[id_], id_);
        }
    }

    /**
     *  @notice Performs an insert or an update dependent on borrowers existance.
     *  @param loans_ Holds tree loan data.
     *  @param borrower_       Borrower address that is being updated or inserted.
     *  @param id_             Loan id.
     *  @param thresholdPrice_ Threshold Price that is updated or inserted.
     */
    function _upsert(
        LoansState storage loans_,
        address borrower_,
        uint256 id_,
        uint96 thresholdPrice_
    ) internal {
        if (thresholdPrice_ == 0) revert ZeroThresholdPrice();

        // Loan exists, update in place.
        if (id_ != 0) {
            Loan memory currentLoan = loans_.loans[id_];
            if (currentLoan.thresholdPrice > thresholdPrice_) {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleDown(loans_, currentLoan, id_);
            } else {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleUp(loans_, currentLoan, id_);
            }

        // New loan, insert it
        } else {
            _bubbleUp(loans_, Loan(borrower_, thresholdPrice_), loans_.loans.length);
        }
    }


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns borrower struct.
     *  @param loans_ Holds tree loan data.
     *  @param borrowerAddress_ Borrower's address.
     *  @return Borrower struct containing borrower info.
     */
    function getBorrowerInfo(
        LoansState storage loans_,
        address borrowerAddress_
    ) internal view returns (Borrower memory) {
        return loans_.borrowers[borrowerAddress_];
    }

    /**
     *  @notice Retreives Loan by borrower address.
     *  @param loans_     Holds tree loans data.
     *  @param borrower_ Borrower address that is being updated or inserted.
     *  @return Loan     Loan struct containing loans info.
     */
    function getById(LoansState storage loans_, address borrower_) internal view returns(Loan memory) {
        return getByIndex(loans_, loans_.indices[borrower_]);
    }

    /**
     *  @notice Retreives Loan by index, i_.
     *  @param loans_ Holds tree loan data.
     *  @param i_    Index to retreive Loan.
     *  @return Loan Loan retrieved by index.
     */
    function getByIndex(LoansState storage loans_, uint256 i_) internal view returns(Loan memory) {
        return loans_.loans.length > i_ ? loans_.loans[i_] : Loan(address(0), 0);
    }

    /**
     *  @notice Retreives Loan with the highest threshold price value.
     *  @param loans_ Holds tree loan data.
     *  @return Loan Max Loan in the Heap.
     */
    function getMax(LoansState storage loans_) internal view returns(Loan memory) {
        return getByIndex(loans_, ROOT_INDEX);
    }

    /**
     *  @notice Returns number of loans in pool.
     *  @param loans_ Holds tree loan data.
     *  @return number of loans in pool.
     */
    function noOfLoans(LoansState storage loans_) internal view returns (uint256) {
        return loans_.loans.length - 1;
    }
}