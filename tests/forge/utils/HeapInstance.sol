// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import './DSTestPlus.sol';

import 'src/libraries/internal/Loans.sol';

contract HeapInstance is DSTestPlus {
    using Loans for LoansState;

    LoansState private _heap;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    address[] private inserts;

    constructor () {
        _heap.init();
    }

    function getCount() public view returns (uint256) {
        return _heap.loans.length;
    }

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIdByInsertIndex(uint256 i_) public view returns (address) {
        return inserts[i_];
    }

    function upsertT0DebtToCollateral(address borrower_, uint256 tp_) public {
        _heap._upsert(borrower_, _heap.indices[borrower_], uint96(tp_));
    }

    function removeT0DebtToCollateral(address borrower_) external {
        _heap.remove(borrower_, _heap.indices[borrower_]);
    }

    function getT0DebtToCollateral(address borrower_) public view returns (uint256) {
        return _heap.getByIndex(_heap.indices[borrower_]).t0DebtToCollateral;
    }

    function getMaxT0DebtToCollateral() external view returns (uint256) {
        return _heap.getMax().t0DebtToCollateral;
    }

    function getMaxBorrower() external view returns (address) {
        return _heap.getMax().borrower;
    }

    function getTotalT0DebtToCollaterals() external view returns (uint256) {
        return _heap.loans.length;
    }


    /**
     *  @notice fills Heap with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 inserts_,       // number of insertions to perform
        uint256 seed_,          // seed for psuedorandom number generator
        bool trackInserts_
    ) external {
        uint256 tp;
        address borrower;

        // Calculate total insertions 
        uint256 totalInserts = bound(inserts_, 1000, 2000);
        uint256 insertsDec = totalInserts;

        // Initialize and print seed for randomness
        setRandomSeed(bound(seed_, 0, type(uint256).max - 1));

        while (insertsDec > 0) {

            // build address and TP
            borrower = makeAddr(vm.toString(insertsDec));
            tp = randomInRange(99_836_282_890, 1_004_968_987.606512354182109771 * 10**18, true);

            // Insert TP
            upsertT0DebtToCollateral(borrower, tp);
            insertsDec  -=  1;

            // Verify amount of Heap TPs
            assertEq(_heap.loans.length - 1, totalInserts - insertsDec);
            assertEq(getT0DebtToCollateral(borrower), tp);

            if (trackInserts_)  inserts.push(borrower);
        }

        assertEq(_heap.loans.length - 1, totalInserts);
    }
}
