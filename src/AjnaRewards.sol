// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IERC20 }    from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Checkpoints.sol';

import { IPool } from './base/interfaces/IPool.sol';
import { IPositionManager } from './base/interfaces/IPositionManager.sol';
import { PositionManager } from './base/PositionManager.sol';

import './libraries/Maths.sol';

import { PoolCommons } from './libraries/external/PoolCommons.sol';

import './IAjnaRewards.sol';

contract AjnaRewards is IAjnaRewards {

    using Checkpoints for Checkpoints.History;
    using SafeERC20   for IERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    address public immutable ajnaToken; // address of the AJNA token

    IPositionManager public immutable positionManager; // address of the PositionManager contract

    /**
     * @notice Reward factor by which to scale the total rewards earned.
     * @dev ensures that rewards issued to staked lenders in a given pool are less than the ajna tokens burned in that pool.
     */
    uint256 internal constant REWARD_FACTOR = 0.500000000000000000 * 1e18;

    /**
     * @notice Mapping of LP NFTs staked in the Ajna Rewards contract.
     * @dev tokenID => Deposit
     */
    mapping(uint256 => Deposit) public deposits;

    /**
     * @notice Mapping of per pool bucket exchange rates, checkpointed by block.
     * @dev Checkpoints for a given bucket are updated everytime any depositer staked in that bucket interacts with the rewards contract.
     * @dev poolAddress => bucketIndex => checkpoint => exchangeRate
     */
    mapping(address => mapping(uint256 => Checkpoints.History)) internal poolBucketExchangeRateCheckpoints;

    struct Deposit {
        address owner;                            // owner of the LP NFT
        address ajnaPool;                         // address of the Ajna pool the NFT corresponds to
        uint256 lastInteractionBlock;             // last block the deposit interacted with the rewards contract
        mapping(uint256 => uint256) lpsAtDeposit; // total pool deposits in each of the buckets a position is in
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(address ajnaToken_, IPositionManager positionManager_) {
        ajnaToken = ajnaToken_;
        positionManager = positionManager_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deposit a LP NFT into the rewards contract.
     *  @dev    Underlying NFT LP positions cannot change while staked. Retrieves exchange rates for each bucket the NFT is associated with.
     *  @param  tokenId_ ID of the LP NFT to stake in the AjnaRewards contract.
     */
    function depositNFT(uint256 tokenId_) external {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfToken();

        Deposit storage deposit = deposits[tokenId_];
        deposit.owner = msg.sender;
        deposit.ajnaPool = ajnaPool;
        deposit.lastInteractionBlock = block.number;

        _setPositionLPs(tokenId_);

        // update checkpoints
        _updateExchangeRates(tokenId_);

        emit DepositToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);
    }

    /**
     *  @notice Withdraw a staked LP NFT from the rewards contract.
     *  @dev    If rewards are available, claim all available rewards before withdrawal.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function withdrawNFT(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        address ajnaPool = deposits[tokenId_].ajnaPool;

        // update checkpoints
        _updateExchangeRates(tokenId_);

        // claim rewards, if any
        _claimRewards(tokenId_);

        delete deposits[tokenId_];

        // transfer LP NFT from contract to sender
        emit WithdrawToken(msg.sender, ajnaPool, tokenId_);
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    /**
     *  @notice Claim ajna token rewards that have accrued to a staked LP NFT.
     *  @param  tokenId_ ID of the staked LP NFT.
     */
    function claimRewards(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        // update checkpoints
        _updateExchangeRates(tokenId_);

        _claimRewards(tokenId_);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _claimRewards(uint256 tokenId_) internal {
        uint256 rewardsEarned = _calculateRewardsEarned(tokenId_);

        emit ClaimRewards(msg.sender, deposits[tokenId_].ajnaPool, tokenId_, rewardsEarned);

        // update last interaction block
        deposits[tokenId_].lastInteractionBlock = block.number;

        // transfer rewards to sender
        if (rewardsEarned > IERC20(ajnaToken).balanceOf(address(this))) rewardsEarned = IERC20(ajnaToken).balanceOf(address(this));
        IERC20(ajnaToken).safeTransfer(msg.sender, rewardsEarned);
    }

    function _calculateRewardsEarned(uint256 tokenId_) internal view returns (uint256 rewards_) {
        Deposit storage deposit = deposits[tokenId_];
        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        address ajnaPool = deposit.ajnaPool;
        uint256 interestEarned = 0;
        uint256 lastInteractionBlock = deposit.lastInteractionBlock;

        // calculate accrued interest as determined by the difference in exchange rates between the last interaction block and the current block
        for (uint256 i = 0; i < positionPrices.length; ) {
            uint256 lastClaimedExchangeRate = poolBucketExchangeRateCheckpoints[ajnaPool][positionPrices[i]].getAtBlock(lastInteractionBlock);
            uint256 currentExchangeRate = poolBucketExchangeRateCheckpoints[ajnaPool][positionPrices[i]].latest();

            uint256 quoteAtLastClaimed = Maths.rayToWad(Maths.rmul(lastClaimedExchangeRate, deposit.lpsAtDeposit[positionPrices[i]]));
            uint256 quoteAtCurrentRate = Maths.rayToWad(Maths.rmul(currentExchangeRate, deposit.lpsAtDeposit[positionPrices[i]]));

            if (quoteAtCurrentRate > quoteAtLastClaimed) {
                interestEarned += quoteAtCurrentRate - quoteAtLastClaimed;
            }
            else {
                interestEarned -= quoteAtLastClaimed - quoteAtCurrentRate;
            }

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }

        // retrieve total interest accumulated by the pool over the claim period, and total tokens burned over that period
        (uint256 ajnaTokensBurned, uint256 totalInterestEarned) = _getPoolAccumulators(ajnaPool, lastInteractionBlock);

        // calculate rewards earned
        if (totalInterestEarned == 0) return 0;
        rewards_ = Maths.wmul(REWARD_FACTOR, Maths.wmul(Maths.wdiv(interestEarned, totalInterestEarned), ajnaTokensBurned));
    }

    /**
     *  @notice Retrieve the total ajna tokens burned and total interest earned by a pool since a given block.
     *  @param  ajnaPool_  Address of the Ajna pool to retrieve accumulators of.
     *  @param  lastBlock_ Block number to use as checkpoint since which values should have accumulated.
     */
    function _getPoolAccumulators(address ajnaPool_, uint256 lastBlock_) internal view returns (uint256 ajnaTokensBurned_, uint256 totalInterestEarned_) {
        (uint256 totalInterestLatest, uint256 totalBurnedLatest) = IPool(ajnaPool_).burnInfoLatest();
        (uint256 totalInterestAtBlock, uint256 totalBurnedAtBlock) = IPool(ajnaPool_).burnInfoAtBlock(lastBlock_);

        ajnaTokensBurned_ = totalBurnedLatest - totalBurnedAtBlock;
        totalInterestEarned_ = totalInterestLatest - totalInterestAtBlock;
    }

    // TODO: use deposits object instead of tokenId?
    function _updateExchangeRates(uint256 tokenId_) internal {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        for (uint256 i = 0; i < positionPrices.length; ) {
            // push the lenders exchange rate into the checkpoint history
            uint256 bucketExchangeRate = IPool(ajnaPool).bucketExchangeRate(positionPrices[i]);
            poolBucketExchangeRateCheckpoints[ajnaPool][positionPrices[i]].push(bucketExchangeRate);

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }
    }

    function _setPositionLPs(uint256 tokenId_) internal {
        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        for (uint256 i = 0; i < positionPrices.length; ) {
            deposits[tokenId_].lpsAtDeposit[positionPrices[i]] = positionManager.getLPTokens(tokenId_, positionPrices[i]);

            // iterations are bounded by array length (which is itself bounded), preventing overflow / underflow
            unchecked {
                ++i;
            }
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function calculateRewardsEarned(uint256 tokenId_) external view returns (uint256 rewards_) {
        return _calculateRewardsEarned(tokenId_);
    }

    /**
     *  @notice Retrieve information about a given deposit.
     *  @param  tokenId_  ID of the NFT deposited into the rewards contract to retrieve information about.
     *  @return The owner of a given NFT deposit.
     *  @return The Pool the NFT represents positions in.
     *  @return The last block in which the owner of the NFT interacted with the rewards contract.
     */
    function getDepositInfo(uint256 tokenId_) external view returns (address, address, uint256) {
        Deposit storage deposit = deposits[tokenId_];
        return (deposit.owner, deposit.ajnaPool, deposit.lastInteractionBlock);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
