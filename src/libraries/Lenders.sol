// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './Book.sol';

library Lenders {

    /***************/
    /*** Lenders ***/
    /***************/

    struct Lender {
        uint256 lps; // [RAY]
        uint256 ts;  // timestamp
    }

    function deposit(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address lender_,
        uint256 amount_
    ) internal {
        self[index_][lender_].lps += amount_;
        self[index_][lender_].ts  = block.timestamp;
    }

    function addLPs(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address lender_,
        uint256 amount_
    ) internal {
        self[index_][lender_].lps += amount_;
    }

    function removeLPs(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address lender_,
        uint256 amount_
    ) internal {
        self[index_][lender_].lps -= amount_;
    }

    function transferLPs(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address owner_,
        address newOwner_,
        uint256 amount_,
        uint256 depositTime
    ) internal {
        // move lp tokens to the new owner address
        Lender storage newOwner = self[index_][newOwner_];
        newOwner.lps += amount_;
        newOwner.ts  = Maths.max(depositTime, newOwner.ts);

        // delete owner lp balance for this index
        delete self[index_][owner_];
    }

    function applyEarlyWithdrawalPenalty(
        uint256 feeRate_,
        uint256 depositTime_,
        uint256 curDebt_,
        uint256 col_,
        uint256 fromIndex_,
        uint256 toIndex_,
        uint256 amount_
    ) internal view returns (uint256 amountWithPenalty_){
        amountWithPenalty_ = amount_;
        if (col_ != 0 && depositTime_ != 0 && block.timestamp - depositTime_ < 1 days) {
            uint256 ptp = Maths.wdiv(curDebt_, col_);
            bool applyPenalty = Book.indexToPrice(fromIndex_) > ptp;
            if (toIndex_ != 0) applyPenalty = applyPenalty && Book.indexToPrice(toIndex_) < ptp;
            if (applyPenalty) amountWithPenalty_ =  Maths.wmul(amountWithPenalty_, Maths.WAD - feeRate_);
        }
    }

    function getLenderInfo(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address lender_
    ) internal view returns (uint256, uint256) {
        return (self[index_][lender_].lps, self[index_][lender_].ts);
    }
}