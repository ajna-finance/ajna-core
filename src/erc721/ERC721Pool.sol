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
    using Queue     for Queue.Data;

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
        _pullCollateralOnBehalfOf(msg.sender, tokenIdsToPull_);
    }

    function _pullCollateralOnBehalfOf(
        address borrower_,
        uint256[] memory tokenIdsToPull_
    ) internal {
        _pullCollateral(borrower_, Maths.wad(tokenIdsToPull_.length));

        // move collateral from pool to sender
        emit PullCollateralNFT(borrower_, tokenIdsToPull_);
        for (uint256 i = 0; i < tokenIdsToPull_.length;) {
            uint256 tokenId = tokenIdsToPull_[i];
            //slither-disable-next-line calls-loop
            if (collateral().ownerOf(tokenId) != address(this)) revert TokenNotDeposited();
            if (!_poolCollateralTokenIds.get(tokenId))          revert RemoveTokenFailed(); // check if NFT token id in pool
            if (!lockedNFTs[borrower_].get(tokenId))           revert RemoveTokenFailed(); // check if caller is the one that locked NFT token id

            _poolCollateralTokenIds.unset(tokenId);
            lockedNFTs[borrower_].unset(tokenId);

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

    // // TODO: Add reentrancy guard
    function take(address borrower_, uint256[] memory tokenIds_, bytes memory swapCalldata_) external override {

        PoolState memory poolState = _getPoolState();
        Liquidation memory liquidation = liquidations[borrower_];
        
        // check liquidation process status
        (,,bool auctionActive) = auctions.get(borrower_);
        if (auctionActive != true) revert NoAuction();
        if (liquidation.kickTime == 0 || block.timestamp - uint256(liquidation.kickTime) <= 1 hours) revert TakeNotPastCooldown();

        (
        uint256 borrowerAccruedDebt,
        uint256 borrowerPledgedCollateral,
        uint256 borrowerMompFactor,
        uint256 borrowerInflatorSnapshot
        ) = borrowers.getBorrower(borrower_);

        (borrowerAccruedDebt, borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            borrower_,
            inflatorSnapshot
        );
        if (
            PoolUtils.collateralization(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                _lup(borrowerDebt)
            ) >= Maths.WAD
        ) revert LiquidateBorrowerOk();

        // Calculate BPF
        // TODO: remove auction from queue if auctionDebt == 0;
        uint256 price = PoolUtils.auctionPrice(liquidation.referencePrice, uint256(liquidation.kickTime));
        int256 bpf = PoolUtils._bpf(
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            borrowerMompFactor,
            borrowerInflatorSnapshot,
            liquidation.bondFactor,
            price);

        // Calculate amounts
        uint256 amount = Maths.wmul(price, tokenIds_.length);
        uint256 repayAmount = Maths.wmul(amount, uint256(1e18 - bpf));
        int256 rewardOrPenalty;

        if (repayAmount >= borrowerAccruedDebt) {
            repayAmount = borrowerAccruedDebt;
            amount = Maths.wdiv(borrowerAccruedDebt, uint256(1e18 - bpf));
        }

        if (bpf >= 0) {
            // Take is below neutralPrice, Kicker is rewarded
            rewardOrPenalty = int256(amount - repayAmount);
            liquidation.bondSize += amount - repayAmount;
 
        } else {     
            // Take is above neutralPrice, Kicker is penalized
            rewardOrPenalty = PRBMathSD59x18.mul(int256(amount), bpf);
            liquidation.bondSize -= uint256(-rewardOrPenalty);
        }


        poolState.accruedDebt -= repayAmount;
        borrowerAccruedDebt   -= repayAmount;

        // TODO: Reduce liquidation's remaining collateral HERE before collat check

        // If recollateralized remove loan from auction
        if (borrowerPledgedCollateral != 0 && PoolUtils.collateralization(borrowerAccruedDebt, borrowerPledgedCollateral, _lup(borrowerDebt)) >= Maths.WAD) {
            auctions.remove(borrower_);

            if (borrowerAccruedDebt > 0) {
                uint256 loansCount = loans.count - 1;
                if (loansCount != 0
                    &&
                    (borrowerAccruedDebt < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
                ) revert BorrowAmountLTMinDebt();

                uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                    borrowerAccruedDebt,
                    borrowerPledgedCollateral,
                    poolState.inflator
                );
                loans.upsert(borrower_, thresholdPrice);
            } 
        }

        uint256 numLoans   = (loans.count - 1) * 1e18;
        borrowerMompFactor = numLoans > 0 ? Maths.wdiv(_momp(numLoans), borrowerInflatorSnapshot): 0;

        borrowers.update(
            borrower_,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            borrowerMompFactor,
            borrowerInflatorSnapshot);

        liquidations[borrower_] = liquidation;

        // TODO: implement flashloan functionality
        // Flash loan full amount to liquidate to borrower
        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        //msg.sender.call(swapCalldata_);
        // Get current swap price
        //uint256 quoteTokenReturnAmount = _getQuoteTokenReturnAmount(uint256(liquidation.kickTime), uint256(liquidation.referencePrice), collateralToPurchase);

        emit Take(borrower_, amount, tokenIds_, rewardOrPenalty);
        _pullCollateralOnBehalfOf(borrower_, tokenIds_);
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
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
