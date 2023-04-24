// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 * @title Rewards Manager Owner Actions
 */
interface IRewardsManagerOwnerActions {

    /**
     *  @notice Claim `Ajna` token rewards that have accrued to a staked `LP` `NFT`.
     *  @dev    Updates exchange rates for each bucket the `NFT` is associated with.
     *  @param  tokenId_      `ID` of the staked `LP` `NFT`.
     *  @param  epochToClaim_ The burn epoch to claim rewards for.
     */
    function claimRewards(
        uint256 tokenId_,
        uint256 epochToClaim_
    ) external;

    /**
     *  @notice Moves liquidity in a staked `NFT` between buckets.
     *  @dev    Calls out to `PositionManager.moveLiquidity()`.
     *  @dev    Automatically claims any available rewards in all existing buckets. Updates exchange rates for each new bucket the `NFT` is associated with.
     *  @dev    `fromBuckets_` and `toBuckets_` must be the same array length. Liquidity is moved from the `fromBuckets_` to the `toBuckets_` in the same index.
     *  @param  tokenId_     `ID` of the staked `LP` `NFT`.
     *  @param  fromBuckets_ The list of bucket indexes to move liquidity from.
     *  @param  toBuckets_   The list of bucket indexes to move liquidity to.
     *  @param  expiry_      Timestamp after which this transaction will revert, preventing inclusion in a block with unfavorable price.
     */
    function moveStakedLiquidity(
        uint256 tokenId_,
        uint256[] memory fromBuckets_,
        uint256[] memory toBuckets_,
        uint256 expiry_
    ) external;

    /**
     *  @notice Stake a `LP` `NFT` into the rewards contract.
     *  @dev    Updates exchange rates for each bucket the `NFT` is associated with.
     *  @param  tokenId_ `ID` of the `LP` `NFT` to stake in the `Rewards contract.
     */
    function stake(
        uint256 tokenId_
    ) external;

    /**
     *  @notice Withdraw a staked `LP` `NFT` from the rewards contract.
     *  @notice If rewards are available, claim all available rewards before withdrawal.
     *  @param  tokenId_ `ID` of the staked `LP` `NFT`.
     */
    function unstake(
        uint256 tokenId_
    ) external;

    /**
     *  @notice Update the exchange rate of a list of buckets.
     *  @dev    Caller can claim `5%` of the rewards that have accumulated to each bucket since the last burn event, if it hasn't already been updated.
     *  @param  pool_    Address of the pool whose exchange rates are being updated.
     *  @param  indexes_ List of bucket indexes to be updated.
     *  @return Returns reward amount for updating bucket exchange rates.
     */
    function updateBucketExchangeRatesAndClaim(
        address pool_,
        uint256[] calldata indexes_
    ) external returns (uint256);

}