// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool Lender Actions
 */
interface IPoolLenderActions {
    /**
     *  @notice Called by lenders to add an amount of credit at a specified price bucket.
     *  @param  amount    The amount of quote token to be added by a lender.
     *  @param  index     The index of the bucket to which the quote tokens will be added.
     *  @return lpbChange The amount of LP Tokens changed for the added quote tokens.
     */
    function addQuoteToken(
        uint256 amount,
        uint256 index
    ) external returns (uint256 lpbChange);

    /**
     *  @notice Called by lenders to approve transfer of LP tokens to a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  allowedNewOwner The new owner of the LP tokens.
     *  @param  index           The index of the bucket from where LPs tokens are transferred.
     *  @param  amount          The amount of LP tokens approved to transfer.
     */
    function approveLpOwnership(
        address allowedNewOwner,
        uint256 index,
        uint256 amount
    ) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  maxAmount     The maximum amount of quote token to be moved by a lender.
     *  @param  fromIndex     The bucket index from which the quote tokens will be removed.
     *  @param  toIndex       The bucket index to which the quote tokens will be added.
     *  @return lpbAmountFrom The amount of LPs moved out from bucket.
     *  @return lpbAmountTo   The amount of LPs moved to destination bucket.
     */
    function moveQuoteToken(
        uint256 maxAmount,
        uint256 fromIndex,
        uint256 toIndex
    ) external returns (uint256 lpbAmountFrom, uint256 lpbAmountTo);

    /**
     *  @notice Called by lenders to claim collateral from a price bucket.
     *  @param  maxAmount        The amount of collateral (or the number of NFT tokens) to claim.
     *  @param  index            The bucket index from which collateral will be removed.
     *  @return collateralAmount The amount of collateral removed.
     *  @return lpAmount         The amount of LP used for removing collateral amount.
     */
    function removeCollateral(
        uint256 maxAmount,
        uint256 index
    ) external returns (uint256 collateralAmount, uint256 lpAmount);

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  maxAmount        The max amount of quote token to be removed by a lender.
     *  @param  index            The bucket index from which quote tokens will be removed.
     *  @return quoteTokenAmount The amount of quote token removed.
     *  @return lpAmount         The amount of LP used for removing quote tokens amount.
     */
    function removeQuoteToken(
        uint256 maxAmount,
        uint256 index
    ) external returns (uint256 quoteTokenAmount, uint256 lpAmount);

    /**
     *  @notice Called by lenders to transfers their LP tokens to a different address. approveLpOwnership needs to be run first
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     *  @param  indexes  Array of price buckets index at which LP tokens were moved.
     */
    function transferLPs(
        address owner,
        address newOwner,
        uint256[] calldata indexes
    ) external;
}
