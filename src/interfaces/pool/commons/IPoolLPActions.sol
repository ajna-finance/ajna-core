// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Pool LP Actions
 */
interface IPoolLPActions {

    /**
     *  @notice Called by LP owners to approve transfer of an amount of LP to a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  spender The new owner of the LP.
     *  @param  indexes Bucket indexes from where LP are transferred.
     *  @param  amounts The amounts of LP approved to transfer.
     */
    function increaseLPAllowance(
        address spender,
        uint256[] calldata indexes,
        uint256[] calldata amounts
    ) external;

    /**
     *  @notice Called by LP owners to decrease the amount of LP that can be spend by a new owner.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  spender The new owner of the LP.
     *  @param  indexes Bucket indexes from where LP are transferred.
     *  @param  amounts The amounts of LP disapproved to transfer.
     */
    function decreaseLPAllowance(
        address spender,
        uint256[] calldata indexes,
        uint256[] calldata amounts
    ) external;

    /**
     *  @notice Called by LP owners to decrease the amount of LP that can be spend by a new owner.
     *  @param  spender Address that is having it's allowance revoked.
     *  @param  indexes List of bucket index to remove the allowance from.
     */
    function revokeLPAllowance(
        address spender,
        uint256[] calldata indexes
    ) external;

    /**
     *  @notice Called by LP owners to allow addresses that can transfer LP.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  transferors Addresses that are allowed to transfer LP to new owner.
     */
    function approveLPTransferors(
        address[] calldata transferors
    ) external;

    /**
     *  @notice Called by LP owners to revoke addresses that can transfer LP.
     *  @dev    Intended for use by the PositionManager contract.
     *  @param  transferors Addresses that are revoked to transfer LP to new owner.
     */
    function revokeLPTransferors(
        address[] calldata transferors
    ) external;

    /**
     *  @notice Called by LP owners to transfers their LP to a different address. approveLpOwnership needs to be run first
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner    The original owner address of the position.
     *  @param  newOwner The new owner address of the position.
     *  @param  indexes  Array of price buckets index at which LP were moved.
     */
    function transferLP(
        address owner,
        address newOwner,
        uint256[] calldata indexes
    ) external;
}
