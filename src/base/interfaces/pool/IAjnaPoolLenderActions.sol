// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title Ajna Pool Lender Actions
 */
interface IAjnaPoolLenderActions {
    /**
     *  @notice Called by lenders to add an amount of credit at a specified price bucket.
     *  @param  index     The index of the bucket to which the quote tokens will be added.
     *  @param  amount    The amount of quote token to be added by a lender.
     *  @return lpbChange The amount of LP Tokens changed for the added quote tokens.
     */
    function addQuoteToken(
        uint256 index,
        uint256 amount
    ) external returns (uint256 lpbChange);

    /**
     *  @notice Called by lenders to approve transfer of LP tokens to a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  index           The index of the bucket from where LPs tokens are transferred.
     *  @param  amount          The amount of LP tokens approved to transfer.
     *  @param  allowedNewOwner The new owner of the LP tokens.
     */
    function approveLpOwnership(
        uint256 index,
        uint256 amount,
        address allowedNewOwner
    ) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  fromIndex     The bucket index from which the quote tokens will be removed.
     *  @param  toIndex       The bucket index to which the quote tokens will be added.
     *  @param  maxAmount     The maximum amount of quote token to be moved by a lender.
     *  @return lpbAmountFrom The amount of LPs moved out from bucket.
     *  @return lpbAmountTo   The amount of LPs moved to destination bucket.
     */
    function moveQuoteToken(
        uint256 fromIndex,
        uint256 toIndex,
        uint256 maxAmount
    ) external returns (uint256 lpbAmountFrom, uint256 lpbAmountTo);

    /**
     *  @notice Called by lenders to redeem the maximum amount of LP for quote token.
     *  @param  index           The bucket index from which quote tokens will be removed.
     *  @return quoteTokenAmount The amount of quote token removed.
     *  @return lpAmount         The amount of LP used for removing quote tokens.
     */
    function removeAllQuoteToken(
        uint256 index
    ) external returns (uint256 quoteTokenAmount, uint256 lpAmount);

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  index       The bucket index from which quote tokens will be removed.
     *  @param  amount      The amount of quote token to be removed by a lender.
     *  @return lpAmount    The amount of LP used for removing quote tokens amount.
     */
    function removeQuoteToken(
        uint256 index,
        uint256 amount
    ) external returns (uint256 lpAmount);

    /**
     *  @notice Called by lenders to transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  indexes  Array of price buckets index at which LP tokens were moved.
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     */
    function transferLPTokens(
        uint256[] calldata indexes,
        address owner,
        address newOwner
    ) external;
}