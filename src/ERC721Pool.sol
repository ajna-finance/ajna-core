// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { console } from "@std/console.sol";

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 }        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { BitMaps }       from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { BorrowerManager } from "./base/BorrowerManager.sol";
import { LenderManager }   from "./base/LenderManager.sol";

import { INFTPool } from "./interfaces/IPool.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";


contract ERC721Pool is INFTPool, BorrowerManager, Clone, LenderManager {

    using SafeERC20 for ERC20;

    using EnumerableSet for EnumerableSet.UintSet;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Set of tokenIds that are currently being used as collateral
    EnumerableSet.UintSet internal _collateralTokenIdsAdded;
    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    EnumerableSet.UintSet internal _tokenIdsAllowed;

    /// @dev Counter used by onlyOnce modifier
    uint256 private _poolInitializations = 0;

    uint256 public override quoteTokenScale;

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    function initialize() external override {
        _onlyOnce();
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    function initializeSubset(uint256[] memory tokenIds_) external override {
        _onlyOnce();
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;

        // add subset of tokenIds allowed in the pool
        for (uint256 id; id < tokenIds_.length;) {
            _tokenIdsAllowed.add(tokenIds_[id]);
            unchecked {
                ++id;
            }
        }
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 tokenId_) public override {
        // check if collateral is valid
        _onlySubset(tokenId_);

        // pool level accounting
        _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        _collateralTokenIdsAdded.add(tokenId_);
        totalCollateral = Maths.wad(_collateralTokenIdsAdded.length());

        // borrower accounting
        NFTborrowers[msg.sender].collateralDeposited.add(tokenId_);

        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), tokenId_);
        emit AddNFTCollateral(msg.sender, tokenId_);
    }

    function addCollateralMultiple(uint256[] calldata tokenIds_) external override {
        // check if all incoming tokenIds are part of the pool subset
        _onlySubsetMultiple(tokenIds_);

        _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // add tokenIds to the pool
        for (uint i; i < tokenIds_.length;) {

            // pool level accounting
            _collateralTokenIdsAdded.add(tokenIds_[i]);
            totalCollateral += Maths.ONE_WAD;

            // borrower accounting
            NFTborrowers[msg.sender].collateralDeposited.add(tokenIds_[i]);

            // move collateral from sender to pool
            collateral().safeTransferFrom(msg.sender, address(this), tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
        emit AddNFTCollateralMultiple(msg.sender, tokenIds_);
    }

    function borrow(uint256 amount_, uint256 limitPrice_) external override {
        require(amount_ <= totalQuoteToken, "P:B:INSUF_LIQ");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:B:AMT_LT_AVG_DEBT");

        NFTBorrowerInfo storage borrower = NFTborrowers[msg.sender];
        _accumulateNFTBorrowerInterest(borrower, curInflator);

        // borrow amount from buckets with limit price and apply the origination fee
        uint256 fee = Maths.max(Maths.wdiv(previousRate, WAD_WEEKS_PER_YEAR), minFee);
        _borrowFromBucket(amount_, fee, limitPrice_, curInflator);
        // collateral amounts need to be recorded as WADs to enable like-unit comparisons with quote token precision
        require(Maths.ray(borrower.collateralDeposited.length()) > _encumberedCollateral(borrower.debt + amount_ + fee), "P:B:INSUF_COLLAT");
        curDebt += amount_ + fee;
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:B:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalDebt       = curDebt;

        // borrower accounting
        if (borrower.debt == 0) totalBorrowers += 1;
        borrower.debt         += amount_ + fee;

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function removeCollateral(uint256 tokenId_) external override {
        _tokenInPool(tokenId_);

        ( , uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        NFTBorrowerInfo storage borrower = NFTborrowers[msg.sender];
        _accumulateNFTBorrowerInterest(borrower, curInflator);

        // Require overcollateralization to be at a minimum of one RAY to account for indivisible NFTs
        require(Maths.ray(borrower.collateralDeposited.length()) - _encumberedCollateral(borrower.debt) >= Maths.ONE_RAY, "P:RC:AMT_GT_AVAIL_COLLAT");

        // pool level accounting
        _collateralTokenIdsAdded.remove(tokenId_);
        totalCollateral = Maths.wad(_collateralTokenIdsAdded.length());

        // borrower accounting
        borrower.collateralDeposited.remove(tokenId_);

        // move collateral from pool to sender
        collateral().safeTransferFrom(address(this), msg.sender, tokenId_);
        emit RemoveNFTCollateral(msg.sender, tokenId_);
    }

    function removeCollateralMultiple(uint256[] calldata tokenIds_) external override {
        _tokensInPool(tokenIds_);

        ( , uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        NFTBorrowerInfo storage borrower = NFTborrowers[msg.sender];
        _accumulateNFTBorrowerInterest(borrower, curInflator);

        uint256 unencumberedCollateral = Maths.ray(borrower.collateralDeposited.length()) - _encumberedCollateral(borrower.debt);

        // Require overcollateralization to be at a minimum of one RAY to account for indivisible NFTs
        require(
            Maths.ray(tokenIds_.length) <= unencumberedCollateral || unencumberedCollateral >= Maths.ray(tokenIds_.length) + Maths.ONE_RAY,
            "P:RC:AMT_GT_AVAIL_COLLAT"
        );

        // remove tokenIds from the pool
        for (uint i; i < tokenIds_.length;) {

            // pool level accounting
            _collateralTokenIdsAdded.remove(tokenIds_[i]);
            totalCollateral -= Maths.ONE_WAD;

            // borrower accounting
            borrower.collateralDeposited.remove(tokenIds_[i]);

            // move collateral from pool to sender
            collateral().safeTransferFrom(address(this), msg.sender, tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
        emit RemoveNFTCollateralMultiple(msg.sender, tokenIds_);
    }


    // TODO: finish implementing
    function repay(uint256 amount_) external override {}

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        address recipient_, uint256 amount_, uint256 price_
    ) external override returns (uint256 lpTokens_) {
        require(BucketMath.isValidPrice(price_), "P:AQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:AQT:AMT_LT_AVG_DEBT");

        // deposit quote token amount and get awarded LP tokens
        lpTokens_ = _addQuoteTokenToBucket(price_, amount_, curDebt, curInflator);

        // pool level accounting
        totalQuoteToken += amount_;

        // lender accounting
        lpBalance[recipient_][price_] += lpTokens_;
        lpTimer[recipient_][price_]   = block.timestamp;

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(recipient_, price_, amount_, lup);
    }

    function claimCollateral(address recipient_, uint256 tokenId_, uint256 price_) external override {
        _tokenInPool(tokenId_);
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        uint256 maxClaim = lpBalance[recipient_][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        uint256 claimedLpTokens = _claimNFTCollateralFromBucket(price_, tokenId_, maxClaim);

        // pool level accounting
        _collateralTokenIdsAdded.remove(tokenId_);
        totalCollateral -= Maths.ONE_WAD;

        // lender accounting
        lpBalance[recipient_][price_] -= claimedLpTokens;

        // move claimed collateral from pool to claimer
        collateral().safeTransferFrom(address(this), recipient_, tokenId_);
        emit ClaimNFTCollateral(recipient_, price_, tokenId_, claimedLpTokens);
    }

    function claimCollateralMultiple(address recipient_, uint256[] calldata tokenIds_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        _tokensInPool(tokenIds_);

        uint256 maxClaim = lpBalance[recipient_][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        uint256 claimedLpTokens = _claimMultipleNFTCollateralFromBucket(price_, tokenIds_, maxClaim);

        // lender accounting
        lpBalance[recipient_][price_] -= claimedLpTokens;

        // claim tokenIds from the pool
        for (uint i; i < tokenIds_.length;) {
            // pool level accounting
            _collateralTokenIdsAdded.remove(tokenIds_[i]);
            totalCollateral -= Maths.ONE_WAD;

            // move claimed collateral from pool to claimer
            collateral().safeTransferFrom(address(this), recipient_, tokenIds_[i]);
            unchecked {
                ++i;
            }
        }
        emit ClaimNFTCollateralMultiple(recipient_, price_, tokenIds_, claimedLpTokens);
    }

    function moveQuoteToken(
        address recipient_, uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_
    ) external override {
        require(BucketMath.isValidPrice(toPrice_), "P:MQT:INVALID_TO_PRICE");
        require(fromPrice_ != toPrice_, "P:MQT:SAME_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        (uint256 fromLpTokens, uint256 toLpTokens, uint256 movedAmount) = _moveQuoteTokenFromBucket(
            fromPrice_, toPrice_, maxAmount_, lpBalance[recipient_][fromPrice_], lpTimer[recipient_][fromPrice_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:MQT:POOL_UNDER_COLLAT");

        // lender accounting
        lpBalance[recipient_][fromPrice_] -= fromLpTokens;
        lpBalance[recipient_][toPrice_]   += toLpTokens;

        emit MoveQuoteToken(recipient_, fromPrice_, toPrice_, movedAmount, lup);
    }

    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // remove quote token amount and get LP tokens burned
        (uint256 amount, uint256 lpTokens) = _removeQuoteTokenFromBucket(
            price_, maxAmount_, lpBalance[recipient_][price_], lpTimer[recipient_][price_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:RQT:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount;

        // lender accounting
        lpBalance[recipient_][price_] -= lpTokens;

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    // TODO: finish implementing
    function liquidate(address borrower_) external override {}

    function purchaseBidNFTCollateral(uint256 amount_, uint256 price_, uint256[] calldata tokenIds_) external override {
        require(BucketMath.isValidPrice(price_), "P:PB:INVALID_PRICE");

        _onlySubsetMultiple(tokenIds_);

        // calculate in whole NFTs the amount of collateral required to cover desired quote at desired price
        uint256 collateralRequired = Maths.divRoundingUp(amount_, price_);
        require(tokenIds_.length >= collateralRequired, "P:PB:INSUF_COLLAT");

        // slice incoming tokens to only use as many as are required
        uint256[] memory usedTokens = new uint256[](collateralRequired);
        usedTokens = tokenIds_[:collateralRequired];

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        _purchaseBidFromBucketNFTCollateral(price_, amount_, usedTokens, curInflator);
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:PB:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalCollateral += Maths.wad(usedTokens.length);

        // move required collateral from sender to pool
        for (uint i; i < collateralRequired;) {
            collateral().safeTransferFrom(msg.sender, address(this), usedTokens[i]);
            unchecked {
                ++i;
            }
        }

        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit PurchaseWithNFTs(msg.sender, price_, amount_, usedTokens);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /** @notice Used to protect a clone's initialize method from repeated updates */
    function _onlyOnce() internal view {
        require(_poolInitializations == 0, "P:INITIALIZED");
    }

    function _onlySubset(uint256 tokenId_) internal view {
        if (_tokenIdsAllowed.length() != 0) {
            require(_tokenIdsAllowed.contains(tokenId_), "P:ONLY_SUBSET");
        }
    }

    function _onlySubsetMultiple(uint256[] memory tokenIds_) internal view {
        if (_tokenIdsAllowed.length() != 0) {
            for (uint i; i < tokenIds_.length;) {
                require(_tokenIdsAllowed.contains(tokenIds_[i]), "P:ONLY_SUBSET");
                unchecked {
                    ++i;
                }
            }
        }
    }

    /** @notice Check if a token has been deposited into the pool */
    function _tokenInPool(uint256 tokenId_) internal view {
        require(collateral().ownerOf(tokenId_) == address(this), "P:T_NOT_IN_P");
    }

    /** @notice Check if all tokens in an array have been deposited into the pool */
    function _tokensInPool(uint256[] memory tokenIds_) internal view {
        for (uint i; i < tokenIds_.length;) {
            _tokenInPool(tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getCollateralDeposited() public view returns(uint256[] memory) {
        return _collateralTokenIdsAdded.values();
    }

    // WARNING: This is an extremely gas intensive operation and should only be done in view accessors
    function getTokenIdsAllowed() public view returns(uint256[] memory) {
        return _tokenIdsAllowed.values();
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

    /** @dev Quote tokens are always fungible
     *  @dev Pure function used to facilitate accessing token via clone state
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */    
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
