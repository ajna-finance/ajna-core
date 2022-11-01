// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Lender Actions
 */
interface IERC721PoolLenderActions {

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  tokenIds Array of collateral to deposit.
     *  @param  index    The bucket index to which collateral will be deposited.
     */
    function addCollateral(
        uint256[] calldata tokenIds,
        uint256 index
    ) external returns (uint256);
}