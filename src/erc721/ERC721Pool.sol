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

import { console } from "@std/console.sol";


contract ERC721Pool is IERC721Pool, ScaledPool {
    using SafeERC20     for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Set of tokenIds that are currently being used as collateral
    EnumerableSet.UintSet internal _collateralTokenIdsAdded;

    /**
     *  @notice Mapping of price to Set of NFT Token Ids that have been deposited into the bucket
     *  @dev price [WAD] -> collateralDeposited
     */
    mapping(uint256 => EnumerableSet.UintSet) internal _collateralDeposited;

    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    EnumerableSet.UintSet internal _tokenIdsAllowed;

    /// @dev Internal visibility is required as it contains a nested struct
    // borrowers book: borrower address -> NFTBorrower
    mapping(address => NFTBorrower) internal borrowers;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        require(_poolInitializations == 0, "P:INITIALIZED");

        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
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

    function pledgeCollateral(uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external override {
        NFTBorrower storage borrower = borrowers[msg.sender];

        // add tokenIds to the pool
        for (uint i; i < tokenIds_.length;) {
            if (_tokenIdsAllowed.length() != 0) {
                require(_tokenIdsAllowed.contains(tokenIds_[i]), "P:ONLY_SUBSET");
            }

            // update pool state
            _collateralTokenIdsAdded.add(tokenIds_[i]);

            // update borrower accounting
            borrower.collateralDeposited.add(tokenIds_[i]);

            // move collateral from sender to pool
            collateral().safeTransferFrom(msg.sender, address(this), tokenIds_[i]);

            unchecked {
                ++i;
            }
        }

        // update pool state
        uint256 curDebt = _accruePoolInterest();
        _updateInterestRate(curDebt, _lup());
        pledgedCollateral += Maths.wad(tokenIds_.length);

        // accrue interest to borrower
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        emit PledgeCollateralNFT(msg.sender, tokenIds_);
    }

    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external override {
        uint256 lupId = _lupIndex(amount_);
        require(lupId <= limitIndex_, "S:B:LIMIT_REACHED"); // TODO: add check that limitIndex is <= MAX_INDEX

        // update pool interest
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        NFTBorrower storage borrower = borrowers[msg.sender];
        uint256 borrowersCount = totalBorrowers;
        if (borrowersCount != 0) require(borrower.debt + amount_ > _poolMinDebtAmount(curDebt), "S:B:AMT_LT_AVG_DEBT");

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        if (borrower.debt == 0) totalBorrowers = borrowersCount + 1;

        uint256 feeRate = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee) + Maths.WAD;
        uint256 debt    = Maths.wmul(amount_, feeRate);
        borrower.debt   += debt;

        // pool accounting
        uint256 newLup = _indexToPrice(lupId);
        require(_borrowerCollateralization(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), newLup) >= Maths.WAD, "S:B:BUNDER_COLLAT");

        require(
            _poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) >= Maths.WAD,
            "S:B:PUNDER_COLLAT"
        );
        curDebt += debt;

        borrowerDebt = curDebt;
        lenderDebt   += amount_;

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        _updateInterestRate(curDebt, newLup);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, newLup, amount_);
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
        require(Maths.wad(borrower.collateralDeposited.length()) - _encumberedCollateral(borrower.debt, curLup) >= Maths.wad(tokenIds_.length), "S:PC:NOT_ENOUGH_COLLATERAL");

        // update pool state
        pledgedCollateral -= Maths.wad(tokenIds_.length);
        _updateInterestRate(curDebt, curLup);

        // remove tokenIds and transfer to caller
        for (uint i; i < tokenIds_.length;) {
            require(collateral().ownerOf(tokenIds_[i]) == address(this), "P:T_NOT_IN_P");

            // pool level accounting
            _collateralTokenIdsAdded.remove(tokenIds_[i]);

            // borrower accounting
            borrower.collateralDeposited.remove(tokenIds_[i]);

            // move collateral from pool to sender
            collateral().safeTransferFrom(address(this), msg.sender, tokenIds_[i]);

            unchecked {
                ++i;
            }
        }

        // update loan queue
        uint256 thresholdPrice = _threshold_price(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
        if (borrower.debt != 0) _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);

        emit PullCollateralNFT(msg.sender, tokenIds_);
    }

    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_) external override {
        require(quoteToken().balanceOf(msg.sender) * quoteTokenScale >= maxAmount_, "S:R:INSUF_BAL");

        NFTBorrower storage borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "S:R:NO_DEBT");

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;

        // update lender accounting
        uint256 curLenderDebt = lenderDebt;
        curLenderDebt -= Maths.min(curLenderDebt, Maths.wmul(Maths.wdiv(curLenderDebt, curDebt), amount));

        curDebt       -= amount;

        // update loan queue
        uint256 borrowersCount = totalBorrowers;
        if (borrower.debt == 0) {
            totalBorrowers = borrowersCount - 1;
            _removeLoanQueue(msg.sender, oldPrev_);
        } else {
            if (borrowersCount != 0) require(borrower.debt > _poolMinDebtAmount(curDebt), "R:B:AMT_LT_AVG_DEBT");
            uint256 thresholdPrice = _threshold_price(borrower.debt, Maths.wad(borrower.collateralDeposited.length()), borrower.inflatorSnapshot);
            _updateLoanQueue(msg.sender, thresholdPrice, oldPrev_, newPrev_);
        }

        // update pool state
        if (curDebt != 0) {
            borrowerDebt = curDebt;
            lenderDebt   = curLenderDebt;
        } else {
            borrowerDebt = 0;
            lenderDebt   = 0;
        }

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move amount to repay from sender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, newLup, amount);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    // TODO: finish implementing
    function addCollateral(uint256[] calldata tokenIds_, uint256 index_) external override returns (uint256 lpbChange_) {}

    // TODO: finish implementing
    function removeCollateral(uint256[] calldata tokenIds_, uint256 index_) external override returns (uint256 lpAmount_) {}

    /**********************/
    /*** View Functions ***/
    /**********************/

    function borrowerInfo(address borrower_) external view override returns (uint256, uint256, uint256[] memory, uint256) {
        uint256 pending_debt = Maths.wmul(borrowers[borrower_].debt, Maths.wdiv(_pendingInflator(), inflatorSnapshot));

        return (
            borrowers[borrower_].debt,                         // accrued debt (WAD)
            pending_debt,                                       // current debt, accrued and pending accrual (WAD)
            borrowers[borrower_].collateralDeposited.values(), // deposited collateral including encumbered (WAD)
            borrowers[borrower_].inflatorSnapshot              // used to calculate pending interest (WAD)
        );
    }

    // TODO: finish implementing here and in ERC20 Pool following updates to lender external functions
    // function bucketAt() {}

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
