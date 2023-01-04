// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;


interface IAjnaRewards {

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
