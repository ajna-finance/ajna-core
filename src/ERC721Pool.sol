// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { console } from "@std/console.sol";

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 }        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { BitMaps }       from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { BasePool } from "./base/BasePool.sol";

import { INFTPool } from "./interfaces/IPool.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";


contract ERC721Pool is INFTPool, BasePool {

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

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    function initialize(uint256 rate_) external override {
        require(_poolInitializations == 0, "P:INITIALIZED");

        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**27;
        lastInflatorSnapshotUpdate = block.timestamp;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    function initializeSubset(uint256[] memory tokenIds_, uint256 rate_) external override {
        this.initialize(rate_);

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

    function addCollateral(uint256[] calldata tokenIds_) external override {

        (uint256 curDebt, ) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        _updateInterestRate(curDebt);

        // add tokenIds to the pool
        for (uint i; i < tokenIds_.length;) {
            require(_tokenIdsAllowed.contains(tokenIds_[i]), "P:ONLY_SUBSET");

            // pool level accounting
            _collateralTokenIdsAdded.add(tokenIds_[i]);
            totalCollateral += Maths.WAD;

            // borrower accounting
            NFTborrowers[msg.sender].collateralDeposited.add(tokenIds_[i]);

            // move collateral from sender to pool
            collateral().safeTransferFrom(msg.sender, address(this), tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
        emit AddNFTCollateral(msg.sender, tokenIds_);
    }

    function borrow(uint256 amount_, uint256 limitPrice_) external override {
        require(amount_ <= totalQuoteToken, "P:B:INSUF_LIQ");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:B:AMT_LT_AVG_DEBT");

        NFTBorrowerInfo storage borrower = NFTborrowers[msg.sender];
        _accumulateNFTBorrowerInterest(borrower, curInflator);

        // borrow amount from buckets with limit price and apply the origination fee
        uint256 fee = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
        _borrowFromBucket(amount_, fee, limitPrice_, curInflator);
        // collateral amounts need to be recorded as WADs to enable like-unit comparisons with quote token precision
        require(Maths.ray(borrower.collateralDeposited.length()) > _encumberedCollateral(borrower.debt + amount_ + fee), "P:B:INSUF_COLLAT");
        curDebt += amount_ + fee;
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:B:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalDebt       = curDebt;

        // borrower accounting
        if (borrower.debt == 0) totalBorrowers += 1;
        borrower.debt         += amount_ + fee;

        _updateInterestRate(curDebt);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function removeCollateral(uint256[] calldata tokenIds_) external override {

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        NFTBorrowerInfo storage borrower = NFTborrowers[msg.sender];
        _accumulateNFTBorrowerInterest(borrower, curInflator);

        uint256 unencumberedCollateral = Maths.ray(borrower.collateralDeposited.length()) - _encumberedCollateral(borrower.debt);

        // Require overcollateralization to be at a minimum of one RAY to account for indivisible NFTs
        require(
            Maths.ray(tokenIds_.length) <= unencumberedCollateral || unencumberedCollateral >= Maths.ray(tokenIds_.length) + Maths.RAY,
            "P:RC:AMT_GT_AVAIL_COLLAT"
        );

        _updateInterestRate(curDebt);

        // remove tokenIds from the pool
        for (uint i; i < tokenIds_.length;) {
            require(collateral().ownerOf(tokenIds_[i]) == address(this), "P:T_NOT_IN_P");

            // pool level accounting
            _collateralTokenIdsAdded.remove(tokenIds_[i]);
            totalCollateral -= Maths.WAD;

            // borrower accounting
            borrower.collateralDeposited.remove(tokenIds_[i]);

            // move collateral from pool to sender
            collateral().safeTransferFrom(address(this), msg.sender, tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
        emit RemoveNFTCollateral(msg.sender, tokenIds_);
    }


    // TODO: finish implementing
    function repay(uint256 amount_) external override {}

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function claimCollateral(address recipient_, uint256[] calldata tokenIds_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        uint256 maxClaim = lpBalance[recipient_][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        uint256 claimedLpTokens = _claimNFTCollateralFromBucket(price_, tokenIds_, maxClaim);

        // lender accounting
        lpBalance[recipient_][price_] -= claimedLpTokens;

        _updateInterestRate(totalDebt);

        // claim tokenIds from the pool
        for (uint i; i < tokenIds_.length;) {
            require(collateral().ownerOf(tokenIds_[i]) == address(this), "P:T_NOT_IN_P");

            // pool level accounting
            _collateralTokenIdsAdded.remove(tokenIds_[i]);
            totalCollateral -= Maths.WAD;

            // move claimed collateral from pool to claimer
            collateral().safeTransferFrom(address(this), recipient_, tokenIds_[i]);
            unchecked {
                ++i;
            }
        }
        emit ClaimNFTCollateral(recipient_, price_, tokenIds_, claimedLpTokens);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    // TODO: finish implementing
    function liquidate(address borrower_) external override {}

    function purchaseBid(uint256 amount_, uint256 price_, uint256[] calldata tokenIds_) external override {
        require(BucketMath.isValidPrice(price_), "P:PB:INVALID_PRICE");

        if (_tokenIdsAllowed.length() != 0) {
            for (uint i; i < tokenIds_.length;) {
                require(_tokenIdsAllowed.contains(tokenIds_[i]), "P:ONLY_SUBSET");
                unchecked {
                    ++i;
                }
            }
        }

        // calculate in whole NFTs the amount of collateral required to cover desired quote at desired price
        uint256 collateralRequired = Maths.divRoundingUp(amount_, price_);
        require(tokenIds_.length >= collateralRequired, "P:PB:INSUF_COLLAT");

        // slice incoming tokens to only use as many as are required
        uint256[] memory usedTokens = new uint256[](collateralRequired);
        usedTokens = tokenIds_[:collateralRequired];

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        _purchaseBidFromBucketNFTCollateral(price_, amount_, usedTokens, curInflator);
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:PB:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalCollateral += Maths.wad(usedTokens.length);

        _updateInterestRate(curDebt);

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

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */    
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
