// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

library LoansHeap {

    uint256 constant ROOT_INDEX = 1;

    struct Data {
        Loan[] loans;
        mapping (address => uint) indices; // unique id => loan index
    }

    struct Loan {
        address borrower;
        uint256 thresholdPrice;
    }

    /**
     *  @notice Initializes Max Heap.
     *  @dev    Organizes loans so Highest Threshold Price can be retreived easily.
     *  @param self_ Holds tree loan data.
     */
    function init(Data storage self_) internal {
        require(self_.loans.length == 0, "H:ALREADY_INIT");
        self_.loans.push(Loan(address(0), 0));
    }

    function noOfLoans(Data storage self_) internal view returns (uint256) {
        return self_.loans.length - 1;
    }

   function update(
        Data storage self_,
        address borrower_,
        uint256 thresholdPrice_
    ) internal {
        if (thresholdPrice_ != 0) upsert(self_, borrower_, thresholdPrice_);
        else if (self_.indices[borrower_] != 0) {
            remove(self_, borrower_);
        }
    }

    /**
     *  @notice Performs an insert or an update dependent on borrowers existance.
     *  @param self_ Holds tree loan data.
     *  @param borrower_       Borrower address that is being updated or inserted.
     *  @param thresholdPrice_ Threshold Price that is updated or inserted.
     */
    function upsert(
        Data storage self_,
        address borrower_,
        uint256 thresholdPrice_
    ) internal {
        require(thresholdPrice_ != 0, "H:I:VAL_EQ_0");
        uint256 i = self_.indices[borrower_];

        // Loan exists, update in place.
        if (i != 0) {
            Loan memory currentLoan = self_.loans[i];
            if (currentLoan.thresholdPrice > thresholdPrice_) {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleDown(self_, currentLoan, i);
            } else {
                currentLoan.thresholdPrice = thresholdPrice_;
                _bubbleUp(self_, currentLoan, i);
            }

        // New loan, insert it
        } else { 
            _bubbleUp(self_, Loan(borrower_, thresholdPrice_), self_.loans.length);
        }
    }

    /**
     *  @notice Retreives Loan by borrower address.
     *  @param self_     Holds tree loans data.
     *  @param borrower_ Borrower address that is being updated or inserted.
     *  @return Loan     Id's freshly updated or inserted Loan.
     */
    function getById(Data storage self_, address borrower_) internal view returns(Loan memory) {
        return getByIndex(self_, self_.indices[borrower_]);
    }

    /**
     *  @notice Retreives Loan by index, i_.
     *  @param self_ Holds tree loan data.
     *  @param i_    Index to retreive Loan.
     *  @return Loan Loan retrieved by index.
     */
    function getByIndex(Data storage self_, uint256 i_) internal view returns(Loan memory) {
        return self_.loans.length > i_ ? self_.loans[i_] : Loan(address(0), 0);
    }

    /**
     *  @notice Retreives Loan with the highest threshold price value.
     *  @param self_ Holds tree loan data.
     *  @return Loan Max Loan in the Heap.
     */
    function getMax(Data storage self_) internal view returns(Loan memory) {
        return getByIndex(self_, ROOT_INDEX);
    }

    /**
     *  @notice Removes loan for given borrower address.
     *  @param self_     Holds tree loan data.
     *  @param borrower_ Borrower address whose loan is being updated or inserted.
     */
    function remove(Data storage self_, address borrower_) internal {
        uint256 i_ = self_.indices[borrower_];
        require(i_ != 0, "H:R:NO_BORROWER");

        delete self_.indices[borrower_];
        uint256 tailIndex = self_.loans.length - 1;
        if (i_ == tailIndex) self_.loans.pop(); // we're removing the tail, pop without sorting
        else {
            Loan memory tail = self_.loans[tailIndex];
            self_.loans.pop();            // remove tail loan
            _bubbleUp(self_, tail, i_);
            _bubbleDown(self_, self_.loans[i_], i_);
        }
    }

    /**
     *  @notice Moves a Loan up the tree.
     *  @param self_ Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleUp(Data storage self_, Loan memory loan_, uint i_) private {
        uint256 count = self_.loans.length;
        if (i_ == ROOT_INDEX || loan_.thresholdPrice <= self_.loans[i_ / 2].thresholdPrice){
          _insert(self_, loan_, i_, count);
        } else {
          _insert(self_, self_.loans[i_ / 2], i_, count);
          _bubbleUp(self_, loan_, i_ / 2);
        }
    }

    /**
     *  @notice Moves a Loan down the tree.
     *  @param self_ Holds tree loan data.
     *  @param loan_ Loan to be moved.
     *  @param i_    Index for Loan to be moved to.
     */
    function _bubbleDown(Data storage self_, Loan memory loan_, uint i_) private {
        // Left child index.
        uint cIndex = i_ * 2; 

        uint256 count = self_.loans.length;
        if (count <= cIndex) {
            _insert(self_, loan_, i_, count);
        } else {
            Loan memory largestChild = self_.loans[cIndex];

            if (count > cIndex + 1 && self_.loans[cIndex + 1].thresholdPrice > largestChild.thresholdPrice) {
                largestChild = self_.loans[++cIndex];
            }

            if (largestChild.thresholdPrice <= loan_.thresholdPrice) {
              _insert(self_, loan_, i_, count);
            } else {
              _insert(self_, largestChild, i_, count);
              _bubbleDown(self_, loan_, cIndex);
            }
        }
    }

    /**
     *  @notice Inserts a Loan in the tree.
     *  @param self_ Holds tree loan data.
     *  @param loan_ Loan to be inserted.
     *  @param i_    index for Loan to be inserted at.
     */
    function _insert(Data storage self_, Loan memory loan_, uint i_, uint256 count_) private {
        if (i_ == count_) self_.loans.push(loan_);
        else self_.loans[i_] = loan_;

        self_.indices[loan_.borrower] = i_;
    }
}