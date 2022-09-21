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
     *  @notice Emitted when an actor settles debt in a completed liquidation
     *  @param  borrower_           Identifies the loan being liquidated.
     *  @param  hpbIndex_           The index of the Highest Price Bucket where debt was cleared.
     *  @param  amount_             Amount of debt cleared from the HPB in this transaction.
     *  @param  tokenIdsReturned_   Array of NFTs returned to the borrower in this transaction.
     *  @param  amountRemaining_    Amount of debt which still needs to be cleared.
     *  @dev    When amountRemaining_ == 0, the auction has been completed cleared and removed from the queue.
     */
    event ClearNFT(
        address   indexed borrower_,
        uint256   hpbIndex_,
        uint256   amount_,
        uint256[] tokenIdsReturned_,
        uint256   amountRemaining_);

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     */
    event PledgeCollateralNFT(address indexed borrower_, uint256[] tokenIds_);

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
     *  @notice Emitted when an actor uses quote token outside of the book to purchase collateral under liquidation.
     *  @param  borrower_   Identifies the loan being liquidated.
     *  @param  amount_     Amount of quote token used to purchase collateral.
     *  @param  tokenIds_   Tokens purchased with quote token.
     *  @param  bondChange_ Impact of this take to the liquidation bond.
     *  @dev    amount_ / len(tokenIds_) implies the auction price.
     */
    event Take(address indexed borrower_, uint256 amount_, uint256[] tokenIds_, int256 bondChange_);


    /*************************/
    /*** ERC721Pool Errors ***/
    /*************************/

    /**
     *  @notice Failed to add tokenId to an EnumerableSet.
     */
    error AddTokenFailed();

    /**
     *  @notice User attempted to add an NFT to the pool with a tokenId outsde of the allowed subset.
     */
    error OnlySubset();

    /**
     *  @notice Failed to remove a tokenId from an EnumerableSet.
     */
    error RemoveTokenFailed();

    /**
     *  @notice User attempted to interact with a tokenId that hasn't been deposited into the pool or bucket.
     */
    error TokenNotDeposited();


    /**************************/
    /*** ERC721Pool Structs ***/
    /**************************/

    /**
     *  @notice Maintains the state of a liquidation.
     *  @param  kickTime            Time the liquidation was initiated.
     *  @param  referencePrice      Highest Price Bucket at time of liquidation.
     *  @param  remainingTokenIds   Liquidated NFTs which not yet been taken.
     *  @param  remainingDebt       Amount of debt which has not been covered by the liquidation.
     */
    struct NFTLiquidationInfo {
        uint128               kickTime;
        uint128               referencePrice;
        EnumerableSet.UintSet remainingTokenIds;
        uint256               remainingDebt;
    }


    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Called by deployNFTSubsetPool()
     *  @dev    Used to initialize pools that only support a subset of tokenIds
     *  @param  tokenIds_         Enumerates tokenIds to be allowed in the pool.
     *  @param  interestRate_     Initial interest rate of the pool.
     *  @param  ajnaTokenAddress_ Address of the Ajna token.
     */
    function initializeSubset(uint256[] memory tokenIds_, uint256 interestRate_, address ajnaTokenAddress_) external;


    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ The address of borrower to pledge collateral for.
     *  @param  tokenIds_ Array of tokenIds to be added to the pool.
     */
    function pledgeCollateral(address borrower_, uint256[] calldata tokenIds_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  tokenIds_ Array of tokenIds to be removed from the pool.
     */
    function pullCollateral(uint256[] calldata tokenIds_) external;
    

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


    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Called by actors to purchase collateral using quote token they provide themselves.
     *  @param  borrower_     Identifies the loan being liquidated.
     *  @param  tokenIds_     NFT token ids caller wishes to purchase from the liquidation.
     *  @param  swapCalldata_ If provided, delegate call will be invoked after sending collateral to msg.sender,
     *                        such that sender will have a sufficient quote token balance prior to payment.
     */
    function take(address borrower_, uint256[] calldata tokenIds_, bytes memory swapCalldata_) external;


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
