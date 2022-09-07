// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 }        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IERC721Pool } from "./interfaces/IERC721Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

import { Maths } from "../libraries/Maths.sol";

contract ERC721Pool is IERC721Pool, ScaledPool {
    using SafeERC20     for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Set of tokenIds that are currently being used as collateral in the pool
    EnumerableSet.UintSet private _poolCollateralTokenIds;

    /// @dev Set of NFT Token Ids that have been deposited into any bucket
    EnumerableSet.UintSet private _bucketCollateralTokenIds;

    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    EnumerableSet.UintSet private _tokenIdsAllowed;

    /// @dev Internal visibility is required as it contains a nested struct
    // borrowers book: borrower address -> NFTBorrower
    mapping(address => NFTBorrower) private borrowers;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        if (poolInitializations != 0) revert AlreadyInitialized();

        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    function initializeSubset(uint256[] memory tokenIds_, uint256 rate_) external override {
        this.initialize(rate_);

        // add subset of tokenIds allowed in the pool
        for (uint256 id = 0; id < tokenIds_.length;) {
            if (!_tokenIdsAllowed.add(tokenIds_[id])) revert AddTokenFailed();
            unchecked {
                ++id;
            }
        }
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function pledgeCollateral(address borrower_, uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external override {
        NFTBorrower storage borrower = borrowers[borrower_];

        // add tokenIds to the pool
        for (uint256 i = 0; i < tokenIds_.length;) {
            if (_tokenIdsAllowed.length() != 0) if(!_tokenIdsAllowed.contains(tokenIds_[i])) revert OnlySubset();

            if (!_poolCollateralTokenIds.add(tokenIds_[i]))      revert AddTokenFailed(); // update pool state
            if (!borrower.collateralDeposited.add(tokenIds_[i])) revert AddTokenFailed(); // update borrower accounting

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(msg.sender, address(this), tokenIds_[i]); // move collateral from sender to pool

            unchecked {
                ++i;
            }
        }

        // update pool state
        uint256 curDebt = _accruePoolInterest();
        _updateInterestRateAndEMAs(curDebt, _lup());
        pledgedCollateral += Maths.wad(tokenIds_.length);

        // accrue interest to borrower
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(borrower_, thresholdPrice, oldPrev_, newPrev_);

        emit PledgeCollateralNFT(borrower_, tokenIds_);
    }

    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external override {
        uint256 lupId = _lupIndex(amount_);
        if (lupId > limitIndex_) revert BorrowLimitIndexReached();

        // update pool interest
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        NFTBorrower storage borrower = borrowers[msg.sender];
        uint256 borrowersCount = totalBorrowers;
        if (borrowersCount != 0) if (borrower.debt + amount_ < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        if (borrower.debt == 0) totalBorrowers = borrowersCount + 1;

        uint256 debt  = Maths.wmul(amount_, _calculateFeeRate() + Maths.WAD);
        borrower.debt += debt;

        // pool accounting
        uint256 newLup = _indexToPrice(lupId);

        // check borrow won't push borrower or pool into a state of under-collateralization
        if (_borrowerCollateralization(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), newLup) < Maths.WAD) revert BorrowBorrowerUnderCollateralized();
        if (_poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) < Maths.WAD) revert BorrowPoolUnderCollateralized();

        curDebt += debt;

        borrowerDebt = curDebt;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amount_);
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
    }

    // TODO: check for reentrancy
    // TODO: check for whole units of collateral
    function pullCollateral(uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external override {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        NFTBorrower storage borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        // check collateralization for sufficient unenecumbered collateral
        uint256 curLup = _lup();
        if (Maths.wad(borrower.collateralDeposited.length()) - _encumberedCollateral(borrower.debt, curLup) < Maths.wad(tokenIds_.length)) revert RemoveCollateralInsufficientCollateral();

        // update pool state
        pledgedCollateral -= Maths.wad(tokenIds_.length);
        _updateInterestRateAndEMAs(curDebt, curLup);

        // remove tokenIds and transfer to caller
        for (uint256 i = 0; i < tokenIds_.length;) {
            //slither-disable-next-line calls-loop
            if (collateral().ownerOf(tokenIds_[i]) != address(this)) revert TokenNotDeposited();
            if (!_poolCollateralTokenIds.remove(tokenIds_[i]))       revert RemoveTokenFailed(); // pool level accounting
            if (!borrower.collateralDeposited.remove(tokenIds_[i]))  revert RemoveTokenFailed(); // borrower accounting

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(address(this), msg.sender, tokenIds_[i]); // move collateral from pool to sender

            unchecked {
                ++i;
            }
        }

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        emit PullCollateralNFT(msg.sender, tokenIds_);
    }

    function repay(address borrower_, uint256 maxAmount_, address oldPrev_, address newPrev_) external override {
        NFTBorrower storage borrower = borrowers[borrower_];
        if (borrower.debt == 0) revert RepayNoDebt();

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;
        curDebt       -= amount;

        // update loan queue
        uint256 borrowersCount = totalBorrowers;
        if (borrower.debt == 0) {
            totalBorrowers = borrowersCount - 1;
            _removeLoanQueue(borrower_, oldPrev_);
        } else {
            if (borrowersCount != 0) if (borrower.debt < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();

            uint256 thresholdPrice = _t0ThresholdPrice(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
            _updateLoanQueue(borrower_, thresholdPrice, oldPrev_, newPrev_);
        }

        // update pool state
        borrowerDebt = curDebt;
        uint256 newLup = _lup();
        _updateInterestRateAndEMAs(curDebt, newLup);

        // move amount to repay from sender to pool
        emit Repay(borrower_, newLup, amount);
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    // TODO: does pool state need to be updated with collateral deposited as well?
    function addCollateral(uint256[] calldata tokenIds_, uint256 index_) external override returns (uint256 lpbChange_) {
        _accruePoolInterest();

        Bucket memory bucket = buckets[index_];
        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        // Calculate exchange rate before new collateral has been accounted for.
        // This is consistent with how lbpChange in addQuoteToken is adjusted before calling _add.
        uint256 rate = _exchangeRate(_rangeSum(index_, index_), bucket.availableCollateral, bucket.lpAccumulator, index_);

        uint256 tokensToAdd        = Maths.wad(tokenIds_.length);
        uint256 quoteValue         = Maths.wmul(tokensToAdd, _indexToPrice(index_));
        lpbChange_                 = Maths.rdiv(Maths.wadToRay(quoteValue), rate);
        bucket.lpAccumulator       += lpbChange_;
        bucketLender.lpBalance     += lpbChange_;
        bucket.availableCollateral += tokensToAdd;

        buckets[index_] = bucket;
        bucketLenders[index_][msg.sender] = bucketLender;

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        // move required collateral from sender to pool
        for (uint256 i = 0; i < tokenIds_.length;) {
            if (_tokenIdsAllowed.length() != 0) if(!_tokenIdsAllowed.contains(tokenIds_[i])) revert OnlySubset();

            if (!_bucketCollateralTokenIds.add(tokenIds_[i])) revert AddTokenFailed();

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(msg.sender, address(this), tokenIds_[i]); // move collateral from sender to pool

            unchecked {
                ++i;
            }
        }

        emit AddCollateralNFT(msg.sender, index_, tokenIds_);
    }

    // TODO: finish implementing
    // TODO: check for reentrancy
    function removeCollateral(uint256[] calldata tokenIds_, uint256 index_) external override returns (uint256 lpAmount_) {
        Bucket memory bucket = buckets[index_];
        if (Maths.wad(tokenIds_.length) > bucket.availableCollateral) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        uint256 price        = _indexToPrice(index_);
        uint256 rate         = _exchangeRate(_rangeSum(index_, index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        uint256 availableLPs = bucketLender.lpBalance;

        // ensure user can actually remove that much
        lpAmount_ = Maths.rdiv((Maths.wad(tokenIds_.length) * price / 1e9), rate);
        uint256 nftsAvailableForClaiming = Maths.rwdivw(Maths.rmul(lpAmount_, rate), price);

        if (availableLPs == 0 || lpAmount_ > availableLPs || Maths.wad(tokenIds_.length) < nftsAvailableForClaiming) {
            revert RemoveCollateralInsufficientLP();
        }

        // update bucket accounting
        bucket.availableCollateral -= Maths.wad(tokenIds_.length);
        bucket.lpAccumulator       -= Maths.min(bucket.lpAccumulator, lpAmount_);
        buckets[index_] = bucket;

        // update lender accounting
        bucketLender.lpBalance -= lpAmount_;
        bucketLenders[index_][msg.sender] = bucketLender;

        _updateInterestRateAndEMAs(borrowerDebt, _lup());

        emit RemoveCollateralNFT(msg.sender, price, tokenIds_);

        // move collateral from pool to lender
        for (uint256 i = 0; i < tokenIds_.length;) {
            if (!_bucketCollateralTokenIds.contains(tokenIds_[i])) revert TokenNotDeposited();

            //slither-disable-next-line calls-loop
            collateral().safeTransferFrom(address(this), msg.sender, tokenIds_[i]);

            unchecked {
                ++i;
            }
        }
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function liquidate(address borrower_) external override {
        (uint256 curDebt) = _accruePoolInterest();

        NFTBorrower storage borrower = borrowers[borrower_];
        if (borrower.debt == 0) revert LiquidateNoDebt();

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 lup = _lup();
        _updateInterestRateAndEMAs(curDebt, lup);

        if (_borrowerCollateralization(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), lup) >= Maths.WAD) revert LiquidateBorrowerOk();

        // TODO: Implement similar to ERC20Pool, but this will have a different LiquidationInfo struct
        //  which includes an array of the borrower's tokenIds.
    }

    function take(address borrower_, uint256 amount_, bytes memory swapCalldata_, address oldPrev_, address newPrev_) external override {
        // TODO: Implement
    }

    function depositTake(address borrower_, uint256 amount_, uint256 index_) external override {
        // TODO: implement
    }

    function arbTake(address borrower_, uint256 amount_) external override {
        // TODO: implement
    }

    function clear(address borrower_, uint256 amount_) external override {
        // TODO: implement
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function borrowerInfo(address borrower_) external view override returns (uint256, uint256, uint256[] memory, uint256) {
        uint256 pendingDebt = Maths.wmul(borrowers[borrower_].debt, Maths.wdiv(_pendingInflator(), inflatorSnapshot));

        return (
            borrowers[borrower_].debt,                         // accrued debt (WAD)
            pendingDebt,                                       // current debt, accrued and pending accrual (WAD)
            borrowers[borrower_].collateralDeposited.values(), // deposited collateral including encumbered (WAD)
            borrowers[borrower_].inflatorSnapshot              // used to calculate pending interest (WAD)
        );
    }


    function isTokenIdAllowed(uint256 tokenId_) external view override returns (bool) {
        return _tokenIdsAllowed.contains(tokenId_);
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
