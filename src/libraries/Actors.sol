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
     *  @param  debt             Borrower debt, WAD units.
     *  @param  collateral       Collateral deposited by borrower, WAD units.
     *  @return mompFactor       Most Optimistic Matching Price (MOMP) / inflator, used in neutralPrice calc, WAD units.
     *  @param  inflatorSnapshot Current borrower inflator snapshot, WAD units.
     */
    struct Borrower {
        uint256 debt;             // [WAD]
        uint256 collateral;       // [WAD]
        uint256 mompFactor;       // [WAD]
        uint256 inflatorSnapshot; // [WAD]
    }

    function getBorrowerInfo(
        mapping(address => Borrower) storage self,
        address borrower_,
        uint256 poolInflator_
    ) internal view returns (uint256 debt_, uint256 collateral_) {
        debt_       = self[borrower_].debt;
        collateral_ = self[borrower_].collateral;
        if (debt_ != 0) {
            debt_ = Maths.wmul(debt_, Maths.wdiv(poolInflator_, self[borrower_].inflatorSnapshot));
        }
    }

    function update(
        mapping(address => Borrower) storage self,
        address borrower_,
        uint256 debt_,
        uint256 collateral_,
        uint256 mompFactor_,
        uint256 inflator_
    ) internal {
        Borrower storage borrower = self[borrower_];
        borrower.debt             = debt_;
        borrower.collateral       = collateral_;
        borrower.mompFactor       = mompFactor_;
        borrower.inflatorSnapshot = inflator_;
    }

    function updateDebt(
        mapping(address => Borrower) storage self,
        address borrower_,
        uint256 debt_,
        uint256 inflator_
    ) internal {
        Borrower storage borrower = self[borrower_];
        borrower.debt             = debt_;
        borrower.inflatorSnapshot = inflator_;
    }

    function getBorrower(
        mapping(address => Borrower) storage self,
        address borrower_
    ) internal view returns (uint256, uint256, uint256, uint256) {
        return (
            self[borrower_].debt,
            self[borrower_].collateral,
            self[borrower_].mompFactor,
            self[borrower_].inflatorSnapshot
        );
    }
}