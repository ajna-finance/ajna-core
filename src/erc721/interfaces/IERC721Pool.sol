// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Ajna ERC20 Pool
 */
interface IERC721Pool is IScaledPool {

    /************************/
    /*** ERC20Pool Events ***/
    /************************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     */
    event AddCollateralNFT(address indexed borrower_, uint256[] tokenIds_);

    /**
     *  @notice Emitted when borrower borrows quote tokens from pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after borrow.
     *  @param  amount_   Amount of quote tokens borrowed from the pool.
     */
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

    /**
     *  @notice Emitted when borrower removes collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  tokenIds_ Array of tokenIds to be removed from the pool.
     */
    event RemoveCollateralNFT(address indexed borrower_, uint256[] tokenIds_);


    /**************************/
    /*** ERC721Pool Structs ***/
    /**************************/

     /**
     *  @notice Struct holding borrower related info per price bucket, for borrowers using NFTs as collateral.
     *  @param  debt                Borrower debt, WAD units.
     *  @param  collateralDeposited OZ Enumberable Set tracking the tokenIds of collateral that have been deposited
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY units.
     */
    struct NFTBorrower {
        uint256               debt;                // [WAD]
        EnumerableSet.UintSet collateralDeposited;
        uint256               inflatorSnapshot;    // [WAD]
    }

    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Called by deployNFTSubsetPool()
     *  @dev Used to initialize pools that only support a subset of tokenIds
     */
    function initializeSubset(uint256[] memory tokenIds_, uint256 interestRate_) external;

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     *  @param  oldPrev_ Previous borrower that came before placed loan (old)
     *  @param  newPrev_ Previous borrower that now comes before placed loan (new)
     */
    function addCollateral(uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to open or expand a position.
     *  @dev    Can only be called if quote tokens have already been added to the pool.
     *  @param  amount_     The amount of quote token to borrow.
     *  @param  limitIndex_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position.
     *  @param  oldPrev_    Previous borrower that came before placed loan (old)
     *  @param  newPrev_    Previous borrower that now comes before placed loan (new)
     */
    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  tokenIds_ Array of tokenIds to be removed from the pool.
     *  @param  oldPrev_  Previous borrower that came before placed loan (old)
     *  @param  newPrev_  Previous borrower that now comes before placed loan (new)
     */
    function removeCollateral(uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     *  @param  oldPrev_   Previous borrower that came before placed loan (old)
     *  @param  newPrev_   Previous borrower that now comes before placed loan (new)
     */
    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_) external;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  tokenIds_ Array of unencumbered collateral to claim.
     *  @param  index_    The index of the bucket from which unencumbered collateral will be claimed.
     */
    function claimCollateral(uint256[] calldata tokenIds_, uint256 index_) external;

    /*********************************/
    /*** Pool External Functions ***/
    /*********************************/

    /**
     *  @notice Purchase amount of quote token from specified bucket price.
     *  @param  amount_   Amount of quote tokens to purchase.
     *  @param  index_    The bucket index from which quote tokens will be purchased.
     *  @param  tokenIds_ Array of tokenIds to use as collateral for the purchase.
     */
    function purchaseQuote(uint256 amount_, uint256 index_, uint256[] calldata tokenIds_) external;

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Check if a token id is allowed as collateral in pool.
     *  @param  tokenId_ The token id to check.
     *  @return allowed_ True if token id is allowed in pool
     */
    function isTokenIdAllowed(uint256 tokenId_) external view returns (bool allowed_);
}
