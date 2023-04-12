// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Kicker Actions
 */
interface IPoolKickerActions {

    /********************/
    /*** Liquidations ***/
    /********************/

    /**
     *  @notice Called by actors to initiate a liquidation.
     *  @param  borrower     Identifies the loan to liquidate.
     *  @param  npLimitIndex Index of the lower bound of NP tolerated when kicking the auction.
     */
    function kick(
        address borrower,
        uint256 npLimitIndex
    ) external;

    /**
     *  @notice Called by lenders to liquidate the top loan using their deposits.
     *  @param  index        The deposit index to use for kicking the top loan.
     *  @param  npLimitIndex Index of the lower bound of NP tolerated when kicking the auction.
     */
    function kickWithDeposit(
        uint256 index,
        uint256 npLimitIndex
    ) external;

    /**
     *  @notice Called by kickers to withdraw their auction bonds (the amount of quote tokens that are not locked in active auctions).
     *  @param  recipient Address to receive claimed bonds amount.
     *  @param  maxAmount The max amount to withdraw from auction bonds. Constrained by claimable amounts and liquidity
     */
    function withdrawBonds(
        address recipient,
        uint256 maxAmount
    ) external;

    /***********************/
    /*** Reserve Auction ***/
    /***********************/

    /**
     *  @notice Called by actor to start a Claimable Reserve Auction (CRA).
     */
    function kickReserveAuction() external;
}