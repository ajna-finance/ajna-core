// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager Errors
 */
interface IRewardsManagerErrors {
    /**
     *  @notice User attempted to claim rewards multiple times.
     */
    error AlreadyClaimed();

    /**
     *  @notice User attempted to claim rewards for an epoch that is not yet available.
     */
    error EpochNotAvailable();

    /**
     *  @notice User provided move index params that didn't match in size.
     */
    error MoveStakedLiquidityInvalid();

    /**
     *  @notice User attempted to interact with an NFT they aren't the owner of.
     */
    error NotOwnerOfDeposit();

    /**
     *  @notice Can't deploy with Ajna token address 0x0 address.
     */
    error DeployWithZeroAddress();
}