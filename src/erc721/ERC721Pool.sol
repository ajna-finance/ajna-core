// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC721Pool.sol';
import '../base/Pool.sol';

contract ERC721Pool is IERC721Pool, Pool {
    using Buckets for mapping(uint256 => Buckets.Bucket);
    using Loans   for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed;  // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerTokenIds; // borrower address => array of tokenIds pledged by borrower
    mapping(uint256 => uint256[]) public bucketTokenIds;   // bucket id => array of tokenIds added in bucket

    bool public isSubset; // true if pool is a subset pool

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256[] memory tokenIds_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;

        uint256 noOfTokens = tokenIds_.length;
        if (noOfTokens > 0) {
            isSubset = true;
            // add subset of tokenIds allowed in the pool
            for (uint256 id = 0; id < noOfTokens;) {
                tokenIdsAllowed[tokenIds_[id]] = true;
                unchecked {
                    ++id;
                }
            }
        }

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
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

            borrowerTokenIds[borrower_].push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked {
                ++i;
            }
        }
    }

    function pullCollateral(
        uint256 noOfNFTsToPull_
    ) external override {
        _pullCollateral(Maths.wad(noOfNFTsToPull_));

        emit PullCollateral(msg.sender, noOfNFTsToPull_);

        uint256[] storage pledgedCollateral = borrowerTokenIds[msg.sender];
        uint256 noOfNFTsPledged = pledgedCollateral.length;
        for (uint256 i = 0; i < noOfNFTsToPull_;) {
            uint256 tokenId = pledgedCollateral[--noOfNFTsPledged];  // start with pulling the last token added in bucket
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

            bucketTokenIds[index_].push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked {
                ++i;
            }
        }
    }

    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(Maths.wad(noOfNFTsToRemove_), index_);

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_);

        // move collateral from pool to lender
        uint256[] storage addedNFTs = bucketTokenIds[index_];
        uint256 noOfNFTsInBucket = addedNFTs.length;
        for (uint256 i = 0; i < noOfNFTsToRemove_;) {
            uint256 tokenId = addedNFTs[--noOfNFTsInBucket]; // start with removing the last token added in bucket
            addedNFTs.pop();

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
            uint256 nftsTaken = (collateralTaken / 1e18) + 1; // round up collateral taken: (taken / 1e18) rounds down + 1 = rounds up TODO: fix this

            uint256[] storage pledgedNFTs = borrowerTokenIds[borrower_];
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
        //slither-disable-next-line divide-before-multiply
        collateral_ = (collateral_ / Maths.WAD) * Maths.WAD; // use collateral floor
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function _transferNFT(address from_, address to_, uint256 tokenId_) internal {
        //slither-disable-next-line calls-loop
        IERC721Token(_getArgAddress(0)).safeTransferFrom(from_, to_, tokenId_);
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
