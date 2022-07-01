// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { BorrowerManager } from "../base/BorrowerManager.sol";

import { ERC20InterestManager }  from "./ERC20InterestManager.sol";
import { IERC20BorrowerManager } from "./interfaces/IERC20BorrowerManager.sol";

import { Maths } from "../libraries/Maths.sol";

/**
 *  @notice Lender Management related functionality
 */
abstract contract ERC20BorrowerManager is IERC20BorrowerManager, ERC20InterestManager, BorrowerManager {

    using EnumerableSet for EnumerableSet.UintSet;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public override borrowers;
    mapping(address => LoanInfo) public override loans;

    uint256 public override size;
    address public override head;

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getBorrowerInfo(address borrower_)
        public view override returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256 collateralDeposited_,
            uint256 collateralEncumbered_,
            uint256 collateralization_,
            uint256 borrowerInflatorSnapshot_,
            uint256 inflatorSnapshot_
        )
    {
        BorrowerInfo memory borrower = borrowers[borrower_];

        debt_                     = borrower.debt;
        pendingDebt_              = borrower.debt;
        collateralDeposited_      = borrower.collateralDeposited;
        collateralization_        = Maths.WAD;
        borrowerInflatorSnapshot_ = borrower.inflatorSnapshot;
        inflatorSnapshot_         = inflatorSnapshot;

        if (debt_ != 0 && borrowerInflatorSnapshot_ != 0) {
            pendingDebt_          += _pendingInterest(debt_, getPendingInflator(), borrowerInflatorSnapshot_);
            collateralEncumbered_ = getEncumberedCollateral(pendingDebt_);
            collateralization_    = Maths.wrdivw(collateralDeposited_, collateralEncumbered_);
        }

    }

    function getHighestThresholdPrice() public view returns ( BorrowerInfo memory borrower_) {
        if (head != address(0)) {
            borrower_ = borrowers[head];
        }
    }

    function updateLoanQueue(address borrower_, uint256 thresholdPrice_, address oldPrev_, address newPrev_) public override {
        require(oldPrev_ != borrower_ || newPrev_ != borrower_, "B:U:PNT_SELF_REF");

        if (loans[oldPrev_].next != address(0)) {
            require(loans[oldPrev_].next == borrower_, "B:U:OLDPREV_NOT_CUR_BRW");
        }

        LoanInfo memory loan = loans[borrower_];
        
        if (loan.thresholdPrice > 0) {
            // loan exists
            loan = _move(oldPrev_, newPrev_);
            loan.thresholdPrice = thresholdPrice_;
            loans[borrower_] = loan;

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
            loans[borrower_] = loan;
        } else {
            // first loan in queue
            require(oldPrev_ == address(0) || newPrev_ == address(0), "B:U:PREV_SHD_B_ZRO");
            head = borrower_;
            loan.thresholdPrice = thresholdPrice_;
            loans[borrower_] = loan;
        }

        // protections
        if (newPrev_ != address(0)) {
            require(loans[newPrev_].thresholdPrice > thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }
        if (loan.next != address(0)) {
            require(loans[loan.next].thresholdPrice < thresholdPrice_, "B:U:QUE_WRNG_ORD");
        }
    }

    function _move(address oldPrev_, address newPrev_) private returns (LoanInfo memory loan) {
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
        }
        if (newPrev_ == address(0)) {
            loan.next = head;
            head = borrower;

        } else {
            LoanInfo memory newPrevLoan = loans[newPrev_];
            loan.next = newPrevLoan.next;
            newPrevLoan.next = borrower;
        }
    }

}
