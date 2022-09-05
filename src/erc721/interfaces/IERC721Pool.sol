// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Ajna ERC20 Pool
 */
interface IERC721Pool is IScaledPool {

    /*************************/
    /*** ERC721Pool Events ***/
    /*************************/

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor_    Recipient that added collateral.
     *  @param  price_    Price at which collateral were added.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     */
    event AddCollateralNFT(address indexed actor_, uint256 indexed price_, uint256[] tokenIds_);

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     */
    event PledgeCollateralNFT(address indexed borrower_, uint256[] tokenIds_);

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
    event PullCollateralNFT(address indexed borrower_, uint256[] tokenIds_);

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer_  Recipient that claimed collateral.
     *  @param  price_    Price at which unencumbered collateral was claimed.
     *  @param  tokenIds_ Array of tokenIds to be removed from the pool.
     */
    event RemoveCollateralNFT(address indexed claimer_, uint256 indexed price_, uint256[] tokenIds_);

    /**
     *  @notice Emitted when borrower repays quote tokens to the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  lup_      LUP after repay.
     *  @param  amount_   Amount of quote tokens repayed to the pool.
     */
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /*************************/
    /*** ERC721Pool Errors ***/
    /*************************/

    /**
     *  @notice Failed to add tokenId to an EnumerableSet.
     */
    error AddTokenFailed();

    /**
     *  @notice Failed to remove a tokenId from an EnumerableSet.
     */
    error RemoveTokenFailed();

    /**
     *  @notice User attempted to add an NFT to the pool with a tokenId outsde of the allowed subset.
     */
    error OnlySubset();

    /**
     *  @notice User attempted to interact with a tokenId that hasn't been deposited into the pool or bucket.
     */
    error TokenNotDeposited();

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
     *  @param  borrower_ The address of borrower to pledge collateral for.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     *  @param  oldPrev_  Previous borrower that came before placed loan (old)
     *  @param  newPrev_  Previous borrower that now comes before placed loan (new)
     */
    function pledgeCollateral(address borrower_, uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external;

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
    function pullCollateral(uint256[] calldata tokenIds_, address oldPrev_, address newPrev_) external;

    /**
     *  @notice Called by a borrower to repay some amount of their borrowed quote tokens.
     *  @param  borrower_  The address of borrower to repay quote token amount for.
     *  @param  maxAmount_ WAD The maximum amount of quote token to repay.
     *  @param  oldPrev_   Previous borrower that came before placed loan (old)
     *  @param  newPrev_   Previous borrower that now comes before placed loan (new)
     */
    function repay(address borrower_, uint256 maxAmount_, address oldPrev_, address newPrev_) external;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Deposit unencumbered collateral into a specified bucket.
     *  @param  tokenIds_ Array of collateral to deposit.
     *  @param  index_    The bucket index to which collateral will be deposited.
     */
    function addCollateral(uint256[] calldata tokenIds_, uint256 index_) external returns (uint256 lpbChange_);

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  tokenIds_ NFT token ids to be removed from the pool.
     *  @param  index_    The index of the bucket from which unencumbered collateral will be claimed.
     *  @return lpAmount_ The amount of LP tokens used for removing collateral amount.
     */
    function removeCollateral(uint256[] calldata tokenIds_, uint256 index_) external returns (uint256 lpAmount_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Get a borrower info struct for a given address.
     *  @param  borrower_            The borrower address.
     *  @return debt_                Borrower accrued debt (WAD)
     *  @return pendingDebt_         Borrower current debt, accrued and pending accrual (WAD)
     *  @return collateralDeposited_ Array of deposited collateral IDs including encumbered
     *  @return inflatorSnapshot_    Inflator used to calculate pending interest (WAD)
     */
    function borrowerInfo(address borrower_)
        external
        view
        returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256[] memory collateralDeposited_,
            uint256 inflatorSnapshot_
        );

    /**
     *  @notice Check if a token id is allowed as collateral in pool.
     *  @param  tokenId_ The token id to check.
     *  @return allowed_ True if token id is allowed in pool
     */
    function isTokenIdAllowed(uint256 tokenId_) external view returns (bool allowed_);
}
