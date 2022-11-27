// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Deposits.sol';
import './PoolUtils.sol';
import './Maths.sol';

library Loans {

    uint256 constant ROOT_INDEX = 1;

    struct Data {
        Loan[] loans;
        mapping (address => uint)     indices;   // borrower address => loan index mapping
        mapping (address => Borrower) borrowers; // borrower address => Borrower struct mapping
    }

    struct Loan {
        address borrower;       // borrower address
        uint96  thresholdPrice; // [WAD] Loan's threshold price.
    }

    struct Borrower {
        uint256 t0debt;           // [WAD] Borrower debt time-adjusted as if it was incurred upon first loan of pool.
        uint256 collateral;       // [WAD] Collateral deposited by borrower.
        uint256 t0Np;             // [WAD] Neutral Price time-adjusted as if it was incurred upon first loan of pool.
    }

    /**
     *  @notice The loan to be removed does not exist in loans heap.
     */
    error NoLoan();
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
     *  @param self Holds tree loan data.
     */
    function init(Data storage self) internal {
        self.loans.push(Loan(address(0), 0));
    }

    /***********************************/
    /***  Loans Management Functions ***/
    /***********************************/

    /**
     *  @notice Updates a loan: updates heap (upsert if TP not 0, remove otherwise) and borrower balance.
     *  @param self Holds tree loan data.
     *  @param deposits_            Pool deposits, used to calculate borrower MOMP factor.
     *  @param borrowerAddress_     Borrower's address to update.
     *  @param t0NpUpdate           t0Np should be stamped only in borrow, pull collateral
     *  @param borrower_            Borrower struct with borrower details.
     *  @param poolDebt_            Pool debt, used for calculating borrower MOMP factor.
     *  @param poolInflator_        The current pool inflator used to calculate borrower MOMP factor.
     *  @param poolInterestRate_    Current Pool interest Rate.
     *  @param lup_                 Current Lup.
     */
    function update(
        Data storage self,
        Deposits.Data storage deposits_,
        address borrowerAddress_,
        bool t0NpUpdate,
        Borrower memory borrower_,
        uint256 poolDebt_,
        uint256 poolInflator_,
        uint256 poolInterestRate_,
        uint256 lup_
    ) internal {

        // update loan heap
        if (borrower_.t0debt != 0 && borrower_.collateral != 0) {
            _upsert(
                self,
                borrowerAddress_,
                uint96(Maths.wdiv(borrower_.t0debt, borrower_.collateral))
            );
        } else if (self.indices[borrowerAddress_] != 0) {
            remove(self, borrowerAddress_);
        }

        // update borrower
        if (t0NpUpdate) {
            if (borrower_.t0debt != 0 && borrower_.collateral != 0) borrower_.t0Np = Deposits.t0Np(
                deposits_,
                poolInflator_,
                poolDebt_,
                self.loans.length - 1,
                poolInterestRate_,
                lup_,
                borrower_.t0debt,
                borrower_.collateral
            );
            else borrower_.t0Np = 0;
        }
        self.borrowers[borrowerAddress_] = borrower_;
    }

    /**************************************/
    /***  Loans Heap Internal Functions ***/
    /**************************************/

    /**
     *  @notice Moves a Loan up the tree.
     *  @param self Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleUp(Data storage self, Loan memory loan_, uint i_) private {
        uint256 count = self.loans.length;
        if (i_ == ROOT_INDEX || loan_.thresholdPrice <= self.loans[i_ / 2].thresholdPrice){
          _insert(self, loan_, i_, count);
        } else {
          _insert(self, self.loans[i_ / 2], i_, count);
          _bubbleUp(self, loan_, i_ / 2);
        }
    }

    /**
     *  @notice Moves a Loan down the tree.
     *  @param self Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleDown(Data storage self, Loan memory loan_, uint i_) private {
        // Left child index.
        uint cIndex = i_ * 2;

        uint256 count = self.loans.length;
        if (count <= cIndex) {
            _insert(self, loan_, i_, count);
        } else {
            Loan memory largestChild = self.loans[cIndex];

            if (count > cIndex + 1 && self.loans[cIndex + 1].thresholdPrice > largestChild.thresholdPrice) {
                largestChild = self.loans[++cIndex];
            }

            if (largestChild.thresholdPrice <= loan_.thresholdPrice) {
              _insert(self, loan_, i_, count);
            } else {
              _insert(self, largestChild, i_, count);
              _bubbleDown(self, loan_, cIndex);
            }
        }
    }

    /**
     *  @notice Inserts a Loan in the tree.
     *  @param self Holds tree loan data.
     *  @param loan_ Loan to be inserted.
     *  @param i_    index for Loan to be inserted at.
     */
    function _insert(Data storage self, Loan memory loan_, uint i_, uint256 count_) private {
        if (i_ == count_) self.loans.push(loan_);
        else self.loans[i_] = loan_;

        self.indices[loan_.borrower] = i_;
    }

    /**
     *  @notice Removes loan for given borrower address.
     *  @param self      Holds tree loan data.
     *  @param borrower_ Borrower address whose loan is being updated or inserted.
     */
    function remove(Data storage self, address borrower_) internal {
        uint256 i_ = self.indices[borrower_];
        if (i_ == 0) revert NoLoan();

        delete self.indices[borrower_];
        uint256 tailIndex = self.loans.length - 1;
        if (i_ == tailIndex) self.loans.pop(); // we're removing the tail, pop without sorting
        else {
            Loan memory tail = self.loans[tailIndex];
            self.loans.pop();            // remove tail loan
            _bubbleUp(self, tail, i_);
            _bubbleDown(self, self.loans[i_], i_);
        }
    }

    /**
     *  @notice Performs an insert or an update dependent on borrowers existance.
     *  @param self Holds tree loan data.
     *  @param borrower_       Borrower address that is being updated or inserted.
     *  @param thresholdPrice_ Threshold Price that is updated or inserted.
     */
    function _upsert(
        Data storage self,
        address borrower_,
        uint96 thresholdPrice_
    ) internal {
        if (thresholdPrice_ == 0) revert ZeroThresholdPrice();
        uint256 i = self.indices[borrower_];

        // Loan exists, update in place.
        if (i != 0) {
            Loan memory currentLoan = self.loans[i];
            if (currentLoan.thresholdPrice > thresholdPrice_) {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleDown(self, currentLoan, i);
            } else {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleUp(self, currentLoan, i);
            }

        // New loan, insert it
        } else {
            _bubbleUp(self, Loan(borrower_, thresholdPrice_), self.loans.length);
        }
    }


    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Returns borrower struct.
     *  @param self Holds tree loan data.
     *  @param borrowerAddress_ Borrower's address.
     *  @return Borrower struct containing borrower info.
     */
    function getBorrowerInfo(
        Data storage self,
        address borrowerAddress_
    ) internal view returns (Borrower memory) {
        return self.borrowers[borrowerAddress_];
    }

    /**
     *  @notice Retreives Loan by borrower address.
     *  @param self     Holds tree loans data.
     *  @param borrower_ Borrower address that is being updated or inserted.
     *  @return Loan     Loan struct containing loans info.
     */
    function getById(Data storage self, address borrower_) internal view returns(Loan memory) {
        return getByIndex(self, self.indices[borrower_]);
    }

    /**
     *  @notice Retreives Loan by index, i_.
     *  @param self Holds tree loan data.
     *  @param i_    Index to retreive Loan.
     *  @return Loan Loan retrieved by index.
     */
    function getByIndex(Data storage self, uint256 i_) internal view returns(Loan memory) {
        return self.loans.length > i_ ? self.loans[i_] : Loan(address(0), 0);
    }

    /**
     *  @notice Retreives Loan with the highest threshold price value.
     *  @param self Holds tree loan data.
     *  @return Loan Max Loan in the Heap.
     */
    function getMax(Data storage self) internal view returns(Loan memory) {
        return getByIndex(self, ROOT_INDEX);
    }

    /**
     *  @notice Returns number of loans in pool.
     *  @param self Holds tree loan data.
     *  @return number of loans in pool.
     */
    function noOfLoans(Data storage self) internal view returns (uint256) {
        return self.loans.length - 1;
    }
}