// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Checkpoints.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './base/interfaces/IPool.sol';
import './base/interfaces/IPositionManager.sol';
import './base/PositionManager.sol';

import './libraries/Maths.sol';
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
     *  @param  depositBlock Block number in which the NFT was staked.
     */
    event DepositToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 depositBlock);

    /**
     *  @notice Emitted when lender withdraws their LP NFT from the rewards contract.
     *  @param  owner         Owner of the staked NFT.
     *  @param  ajnaPool      Address of the Ajna pool the NFT corresponds to.
     *  @param  tokenId       ID of the staked NFT.
     *  @param  withdrawBlock Block number in which the NFT was withdrawn.
     */
    event WithdrawToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 withdrawBlock);

    /**************/
    /*** Errors ***/
    /**************/

    error NotOwnerOfToken();

    /***********************/
    /*** State Variables ***/
    /***********************/

    // tokenID => Deposit information
    mapping(uint256 => Deposit) public deposits;

    // poolAddress => bucketIndex => checkpoint => exchangeRate
    mapping (address => mapping(uint256 => Checkpoints.History)) internal poolBucketExchangeRateCheckpoints;

    address public immutable ajnaToken;

    IPositionManager public immutable positionManager;

    struct Deposit {
        address owner;
        address ajnaPool;
        uint256 depositBlock;
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
        deposit.depositBlock = block.number;

        // TODO: do these calculations inline
        _setPositionLPs(tokenId_);

        _updateExchangeRates(tokenId_);

        emit DepositToken(msg.sender, ajnaPool, tokenId_, block.number);

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);
    }

    function withdrawNFT(uint256 tokenId_) external {

        _updateExchangeRates(tokenId_);

        // claim rewards, if any
        _claimRewards(tokenId_);

        emit WithdrawToken(msg.sender, deposits[tokenId_].ajnaPool, tokenId_, block.number);

        // transfer LP NFT from contract to sender
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    function claimRewards(uint256 tokenId_) external {

        _updateExchangeRates(tokenId_);

        _claimRewards(tokenId_);
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _claimRewards(uint256 tokenId_) internal {

        Deposit storage deposit = deposits[tokenId_];

        uint256 blocksElapsed = block.number - deposit.depositBlock;
        // uint256 interestEarnedByDeposit = _calculateInterestEarned(tokenId_, deposit.exchangeRatesAtDeposit, _getExchangeRates(tokenId_));

        // TODO: implement this
        // calculate proportion of interest earned by deposit to total interest earned
        // multiply by total ajna tokens burned

        uint256 rewardsEarned = 0;
        emit ClaimRewards(msg.sender, deposits[tokenId_].ajnaPool, tokenId_, rewardsEarned);

        // TODO: use safeTransferFrom
        // transfer rewards to sender
        IERC20(ajnaToken).transferFrom(address(this), msg.sender, rewardsEarned);

    }

    // function _calculateInterestEarned(uint256 tokenId_, uint256[] memory exchangeRatesAtDeposit, uint256[] memory exchangeRatesNow) internal view returns (uint256 interestEarned_) {
    //     for (uint256 i = 0; i < exchangeRatesAtDeposit.length; ) {

    //         uint256 lpTokens = IPositionManager(positionManager).getLPTokens(tokenId_, exchangeRatesAtDeposit[i]);

    //         uint256 quoteAtDeposit = Maths.rayToWad(Maths.rmul(exchangeRatesAtDeposit[i], lpTokens));
    //         uint256 quoteNow = Maths.rayToWad(Maths.rmul(exchangeRatesNow[i], lpTokens));

    //         if (quoteNow > quoteAtDeposit) {
    //             interestEarned_ += quoteNow - quoteAtDeposit;
    //         }
    //         else {
    //             interestEarned_ -= quoteAtDeposit - quoteNow;
    //         }

    //         unchecked {
    //             ++i;
    //         }
    //     }
    // }

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
        return (deposit.owner, deposit.ajnaPool, deposit.depositBlock);
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
