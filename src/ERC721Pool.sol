// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { Clone } from "@clones/Clone.sol";

import { console } from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 }    from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { BitMaps }   from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet }   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { Buckets }       from "./base/Buckets.sol";
import { Interest }      from "./base/Interest.sol";
import { LenderManager } from "./base/LenderManager.sol";

import { IPool } from "./interfaces/IPool.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";


contract ERC721Pool is IPool, Buckets, Clone, Interest, LenderManager {

    using SafeERC20 for ERC20;

    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev Counter used by onlyOnce modifier
    uint8 private _poolInitializations = 0;

    /// @dev Set of tokenIds that are currently being used as collateral
    EnumerableSet.UintSet internal _collateralTokenIdsAdded;
    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    EnumerableSet.UintSet internal _tokenIdsAllowed;

    uint256 public override quoteTokenScale;

    uint256 public override previousRateUpdate;
    uint256 public override totalCollateral;    // [WAD]
    uint256 public override totalQuoteToken;    // [WAD]

    // TODO: rename
    // borrowers book: borrower address -> NFTBorrowerInfo
    mapping(address => NFTBorrowerInfo) public NFTborrowers;

    /// @notice Modifier to protect a clone's initialize method from repeated updates
    modifier onlyOnce() {
        require(_poolInitializations == 0, "P:INITIALIZED");
        _;
    }

    // TODO: convert to modifier and add check at start of each method
    function onlySubset(uint256 tokenId_) internal {
        if (_tokenIdsAllowed.length() != 0) {

            bool isAllowed = _tokenIdsAllowed.contains(tokenId_);

            if (isAllowed == false) {
                revert("P:ONLY_SUBSET");
            }
        }
    }

    function initialize() external onlyOnce {
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /**
     * @notice Called by deployNFTSubsetPool()
     * @dev Used to initialize pools that only support a subset of tokenIds
     */
    function initializeSubset(uint256[] memory tokenIds_) external onlyOnce {
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

    /// @dev Quote tokens are always non-fungible
    /// @dev Pure function used to facilitate accessing token via clone state
    function collateral() public pure returns (ERC721) {
        return ERC721(_getArgAddress(0));
    }

    /// @dev Quote tokens are always fungible
    /// @dev Pure function used to facilitate accessing token via clone state
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    function addQuoteToken(
        address recipient_, uint256 amount_, uint256 price_
    ) external override returns (uint256 lpTokens_) {
        require(BucketMath.isValidPrice(price_), "P:AQT:INVALID_PRICE");

        accumulatePoolInterest();

        // deposit quote token amount and get awarded LP tokens
        lpTokens_ = addQuoteTokenToBucket(price_, amount_, totalDebt, inflatorSnapshot);

        // pool level accounting
        totalQuoteToken               += amount_;

        // lender accounting
        lpBalance[recipient_][price_] += lpTokens_;

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(recipient_, price_, amount_, lup);
    }

    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        accumulatePoolInterest();

        // remove quote token amount and get LP tokens burned
        (uint256 amount, uint256 lpTokens) = removeQuoteTokenFromBucket(
            price_, maxAmount_, lpBalance[recipient_][price_], inflatorSnapshot
        );

        // pool level accounting
        totalQuoteToken -= amount;

        require(getPoolCollateralization() >= Maths.ONE_WAD, "P:RQT:POOL_UNDER_COLLAT");

        // lender accounting
        lpBalance[recipient_][price_] -= lpTokens;

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    function addCollateral(uint256 tokenId_) external  override {
        // check if collateral is valid
        onlySubset(tokenId_);

        accumulatePoolInterest();

        // pool level accounting
        _collateralTokenIdsAdded.add(tokenId_);
        totalCollateral = _collateralTokenIdsAdded.length();

        // borrower accounting
        NFTborrowers[msg.sender].collateralDeposited.push(tokenId_);

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), tokenId_);
        emit AddCollateral(msg.sender, tokenId_);
    }

    // TODO: finish implementing
    // TODO: move check to onlySubsetMultiple()
    // TODO: update to incrementally add if contains, otherwise skip?
    function addCollateralMultiple(uint256[] memory tokenIds_) external {
        for (uint i; i < tokenIds_.length;) {
            onlySubset(tokenIds_[i]);
            unchecked {
                ++i;
            }
        }
        // TODO: finish implementing
    }

    // TODO: finish implementing
    // TODO: add support for find and remove -> require struct?
    function removeCollateral(uint256 tokenId_) external {
        accumulatePoolInterest();

        NFTBorrowerInfo memory borrower = NFTborrowers[msg.sender];
        // accumulateBorrowerInterest(borrower);

        uint256 encumberedBorrowerCollateral = Maths.rayToWad(getEncumberedCollateral(borrower.debt));
        // require(borrower.collateralDeposited - encumberedBorrowerCollateral >= amount_, "P:RC:AMT_GT_AVAIL_COLLAT");

        // // pool level accounting
        // totalCollateral              -= 1;

        // // borrower accounting
        // borrower.collateralDeposited -= amount_;
        _collateralTokenIdsAdded.remove(tokenId_);

        // // move collateral from pool to sender
        // collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        // emit RemoveCollateral(msg.sender, amount_);
    }

    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external {}

    function borrow(uint256 amount_, uint256 stopPrice_) external {}

    function repay(uint256 amount_) external {}

    function purchaseBid(uint256 amount_, uint256 price_) external {}

    function liquidate(address borrower_) external {}

    /*****************************/
    /*** Pool State Management ***/
    /*****************************/

    // WARNING: This is an extremely gas intensive operation and should only be done in view accessors
    function getCollateralDeposited() public view returns(uint256[] memory) {
        return _collateralTokenIdsAdded.values();
    }

    // WARNING: This is an extremely gas intensive operation and should only be done in view accessors
    function getTokenIdsAllowed() public view returns(uint256[] memory) {
        return _tokenIdsAllowed.values();
    }

    // TODO: Add a test for this
    function getMinimumPoolPrice() public view override returns (uint256 minPrice_) {
        minPrice_ = totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256 encumbrance_) {
        // Calculate encumbrance as RAY to maintain precision
        encumbrance_ = debt_ != 0 ? Maths.wdiv(debt_, lup) : 0;
    }

    function getPoolCollateralization() public view override returns (uint256 poolCollateralization_) {
        if (lup != 0 && totalDebt != 0) {
            return Maths.wdiv(totalCollateral, getEncumberedCollateral(totalDebt));
        }
        return Maths.ONE_WAD;
    }

    function getPoolActualUtilization() public view override returns (uint256 poolActualUtilization_) {
        if (totalDebt == 0) {
            return 0;
        }
        return Maths.wdiv(totalDebt, totalQuoteToken + totalDebt);
    }

    function getPoolTargetUtilization() public view override returns (uint256 poolTargetUtilization_) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
    }

    function updateInterestRate() external override {
        // RAY
        uint256 actualUtilization = getPoolActualUtilization();
        if (
            actualUtilization != 0 &&
            previousRateUpdate < block.timestamp &&
            getPoolCollateralization() > Maths.ONE_WAD
        ) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(
                previousRate,
                (
                    Maths.rayToWad(actualUtilization) + Maths.ONE_WAD
                        - Maths.rayToWad(getPoolTargetUtilization())
                )
            );
            previousRateUpdate = block.timestamp;
            emit UpdateInterestRate(oldRate, previousRate);
        }
    }


    /*****************************/
    /*** Borrower Management ***/
    /*****************************/

    // TODO: fix this
    // TODO: rename and add in parallel with ERC20 getBorrowerInfo
    // TODO: fix encumberance and collateralization checks for ERC721
    function getBorrowerInfo(address borrower_)
        public view returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256[] memory collateralDeposited_,
            uint256 collateralEncumbered_,
            uint256 collateralization_,
            uint256 borrowerInflatorSnapshot_,
            uint256 inflatorSnapshot_
        )
    {
        NFTBorrowerInfo memory borrower = NFTborrowers[borrower_];
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization = Maths.ONE_WAD;

        if (borrower.debt > 0 && borrower.inflatorSnapshot != 0) {
            borrowerPendingDebt  += getPendingInterest(borrower.debt, getPendingInflator(), borrower.inflatorSnapshot);
            collateralEncumbered  = getEncumberedCollateral(borrowerPendingDebt);
            collateralization     = Maths.wdiv(borrower.collateralDeposited.length, collateralEncumbered);
        }

        return (
            borrower.debt,
            borrowerPendingDebt,
            borrower.collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
    }

    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) public view override returns (uint256 borrowerCollateralization_) {
        if (lup != 0 && debt_ != 0) {
            return Maths.wdiv(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.ONE_WAD;
    }

    function estimatePriceForLoan(uint256 amount_) public view override returns (uint256 price_) {
        // convert amount from WAD to collateral pool precision - RAD
        return estimatePrice(amount_, lup == 0 ? hpb : lup);
    }

    // Implementing this method allows contracts to receive ERC721 tokens
    // https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}