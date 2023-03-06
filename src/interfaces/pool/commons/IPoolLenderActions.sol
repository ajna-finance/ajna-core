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
     *  @param  expiry    Timestamp after which this TX will revert, preventing inclusion in a block with unfavorable price.
     *  @return lpbChange The amount of LPs changed for the added quote tokens.
     */
    function addQuoteToken(
        uint256 amount,
        uint256 index,
        uint256 expiry
    ) external returns (uint256 lpbChange);

    /**
     *  @notice Called by lenders to approve transfer of an amount of LPs to a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  spender The new owner of the LPs.
     *  @param  indexes         Bucket indexes from where LPs are transferred.
     *  @param  amounts         The amounts of LPs approved to transfer.
     */
    function increaseLPAllowance(
        address spender,
        uint256[] calldata indexes,
        uint256[] calldata amounts
    ) external;

    /**
     *  @notice Called by lenders to decrease the amount of LPs that can be spend by a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  spender The new owner of the LPs.
     *  @param  indexes         Bucket indexes from where LPs are transferred.
     *  @param  amounts         The amounts of LPs approved to transfer.
     */
    function decreaseLPAllowance(
        address spender,
        uint256[] calldata indexes,
        uint256[] calldata amounts
    ) external;

    /**
     *  @notice Called by lenders to allow addresses that can transfer LPs.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  transferors Addresses that are allowed to transfer LPs to lender.
     */
    function approveLpTransferors(
        address[] calldata transferors
    ) external;

    /**
     *  @notice Called by lenders to revoke addresses that can transfer LPs.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  transferors Addresses that are revoked to transfer LPs to lender.
     */
    function revokeLpTransferors(
        address[] calldata transferors
    ) external;

    /**
     *  @notice Called by lenders to move an amount of credit from a specified price bucket to another specified price bucket.
     *  @param  maxAmount        The maximum amount of quote token to be moved by a lender.
     *  @param  fromIndex        The bucket index from which the quote tokens will be removed.
     *  @param  toIndex          The bucket index to which the quote tokens will be added.
     *  @param  expiry           Timestamp after which this TX will revert, preventing inclusion in a block with unfavorable price.
     *  @return lpbAmountFrom    The amount of LPs moved out from bucket.
     *  @return lpbAmountTo      The amount of LPs moved to destination bucket.
     *  @return quoteTokenAmount The amount of quote token moved.
     */
    function moveQuoteToken(
        uint256 maxAmount,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 expiry
    ) external returns (uint256 lpbAmountFrom, uint256 lpbAmountTo, uint256 quoteTokenAmount);

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
     *  @return lpAmount         The amount of LPs used for removing quote tokens amount.
     */
    function removeQuoteToken(
        uint256 maxAmount,
        uint256 index
    ) external returns (uint256 quoteTokenAmount, uint256 lpAmount);

    /**
     *  @notice Called by lenders to decrease the amount of LPs that can be spend by a new owner.
     *  @param  spender Address that is having it's allowance revoked.
     *  @param  indexes List of bucket index to remove the allowance from.
     */
    function revokeLPAllowance(
        address spender,
        uint256[] calldata indexes
    ) external;

    /**
     *  @notice Called by lenders to transfers their LPs to a different address. approveLpOwnership needs to be run first
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     *  @param  indexes  Array of price buckets index at which LPs were moved.
     */
    function transferLPs(
        address owner,
        address newOwner,
        uint256[] calldata indexes
    ) external;

    /**
     *  @notice Called by lenders to update pool interest rate (can be updated only once in a 12 hours period of time).
     */
    function updateInterest() external;
}
