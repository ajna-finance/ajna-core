// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC721Pool.sol';
import '../base/Pool.sol';

contract ERC721Pool is IERC721Pool, Pool {
    using Auctions for Auctions.Data;
    using Loans    for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed;  // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerTokenIds; // borrower address => array of tokenIds pledged by borrower
    uint256[]                     public bucketTokenIds;   // array of tokenIds added in pool buckets

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
        _transferFromSenderToPool(borrowerTokenIds[borrower_], tokenIdsToPledge_);
    }

    function pullCollateral(
        uint256 noOfNFTsToPull_
    ) external override {
        _pullCollateral(Maths.wad(noOfNFTsToPull_));

        emit PullCollateral(msg.sender, noOfNFTsToPull_);
        _transferFromPoolToSender(borrowerTokenIds[msg.sender], noOfNFTsToPull_);
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
        _transferFromSenderToPool(bucketTokenIds, tokenIdsToAdd_);
    }

    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(Maths.wad(noOfNFTsToRemove_), index_);

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_);
        _transferFromPoolToSender(bucketTokenIds, noOfNFTsToRemove_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function arbTake(
        address borrowerAddress_,
        uint256 index_
    ) external override {
        // TODO: implement
        emit ArbTake(borrowerAddress_, index_, 0, 0, 0, true);
    }

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
        emit DepositTake(borrower_, index_, amount_, 0, 0);
    }

    function take(
        address borrowerAddress_,
        uint256 collateral_,
        bytes memory swapCalldata_
    ) external override {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0

        (
            uint256 quoteTokenAmount,
            uint256 t0repaidDebt,
            uint256 takeCollateral,
            uint256 auctionPrice,
            uint256 bondChange,
            bool isRewarded
        ) = auctions.take(borrowerAddress_, borrower, Maths.wad(collateral_), poolState.inflator);

        uint256 excessQuoteToken;
        uint256 collateralTaken = (takeCollateral / 1e18) * 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2
        if (collateralTaken !=  takeCollateral) { // collateral taken not a round number
            collateralTaken += 1e18; // round up collateral to take
            // taker should send additional quote tokens to cover difference between collateral needed to be taken and rounded collateral, at auction price
            // borrower will get quote tokens for the difference between rounded collateral and collateral taken to cover debt
            excessQuoteToken = Maths.wmul(collateralTaken - takeCollateral, auctionPrice);
        }

        borrower.collateral  -= collateralTaken;
        poolState.collateral -= collateralTaken;

        _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);

        emit Take(borrowerAddress_, quoteTokenAmount, takeCollateral, bondChange, isRewarded);

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);

        // transfer from taker to pool the amount of quote tokens needed to cover collateral auctioned (including excess for rounded collateral)
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmount + excessQuoteToken);

        // transfer from pool to borrower the excess of quote tokens after rounding collateral auctioned
        if (excessQuoteToken != 0) _transferQuoteToken(borrowerAddress_, excessQuoteToken);

        // transfer rounded collateral from pool to taker
        _transferFromPoolToSender(borrowerTokenIds[borrowerAddress_], collateralTaken / 1e18);
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
     *  @notice Helper function for transferring multiple NFT tokens from msg.sender to pool.
     *  @notice Reverts in case token id is not supported by subset pool.
     *  @param  poolTokens_ Array in pool that tracks NFT ids (could be tracking NFTs pledged by borrower or NFTs added by a lender in a specific bucket).
     *  @param  tokenIds_   Array of NFT token ids to transfer from msg.sender to pool.
     */
    function _transferFromSenderToPool(
        uint256[] storage poolTokens_,
        uint256[] calldata tokenIds_
    ) internal {
        bool subset = isSubset;
        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();
            poolTokens_.push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /**
     *  @notice Helper function for transferring multiple NFT tokens from pool to msg.sender.
     *  @notice It transfers NFTs from the most recent one added into the pool (pop from array tracking NFTs in pool).
     *  @param  poolTokens_     Array in pool that tracks NFT ids (could be tracking NFTs pledged by borrower or NFTs added by a lender in a specific bucket).
     *  @param  amountToRemove_ Number of NFT tokens to transfer from pool to msg.sender.
     */
    function _transferFromPoolToSender(
        uint256[] storage poolTokens_,
        uint256 amountToRemove_
    ) internal {
        uint256 noOfNFTsInPool = poolTokens_.length;
        for (uint256 i = 0; i < amountToRemove_;) {
            uint256 tokenId = poolTokens_[--noOfNFTsInPool]; // start with transferring the last token added in bucket
            poolTokens_.pop();

            _transferNFT(address(this), msg.sender, tokenId);

            unchecked {
                ++i;
            }
        }
    }

    /**
     *  @dev Helper function to transfer an NFT from owner to target address (reused in code to reduce contract deployment bytecode size).
     *  @param from_    NFT owner address.
     *  @param to_      New NFT owner address.
     *  @param tokenId_ NFT token id to be transferred.
     */
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
