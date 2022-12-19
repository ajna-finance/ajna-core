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
     */
    function addQuoteToken(
        uint256 amount,
        uint256 index
    ) external;

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
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  maxAmount        The amount of unencumbered collateral (or the number of NFT tokens) to claim.
     *  @param  index            The bucket index from which unencumbered collateral will be removed.
     *  @return collateralAmount The amount of collateral removed.
     */
    function removeCollateral(
        uint256 maxAmount,
        uint256 index
    ) external returns (uint256 collateralAmount);

    /**
     *  @notice Called by lenders to remove an amount of credit at a specified price bucket.
     *  @param  maxAmount        The max amount of quote token to be removed by a lender.
     *  @param  index            The bucket index from which quote tokens will be removed.
     *  @return quoteTokenAmount The amount of quote token removed.
     */
    function removeQuoteToken(
        uint256 maxAmount,
        uint256 index
    ) external returns (uint256 quoteTokenAmount);

    /**
     *  @notice Called by lenders to transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     *  @param  indexes  Array of price buckets index at which LP tokens were moved.
     */
    function transferLPTokens(
        address owner,
        address newOwner,
        uint256[] calldata indexes
    ) external;
}

/*********************/
/*** Param Structs ***/
/*********************/

struct MoveQuoteParams {
    uint256 maxAmountToMove; // max amount to move between deposits
    uint256 fromIndex;       // the deposit index from where amount is moved
    uint256 toIndex;         // the deposit index where amount is moved to
    uint256 ptp;             // the Pool Threshold Price (used to determine if penalty should be applied
    uint256 htp;             // the Highest Threshold Price in pool
    uint256 poolDebt;        // the current debt of the pool
    uint256 rate;            // the interest rate in pool (used to calculate penalty)
    }

struct RemoveQuoteParams {
    uint256 maxAmount; // max amount to be removed
    uint256 index;     // the deposit index from where amount is removed
    uint256 ptp;       // the Pool Threshold Price (used to determine if penalty should be applied)
    uint256 htp;       // the Highest Threshold Price in pool
    uint256 poolDebt;  // the current debt of the pool
    uint256 rate;      // the interest rate in pool (used to calculate penalty)
}