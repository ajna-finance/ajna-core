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
        
        // loan doesn't exist
        require(oldPrev_ =t a= address(0), "B:U:PREV_SHD_B_ZRO");

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

    }

}
