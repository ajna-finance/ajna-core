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

    /// @dev bucket collateral: : NFT Token id => boolean (true if locked)
    mapping(uint256 => bool) private _bucketLockedNFTs;

    /// @dev pledged collateral: NFT Token id => borrower address
    mapping(uint256 => address) private _borrowerLockedNFTs;

    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    mapping(uint256 => bool) public tokenIdsAllowed;

    bool public isSubset;

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

            _borrowerLockedNFTs[tokenId] = borrower_;

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

        // move collateral from pool to claimer
        emit PullCollateralNFT(msg.sender, tokenIdsToPull_);
        _pullNFTs(msg.sender, tokenIdsToPull_);
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

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit DepositTake(borrower_, index_, amount_, 0, 0);
    }

    function take(
        address borrower_,
        uint256[] calldata tokenIds_,
        bytes memory swapCalldata_
    ) external override {

        uint256 numberOfNFTsWad = Maths.wad(tokenIds_.length);
        if (loans.borrowers[borrower_].collateral != numberOfNFTsWad) revert PartialTakeNotAllowed();

        _take(borrower_, numberOfNFTsWad);

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        _pullNFTs(msg.sender, tokenIds_);
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

    /**
     *  @notice Performs NFT transfering checks and transfers NFTs (by token Id) from pool to claimer.
     *  @param borrower_ Address of the borower whose NFTs are being transfered from.
     *  @param tokenIds_ Array of token ids to be pulled.
     */
    function _pullNFTs(
        address borrower_,
        uint256[] memory tokenIds_
    ) internal {
        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];
            if (_borrowerLockedNFTs[tokenId] != borrower_) revert TokenNotDeposited();

            delete _borrowerLockedNFTs[tokenId];

            _transferNFT(address(this), borrower_, tokenId);

            unchecked {
                ++i;
            }
        }
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
