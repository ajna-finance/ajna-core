// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Borrower Actions
 */
interface IPoolBorrowerActions {

    /**
     *  @notice Called by fully colalteralized borrowers to restamp the Neutral Price of the loan (only if loan is fully collateralized and not in auction).
     *  @notice The reason for stamping the neutral price on the loan is to provide some certainty to the borrower as to at what price they can expect to be liquidated.
     *  @notice This action can be initiated by borrower itself or by a different actor on behalf of borrower.
     *  @param  borrowerAddress The borrower address to restamp Neutral Price for.
     */
    function stampLoan(
        address borrowerAddress
    ) external;

}
