// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Clone } from '@clones/Clone.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/structs/BitMaps.sol';

import './interfaces/IERC721Pool.sol';

import '../base/Pool.sol';

import '../libraries/Heap.sol';
import '../libraries/Maths.sol';
import '../libraries/Book.sol';
import '../libraries/Actors.sol';

contract ERC721Pool is IERC721Pool, Pool {
    using SafeERC20 for ERC20;
    using BitMaps   for BitMaps.BitMap;
    using Book      for mapping(uint256 => Book.Bucket);
    using Actors    for mapping(uint256 => mapping(address => Actors.Lender));
    using Actors    for mapping(address => Actors.Borrower);
    using Heap      for Heap.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Set of tokenIds that are currently being used as collateral in the pool
    BitMaps.BitMap private _poolCollateralTokenIds;

    /// @dev Set of NFT Token Ids that have been deposited into any bucket
    BitMaps.BitMap private _bucketCollateralTokenIds;

    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    BitMaps.BitMap private _tokenIdsAllowed;

    /// @dev pledged collateral: borrower address -> Set of NFT Token Ids pledged by the borrower
    mapping(address => BitMaps.BitMap) private lockedNFTs;

    mapping(address => NFTLiquidationInfo) private liquidations;

    bool public isSubset;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 rate_,
        address ajnaTokenAddress_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        quoteTokenScale = 10**(18 - quoteToken().decimals());

        ajnaTokenAddress           = ajnaTokenAddress_;
        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    function initializeSubset(
        uint256[] memory tokenIds_,
        uint256 rate_,
        address ajnaTokenAddress_
    ) external override {
        this.initialize(rate_, ajnaTokenAddress_);
        isSubset = true;

        // add subset of tokenIds allowed in the pool
        for (uint256 id = 0; id < tokenIds_.length;) {
            _tokenIdsAllowed.set(tokenIds_[id]);
            unchecked {
                ++id;
            }
        }
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function pledgeCollateral(
        address borrower_,
        uint256[] calldata tokenIdsToPledge_
    ) external override {
        _pledgeCollateral(borrower_, Maths.wad(tokenIdsToPledge_.length));

        // move collateral from sender to pool
        emit PledgeCollateralNFT(borrower_, tokenIdsToPledge_);
        bool subset = isSubset;
        for (uint256 i = 0; i < tokenIdsToPledge_.length;) {
            uint256 tokenId = tokenIdsToPledge_[i];
            if (subset && !_tokenIdsAllowed.get(tokenId)) revert OnlySubset();

            _poolCollateralTokenIds.set(tokenId);
            lockedNFTs[borrower_].set(tokenId);

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(msg.sender, address(this), tokenId); // move collateral from sender to pool

            unchecked {
                ++i;
            }
        }
    }

    // TODO: check for reentrancy
    // TODO: check for whole units of collateral
    function pullCollateral(
        uint256[] calldata tokenIdsToPull_
    ) external override {
        _pullCollateral(Maths.wad(tokenIdsToPull_.length));

        // move collateral from pool to sender
        emit PullCollateralNFT(msg.sender, tokenIdsToPull_);
        for (uint256 i = 0; i < tokenIdsToPull_.length;) {
            uint256 tokenId = tokenIdsToPull_[i];
            //slither-disable-next-line calls-loop
            if (collateral().ownerOf(tokenId) != address(this)) revert TokenNotDeposited();
            if (!_poolCollateralTokenIds.get(tokenId))          revert RemoveTokenFailed(); // check if NFT token id in pool
            if (!lockedNFTs[msg.sender].get(tokenId))           revert RemoveTokenFailed(); // check if caller is the one that locked NFT token id

            _poolCollateralTokenIds.unset(tokenId);
            lockedNFTs[msg.sender].unset(tokenId);

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(address(this), msg.sender, tokenId); // move collateral from pool to sender

            unchecked {
                ++i;
            }
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    // TODO: does pool state need to be updated with collateral deposited as well?
    function addCollateral(
        uint256[] calldata tokenIdsToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _addCollateral(Maths.wad(tokenIdsToAdd_.length), index_);

        // move required collateral from sender to pool
        emit AddCollateralNFT(msg.sender, index_, tokenIdsToAdd_);
        bool subset = isSubset;
        for (uint256 i = 0; i < tokenIdsToAdd_.length;) {
            uint256 tokenId = tokenIdsToAdd_[i];
            if (subset && !_tokenIdsAllowed.get(tokenId)) revert OnlySubset();

            _bucketCollateralTokenIds.set(tokenId);

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(msg.sender, address(this), tokenId); // move collateral from sender to pool

            unchecked {
                ++i;
            }
        }
    }

    // TODO: finish implementing
    // TODO: check for reentrancy
    function removeCollateral(
        uint256[] calldata tokenIdsToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(Maths.wad(tokenIdsToRemove_.length), index_);

        emit RemoveCollateralNFT(msg.sender, index_, tokenIdsToRemove_);
        // move collateral from pool to lender
        for (uint256 i = 0; i < tokenIdsToRemove_.length;) {
            uint256 tokenId = tokenIdsToRemove_[i];
            if (!_bucketCollateralTokenIds.get(tokenId)) revert TokenNotDeposited(); // check if NFT token deposited in buckets

            _bucketCollateralTokenIds.unset(tokenId);

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(address(this), msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function arbTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit ArbTake(borrower_, index_, amount_, 0, 0);
    }

    function clear(address borrower_, uint256 maxDepth_) external override {
        // TODO: implement
        uint256[] memory tokenIdsReturned = new uint256[](1);
        tokenIdsReturned[0] = 0;
        uint256 debtCleared = maxDepth_ * 10_000;
        emit ClearNFT(borrower_, _hpbIndex(), debtCleared, tokenIdsReturned, 0);
    }

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit DepositTake(borrower_, index_, amount_, 0, 0);
    }

    function kick(address borrower_) external override {
        PoolState memory poolState = _getPoolState();

        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            borrower_,
            poolState.inflator
        );
        if (borrowerAccruedDebt == 0) revert KickNoDebt();

        uint256 lup = _lup(poolState.accruedDebt);
        if (
            PoolUtils.collateralization(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                lup
            ) >= Maths.WAD
        ) revert LiquidateBorrowerOk();

        _updatePool(poolState, lup);

        // TODO: Implement similar to ERC20Pool, but this will have a different LiquidationInfo struct
        //  which includes an array of the borrower's tokenIds being auctioned off.
    }

    function take(address borrower_, uint256[] calldata tokenIds_, bytes memory swapCalldata_) external override {
        // TODO: Implement
        // copypasta to quell warnings
        msg.sender.call(swapCalldata_);
        emit Take(borrower_, 0, tokenIds_, 0);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function isTokenIdAllowed(uint256 tokenId_) external view override returns (bool) {
        return _tokenIdsAllowed.get(tokenId_);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /** @dev Collateral tokens are always non-fungible
     *  @dev Pure function used to facilitate accessing token via clone state
     */
    function collateral() public pure returns (ERC721) {
        return ERC721(_getArgAddress(0));
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
