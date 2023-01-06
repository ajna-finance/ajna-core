// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;


interface IAjnaRewards {

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Claim ajna token rewards that have accrued to a staked LP NFT.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId    ID of the staked LP NFT.
     *  @param  startEpoch The burn epoch to start claim.
     */
    function claimRewards(
        uint256 tokenId,
        uint256 startEpoch
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

    /**********************************************/
    /*** External Non State Modifiers Functions ***/
    /**********************************************/

    /**
     *  @notice Calculate the amount of rewards that have been accumulated by a staked NFT.
     *  @param  tokenId    ID of the staked LP NFT.
     *  @param  startEpoch The burn epoch from which to start the calculations
     *  @return rewards_   The amount of rewards earned by the NFT.
     */
    function calculateRewards(
        uint256 tokenId,
        uint256 startEpoch
    ) external returns (uint256);

    /**
     *  @notice Retrieve information about a given stake.
     *  @param  tokenId  ID of the NFT staked in the rewards contract to retrieve information about.
     *  @return The owner of a given NFT stake.
     *  @return The Pool the NFT represents positions in.
     *  @return The last burn epoch in which the owner of the NFT interacted with the rewards contract.
     */
    function getStakeInfo(
        uint256 tokenId
    ) external view returns (address, address, uint256);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Track whether a depositor has claimed rewards for a given burn event epoch.
     *  @param  tokenId ID of the staked LP NFT.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return True if rewards were claimed for the given epoch, else false.
     */
    function isEpochClaimed(
        uint256 tokenId,
        uint256 epoch
    ) external view returns (bool);

    /**
     *  @notice Track the total amount of rewards that have been claimed for a given epoch.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return The amount of rewards claimed in given epoch.
     */
    function rewardsClaimed(
        uint256 epoch
    ) external view returns (uint256);

    /**
     *  @notice Track the total amount of rewards that have been claimed for a given burn event's bucket updates.
     *  @param  epoch   The burn epoch to track if rewards were claimed.
     *  @return The amount of update rewards claimed in given epoch.
     */
    function updateRewardsClaimed(
        uint256 epoch
    ) external view returns (uint256);

    /**************/
    /*** Errors ***/
    /**************/

    /**
     *  @notice User attempted to claim rewards multiple times.
     */
    error AlreadyClaimed();

    /**
     *  @notice User attempted to record updated exchange rates outside of the allowed period.
     */
    error ExchangeRateUpdateTooLate();

    /**
     *  @notice User attempted to interact with an NFT they aren't the owner of.
     */
    error NotOwnerOfDeposit();

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when lender claims rewards that have accrued to their staked NFT.
     *  @param  owner         Owner of the staked NFT.
     *  @param  ajnaPool      Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId       ID of the staked NFT.
     *  @param  epochsClaimed Array of burn epochs claimed.
     *  @param  amount        The amount of AJNA tokens claimed by the staker.
     */
    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256[] epochsClaimed, uint256 amount);

    /**
     *  @notice Emitted when lender stakes their LP NFT in the rewards contract.
     *  @param  owner    Owner of the staked NFT.
     *  @param  ajnaPool Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId  ID of the staked NFT.
     */
    event StakeToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    /**
     *  @notice Emitted when someone records the latest exchange rate for a bucket in a pool, and claims the associated reward.
     *  @param  caller          Address of the recorder. The address which will receive an update reward, if applicable.
     *  @param  ajnaPool        Address of the Ajna pool whose exchange rates are being updated.
     *  @param  indexesUpdated  Array of bucket indexes whose exchange rates are being updated.
     *  @param  rewardsClaimed  Amount of ajna tokens claimed by the recorder as a reward for updating each bucket index.
     */
    event UpdateExchangeRates(address indexed caller, address indexed ajnaPool, uint256[] indexesUpdated, uint256 rewardsClaimed);

    /**
     *  @notice Emitted when lender withdraws their LP NFT from the rewards contract.
     *  @param  owner    Owner of the staked NFT.
     *  @param  ajnaPool Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId  ID of the staked NFT.
     */
    event UnstakeToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    /*********************/
    /*** State Structs ***/
    /*********************/

    struct Stake {
        address ajnaPool;                         // address of the Ajna pool the NFT corresponds to
        uint96  lastInteractionBurnEpoch;         // last burn event the stake interacted with the rewards contract
        address owner;                            // owner of the LP NFT
        uint96  stakingEpoch;                     // epoch at staking time
        mapping(uint256 => BucketState) snapshot; // the LP NFT's balances and exchange rates in each bucket at the time of staking
    }

    struct BucketState {
        uint256 lpsAtStakeTime;
        uint256 rateAtStakeTime;
    }

}
