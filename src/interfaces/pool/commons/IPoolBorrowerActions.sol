// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

/**
 * @title Pool Borrower Actions
 */
interface IPoolBorrowerActions {

    /**
     *  @notice Called by fully collateralized borrowers to restamp the `Np to Tp ratio` of the loan (only if loan is fully collateralized and not in auction).
     *          The reason for stamping the `Np to Tp ratio` on the loan is to provide some certainty to the borrower as to at what price they can expect to be liquidated.
     *          This action can restamp only the loan of `msg.sender`.
     */
    function stampLoan() external;

}
