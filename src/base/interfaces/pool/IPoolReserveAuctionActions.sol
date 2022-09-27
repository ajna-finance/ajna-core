// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Reserve Auction Actions
 */
interface IPoolReserveAuctionActions {
    /**
     *  @notice Called by actor to start a Claimable Reserve Auction (CRA).
     */
    function startClaimableReserveAuction() external;

    /**
     *  @notice Purchases claimable reserves during a CRA using Ajna token.
     *  @param  maxAmount Maximum amount of quote token to purchase at the current auction price.
     *  @return amount    Actual amount of reserves taken.
     */
    function takeReserves(
        uint256 maxAmount
    ) external returns (uint256 amount);
}