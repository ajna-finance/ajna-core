// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import './base/interfaces/IPool.sol';
import './base/interfaces/IPositionManager.sol';
import './libraries/Maths.sol';
import './IAjnaRewards.sol';

contract AjnaRewards is IAjnaRewards {

    using EnumerableSet for EnumerableSet.UintSet;

    /**************/
    /*** Events ***/
    /**************/

    event DepositToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 depositBlock);

    /**************/
    /*** Errors ***/
    /**************/

    error NotOwnerOfToken();

    /***********************/
    /*** State Variables ***/
    /***********************/

    // tokenID => Deposit information
    mapping(uint256 => Deposit) public deposits;

    // FIXME: remove if unneeded with mapping in Deposit struct
    // depositBlock => bucketIndex => lps
    // mapping (uint256 => mapping(uint256 => uint256)) public positionLpsAtDeposit;

    address public immutable ajnaToken;

    IPositionManager public immutable positionManager;

    // TODO: add varible to track set of indexes, and volume of deposits in each index -> available in positionPrices
    struct Deposit {
        address owner;
        address ajnaPool;
        uint256 depositBlock;
        uint256[] exchangeRatesAtDeposit;
        mapping(uint256 => uint256) lpsAtDeposit; // total pool deposits in each of the buckets a position is in
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor (address ajnaToken_, IPositionManager positionManager_) public {
        ajnaToken = ajnaToken_;
        positionManager = positionManager_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function depositNFT(address ajnaPool_, uint256 tokenId_) external {

        // TODO: check that ajnaPool_ is a valid AjnaPool

        // check that msg.sender is owner of tokenId
        if (IERC721(address(positionManager)).ownerOf(tokenId_) != msg.sender) revert NotOwnerOfToken();

        Deposit storage deposit = deposits[tokenId_];
        deposit.owner = msg.sender;
        deposit.ajnaPool = ajnaPool_;
        deposit.depositBlock = block.number;

        deposit.exchangeRatesAtDeposit = _getExchangeRates(tokenId_);

        // TODO: figure out how to store the total lps in each of these buckets at the time of deposit

        // transfer LP NFT to this contract
        IERC721(address(positionManager)).safeTransferFrom(msg.sender, address(this), tokenId_);

    }

    function withdrawNFT(uint256 tokenId_) external {

        // claim rewards, if any
        _claimRewards(tokenId_);

        // transfer LP NFT from contract to sender
        IERC721(address(positionManager)).safeTransferFrom(address(this), msg.sender, tokenId_);
    }

    function claimRewards(uint256 tokenId_) external {

        _claimRewards(tokenId_);

    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _claimRewards(uint256 tokenId_) internal {

        Deposit storage deposit = deposits[tokenId_];

        uint256 blocksElapsed = block.number - deposit.depositBlock;
        uint256 interestEarnedByDeposit = _calculateInterestEarned(tokenId_, deposit.exchangeRatesAtDeposit, _getExchangeRates(tokenId_));

        // TODO: implement this
        // calculate proportion of interest earned by deposit to total interest earned
        // multiply by total ajna tokens burned
        uint256 rewardsEarned;

        // TODO: use safeTransferFrom
        // transfer rewards to sender
        IERC20(ajnaToken).transferFrom(address(this), msg.sender, rewardsEarned);

    }

    function _calculateInterestEarned(uint256 tokenId_, uint256[] memory exchangeRatesAtDeposit, uint256[] memory exchangeRatesNow) internal view returns (uint256 interestEarned_) {

        for (uint256 i = 0; i < exchangeRatesAtDeposit.length; ) {

            uint256 lpTokens = IPositionManager(positionManager).getLPTokens(tokenId_, exchangeRatesAtDeposit[i]);

            uint256 quoteAtDeposit = Maths.rayToWad(Maths.rmul(exchangeRatesAtDeposit[i], lpTokens));
            uint256 quoteNow = Maths.rayToWad(Maths.rmul(exchangeRatesNow[i], lpTokens));

            if (quoteNow > quoteAtDeposit) {
                interestEarned_ += quoteNow - quoteAtDeposit;
            }
            else {
                interestEarned_ -= quoteAtDeposit - quoteNow;
            }

            unchecked {
                ++i;
            }
        }
    }

    // TODO: implement this
    function _calculateTokensBurned() internal pure returns (uint256 tokensBurned_) {

    }

    function _getExchangeRates(uint256 tokenId_) internal view returns (uint256[] memory) {
        uint256[] memory positionPrices = IPositionManager(positionManager).getPositionPrices(tokenId_);
        uint256[] memory exchangeRates = new uint256[](positionPrices.length);

        for (uint256 i = 0; i < positionPrices.length; ) {

            // RAY -> need to convert this to WAD terms
            exchangeRates[i] = IPool(deposits[tokenId_].ajnaPool).bucketExchangeRate(positionPrices[i]);

            unchecked {
                ++i;
            }
        }
        return exchangeRates;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getDepositInfo(uint256 tokenId_) external view returns (address, address, uint256, uint256[] memory) {
        Deposit storage deposit = deposits[tokenId_];
        return (deposit.owner, deposit.ajnaPool, deposit.depositBlock, deposit.exchangeRatesAtDeposit);
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
