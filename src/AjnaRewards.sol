// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Checkpoints.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { IPool } from './base/interfaces/IPool.sol';
import { IPositionManager } from './base/interfaces/IPositionManager.sol';
import { PositionManager } from './base/PositionManager.sol';

import './libraries/Maths.sol';

import { PoolCommons } from './libraries/external/PoolCommons.sol';

import './IAjnaRewards.sol';

contract AjnaRewards is IAjnaRewards {

    using Checkpoints for Checkpoints.History;
    using EnumerableSet for EnumerableSet.UintSet; // TODO: remove this?

    /**************/
    /*** Events ***/
    /**************/

    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 amount);

    /**
     *  @notice Emitted when lender deposits their LP NFT into the rewards contract.
     *  @param  owner        Owner of the staked NFT.
     *  @param  ajnaPool     Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId      ID of the staked NFT.
     */
    event DepositToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    /**
     *  @notice Emitted when lender withdraws their LP NFT from the rewards contract.
     *  @param  owner         Owner of the staked NFT.
     *  @param  ajnaPool      Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId       ID of the staked NFT.
     */
    event WithdrawToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    /**************/
    /*** Errors ***/
    /**************/

    error NotOwnerOfToken();

    /***********************/
    /*** State Variables ***/
    /***********************/

    address public immutable ajnaToken;

    IPositionManager public immutable positionManager;

    uint256 internal constant REWARD_FACTOR = 0.500000000000000000 * 1e18;

    // tokenID => Deposit information
    mapping(uint256 => Deposit) public deposits;

    // poolAddress => bucketIndex => checkpoint => exchangeRate
    mapping (address => mapping(uint256 => Checkpoints.History)) internal poolBucketExchangeRateCheckpoints;

    // poolAddress => checkpoint => totalInterest
    mapping (address => Checkpoints.History) internal poolTotalInterestCheckpoints;

    struct Deposit {
        address owner;
        address ajnaPool;
        uint256 lastInteractionBlock;
        mapping(uint256 => uint256) lpsAtDeposit; // total pool deposits in each of the buckets a position is in
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor (address ajnaToken_, IPositionManager positionManager_) {
        ajnaToken = ajnaToken_;
        positionManager = positionManager_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function depositNFT(uint256 tokenId_) external {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfToken();

        Deposit storage deposit = deposits[tokenId_];
        deposit.owner = msg.sender;
        deposit.ajnaPool = ajnaPool;
        deposit.lastInteractionBlock = block.number;

        // TODO: do these calculations inline
        _setPositionLPs(tokenId_);

        // update checkpoints
        _updateExchangeRates(tokenId_);
        _updatePoolTotalInterest(ajnaPool);

        emit DepositToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);
    }

    function withdrawNFT(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        address ajnaPool = deposits[tokenId_].ajnaPool;

        // update checkpoints
        _updateExchangeRates(tokenId_);
        _updatePoolTotalInterest(ajnaPool);

        // claim rewards, if any
        _claimRewards(tokenId_);

        emit WithdrawToken(msg.sender, ajnaPool, tokenId_);

        // transfer LP NFT from contract to sender
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    function claimRewards(uint256 tokenId_) external {
        if (msg.sender != deposits[tokenId_].owner) revert NotOwnerOfToken();

        address ajnaPool = deposits[tokenId_].ajnaPool;

        // update checkpoints
        _updateExchangeRates(tokenId_);
        _updatePoolTotalInterest(ajnaPool);

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

        // TODO: use safeTransferFrom
        // transfer rewards to sender
        IERC20(ajnaToken).transferFrom(address(this), msg.sender, rewardsEarned);
    }

    function _calculateRewardsEarned(uint256 tokenId_) internal returns (uint256 rewards_) {
        Deposit storage deposit = deposits[tokenId_];
        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        address ajnaPool = deposit.ajnaPool;
        uint256 interestEarned = 0;
        uint256 lastInteractionBlock = deposit.lastInteractionBlock;

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

            unchecked {
                ++i;
            }
        }

        // calculate total interest accumulated by the pool over the claim period
        uint256 totalInterestAtLastClaim = poolTotalInterestCheckpoints[ajnaPool].getAtBlock(lastInteractionBlock);
        uint256 totalInterestCurrent = poolTotalInterestCheckpoints[ajnaPool].latest();
        
        uint256 totalInterestEarned = totalInterestCurrent - totalInterestAtLastClaim;

        rewards_ = REWARD_FACTOR * (interestEarned / totalInterestEarned) * _getAjnaTokensBurned(ajnaPool, lastInteractionBlock);
    }

    function _getAjnaTokensBurned(address ajnaPool_, uint256 lastBlock_) internal returns (uint256 ajnaTokensBurned_) {
        (uint256 burnAmountLatest, uint256 totalInterestLatest, uint256 totalBurnedLatest) = IPool(ajnaPool_).burnInfoLatest();

        (uint256 burnAmountAtBlock, uint256 totalInterestAtBlock, uint256 totalBurnedAtBlock) = IPool(ajnaPool_).burnInfoAtBlock(lastBlock_);

        return totalBurnedLatest - totalBurnedAtBlock;
    }

    // use deposits object instead of tokenId?
    function _updateExchangeRates(uint256 tokenId_) internal {
        address ajnaPool = PositionManager(address(positionManager)).poolKey(tokenId_);

        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        for (uint256 i = 0; i < positionPrices.length; ) {
            // push the lenders exchange rate into the checkpoint history
            poolBucketExchangeRateCheckpoints[ajnaPool][positionPrices[i]].push(IPool(ajnaPool).bucketExchangeRate(positionPrices[i]));

            unchecked {
                ++i;
            }
        }
    }

    function _updatePoolTotalInterest(address ajnaPool_) internal {
        // push the total interest into the checkpoint history
        poolTotalInterestCheckpoints[ajnaPool_].push(PoolCommons.accumulatedInterest());
    }

    function _setPositionLPs(uint256 tokenId_) internal {
        uint256[] memory positionPrices = positionManager.getPositionPrices(tokenId_);

        for (uint256 i = 0; i < positionPrices.length; ) {
            deposits[tokenId_].lpsAtDeposit[positionPrices[i]] = positionManager.getLPTokens(tokenId_, positionPrices[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

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
