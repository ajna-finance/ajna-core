// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './Maths.sol';
import './PoolUtils.sol';

library Actors {

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

    function getLenderInfo(
        mapping(uint256 => mapping(address => Lender)) storage self,
        uint256 index_,
        address lender_
    ) internal view returns (uint256, uint256) {
        return (self[index_][lender_].lps, self[index_][lender_].ts);
    }

    /*****************/
    /*** Borrowers ***/
    /*****************/

    /**
     *  @notice Struct holding borrower related info.
     *  @param  t0debt           Borrower debt time-adjusted as if it was incurred upon first loan of pool, WAD units.
     *  @param  collateral       Collateral deposited by borrower, WAD units.
     *  @return mompFactor       Most Optimistic Matching Price (MOMP) / inflator, used in neutralPrice calc, WAD units.
     */
    struct Borrower {
        uint256 t0debt;           // [WAD]
        uint256 collateral;       // [WAD]
        uint256 mompFactor;       // [WAD]
    }

    function getBorrowerInfo(
        mapping(address => Borrower) storage self,
        address borrower_,
        uint256 poolInflator_
    ) internal view returns (uint256 debt_, uint256 collateral_) {
        debt_       = self[borrower_].t0debt;
        collateral_ = self[borrower_].collateral;
        if (debt_ != 0) {
            debt_ = Maths.wmul(debt_, poolInflator_);
        }
    }

    function update(
        mapping(address => Borrower) storage self,
        address borrower_,
        uint256 collateral_,
        int256  t0debtChange_,
        uint256 mompFactor_
    ) internal {
        Borrower storage borrower = self[borrower_];
        borrower.collateral       = collateral_;
        borrower.mompFactor       = mompFactor_;
        // TODO: inefficient; would like to mutate this with a += in borrow, -= in repay
        borrower.t0debt = Maths.uadd(borrower.t0debt, t0debtChange_);
    }
}