// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager Owner Actions
 */
interface IRewardsManagerOwnerActions {

    /**
     *  @notice Claim ajna token rewards that have accrued to a staked LP NFT.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId    ID of the staked LP NFT.
     *  @param  claimEpoch The burn epoch to claim rewards for.
     */
    function claimRewards(
        uint256 tokenId,
        uint256 claimEpoch
    ) external;

    /**
     *  @notice Stake a LP NFT into the rewards contract.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId ID of the LP NFT to stake in the AjnaRewards contract.
     */
    function stake(
        uint256 tokenId
    ) external;

    /**
     *  @notice Withdraw a staked LP NFT from the rewards contract.
     *  @notice If rewards are available, claim all available rewards before withdrawal.
     *  @param  tokenId ID of the staked LP NFT.
     */
    function unstake(
        uint256 tokenId
    ) external;

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @notice Caller can claim 5% of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool    Address of the pool whose exchange rates are being updated.
     *  @param  indexes List of bucket indexes to be updated.
     *  @return Returns reward amount for updating bucket exchange rates.
     */
    function updateBucketExchangeRatesAndClaim(
        address pool,
        uint256[] calldata indexes
    ) external returns (uint256);

}