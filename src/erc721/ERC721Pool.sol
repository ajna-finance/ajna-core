// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Clone } from '@clones/Clone.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import './interfaces/IERC721Pool.sol';

import '../base/Pool.sol';

contract ERC721Pool is IERC721Pool, Pool {
    using SafeERC20 for ERC20;
    using Buckets   for mapping(uint256 => Buckets.Bucket);
    using Loans     for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed; // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerNFTIds;  // borrower address => array of tokenIds pledged by borrower 

    mapping(uint256 => bool)    private _bucketLockedNFTs;   // NFT Token id => boolean (true if locked)

    bool public isSubset; // true if collection is a subset

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 rate_,
        address ajnaTokenAddress_
    ) external override {
        if (poolInitializations != 0)         revert AlreadyInitialized();
        if (ajnaTokenAddress_ == address(0))  revert Token0xAddress();

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
        isSubset = true;

        // add subset of tokenIds allowed in the pool
        for (uint256 id = 0; id < tokenIds_.length;) {
            tokenIdsAllowed[tokenIds_[id]] = true;
            unchecked {
                ++id;
            }
        }

        this.initialize(rate_, ajnaTokenAddress_);
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
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();

            borrowerNFTIds[borrower_].push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

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

        emit PullCollateralNFT(msg.sender, tokenIdsToPull_);

        // move collateral from pool to claimer
        uint256[] storage pledgedCollateral = borrowerNFTIds[msg.sender];
        uint256 noOfNFTsPledged = pledgedCollateral.length;
        for (uint256 i = 0; i < tokenIdsToPull_.length;) {
            uint256 tokenId = tokenIdsToPull_[i];

            if (pledgedCollateral[--noOfNFTsPledged] != tokenId) revert TokenMismatch();

            pledgedCollateral.pop();

            _transferNFT(address(this), msg.sender, tokenId);

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
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();

            _bucketLockedNFTs[tokenId] = true;

            _transferNFT(msg.sender, address(this), tokenId);

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
            if (!_bucketLockedNFTs[tokenId]) revert TokenNotDeposited(); // check if NFT token deposited in buckets by caller

            _bucketLockedNFTs[tokenId] = false;

            _transferNFT(address(this), msg.sender, tokenId);

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

    function take(
        address borrower_,
        uint256 maxTokens_,
        bytes memory swapCalldata_
    ) external override {

        uint256 collateralTaken = _take(borrower_, Maths.wad(maxTokens_));
        if (collateralTaken != 0) {
            uint256 nftsTaken = (collateralTaken / 1e18) + 1; // round up collateral taken: (taken / 1e18) rounds down + 1 = rounds up

            uint256[] storage pledgedNFTs = borrowerNFTIds[borrower_];
            uint256 noOfNFTsPledged = pledgedNFTs.length;

            if (noOfNFTsPledged < nftsTaken) nftsTaken = noOfNFTsPledged;

            // TODO: implement flashloan functionality
            // Flash loan full amount to liquidate to borrower
            // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
            //msg.sender.call(swapCalldata_);

            for (uint256 i = 0; i < nftsTaken;) {
                uint256 tokenId = pledgedNFTs[--noOfNFTsPledged]; // start with taking the last token pledged by borrower

                pledgedNFTs.pop();

                _transferNFT(address(this), msg.sender, tokenId);

                unchecked {
                    ++i;
                }
            }
        }
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Overrides default implementation and use floor(amount of collateral) to calculate collateralization.
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return Collateralization value.
     */
    function _collateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure override returns (uint256) {
        uint256 encumbered = price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
        collateral_ = (collateral_ / Maths.WAD) * Maths.WAD;
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function _transferNFT(address from_, address to_, uint256 tokenId_) internal {
        //slither-disable-next-line calls-loop
        collateral().safeTransferFrom(from_, to_, tokenId_);
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
