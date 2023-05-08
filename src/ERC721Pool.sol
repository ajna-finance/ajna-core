// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import {
    IERC721Token,
    IPoolErrors,
    IPoolLenderActions,
    IPoolKickerActions,
    IPoolTakerActions,
    IPoolSettlerActions
}                           from './interfaces/pool/IPool.sol';
import {
    DrawDebtResult,
    RepayDebtResult,
    SettleParams,
    SettleResult,
    TakeResult
}                           from './interfaces/pool/commons/IPoolInternals.sol';
import { PoolState }        from './interfaces/pool/commons/IPoolState.sol';

import {
    IERC721Pool,
    IERC721PoolBorrowerActions,
    IERC721PoolImmutables,
    IERC721PoolLenderActions
}                               from './interfaces/pool/erc721/IERC721Pool.sol';
import { IERC721Taker }         from './interfaces/pool/erc721/IERC721Taker.sol';
import { IERC721PoolState }     from './interfaces/pool/erc721/IERC721PoolState.sol';

import { FlashloanablePool } from './base/FlashloanablePool.sol';

import {
    _revertIfAuctionClearable,
    _revertOnExpiry
}                               from './libraries/helpers/RevertsHelper.sol';

import { Maths }    from './libraries/internal/Maths.sol';
import { Deposits } from './libraries/internal/Deposits.sol';
import { Loans }    from './libraries/internal/Loans.sol';

import { LenderActions }   from './libraries/external/LenderActions.sol';
import { BorrowerActions } from './libraries/external/BorrowerActions.sol';
import { SettlerActions }  from './libraries/external/SettlerActions.sol';
import { TakerActions }    from './libraries/external/TakerActions.sol';

/**
 *  @title  ERC721 Pool contract
 *  @notice Entrypoint of `ERC721` Pool actions for pool actors:
 *          - `Lenders`: add, remove and move quote tokens; transfer `LP`
 *          - `Borrowers`: draw and repay debt
 *          - `Traders`: add, remove and move quote tokens; add and remove collateral
 *          - `Kickers`: auction undercollateralized loans; settle auctions; claim bond rewards
 *          - `Bidders`: take auctioned collateral
 *          - `Reserve purchasers`: start auctions; take reserves
 *          - `Flash borrowers`: initiate flash loans on ERC20 quote tokens
 *  @dev    Contract is `FlashloanablePool` with flashloan logic.
 *  @dev    Contract is base `Pool` with logic to handle `ERC721` collateral.
 *  @dev    Calls logic from external `PoolCommons`, `LenderActions`, `BorrowerActions` and `Auction` actions libraries.
 */
contract ERC721Pool is FlashloanablePool, IERC721Pool {

    /*****************/
    /*** Constants ***/
    /*****************/

    /// @dev Immutable NFT subset pool arg offset.
    uint256 internal constant SUBSET = 93;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Array of tokens permitted by the Pool (if applicable)
    uint256[]                     public subsetTokenIds;
    /// @dev Borrower `address => array` of tokenIds pledged by borrower mapping.
    mapping(address => uint256[]) public borrowerTokenIds;
    /// @dev Array of `tokenIds` in pool buckets (claimable from pool).
    uint256[]                     public bucketTokenIds;

    /// @dev Mapping of `tokenIds` allowed in `NFT` Subset type pool.
    mapping(uint256 => bool)      internal tokenIdsAllowed_;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    /// @inheritdoc IERC721Pool
    function initialize(
        uint256[] memory tokenIds_,
        uint256 rate_
    ) external override {
        if (isPoolInitialized) revert AlreadyInitialized();

        inflatorState.inflator       = uint208(1e18);
        inflatorState.inflatorUpdate = uint48(block.timestamp);

        interestState.interestRate       = uint208(rate_);
        interestState.interestRateUpdate = uint48(block.timestamp);

        subsetTokenIds = tokenIds_;

        Loans.init(loans);

        // increment initializations count to ensure these values can't be updated
        isPoolInitialized = true;
    }

    /******************/
    /*** Immutables ***/
    /******************/

    /// @inheritdoc IERC721PoolImmutables
    function isSubset() external pure override returns (bool) {
        return _getArgUint256(SUBSET) != 0;
    }

    /**
     * @dev    Binary search of subtoken array to determine if token is permitted
     * @param  tokenId_ Token ID of NFT to check
     * @return          true if tokenId is permitted in the pool
     */
    function tokenIdsAllowed(uint256 tokenId_) public view returns (bool) {
        // true if token is not a subset pool or token has already been initialized
        if (_getArgUint256(SUBSET) == 0 || tokenIdsAllowed_[tokenId_]) return true;

        uint256 low_;
        uint256 mid_;
        uint256 high_ = subsetTokenIds.length;
        // Binary search for log(n) lookup of NFT in sorted subset
        while (low_ < high_) {
            mid_ = (low_ & high_) + (low_ ^ high_) / 2; // rounds down
            if (subsetTokenIds[mid_] == tokenId_) return true;
            if (subsetTokenIds[mid_] > tokenId_) {
                high_ = mid_;
            } else {
                low_ = mid_ + 1;
            }
        }

        return false;
    }

    /**
     * @dev external function to optionally pre-approve a token before transfer
     * @param tokenId_ the NFT id to pre-approve
    */
    function allowToken(uint256 tokenId_) external {
        tokenIdsAllowed_[tokenId_] = tokenIdsAllowed(tokenId_);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @inheritdoc IERC721PoolBorrowerActions
     *  @dev    === Write state ===
     *  @dev    - decrement `poolBalances.t0DebtInAuction` accumulator
     *  @dev    - increment `poolBalances.pledgedCollateral` accumulator
     *  @dev    - increment `poolBalances.t0Debt` accumulator
     *  @dev    - update `t0Debt2ToCollateral` ratio only if loan not in auction, debt and collateral pre action are considered 0 if auction settled
     *  @dev    - update `borrowerTokenIds` and `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `DrawDebtNFT`
     */
    function drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256[] calldata tokenIdsToPledge_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        DrawDebtResult memory result = BorrowerActions.drawDebt(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            amountToBorrow_,
            limitIndex_,
            Maths.wad(tokenIdsToPledge_.length)
        );

        emit DrawDebtNFT(borrowerAddress_, amountToBorrow_, tokenIdsToPledge_, result.newLup);

        // update in memory pool state struct
        poolState.debt       = result.poolDebt;
        poolState.t0Debt     = result.t0PoolDebt;
        if (result.t0DebtInAuctionChange != 0) poolState.t0DebtInAuction -= result.t0DebtInAuctionChange;
        poolState.collateral = result.poolCollateral;

        // adjust t0Debt2ToCollateral ratio if loan not in auction
        if (!result.inAuction) {
            _updateT0Debt2ToCollateral(
                result.settledAuction ? 0 : result.debtPreAction,       // debt pre settle (for loan in auction) not taken into account
                result.debtPostAction,
                result.settledAuction ? 0 : result.collateralPreAction, // collateral pre settle (for loan in auction) not taken into account
                result.collateralPostAction
            );
        }

        // update pool interest rate state
        _updateInterestState(poolState, result.newLup);

        if (tokenIdsToPledge_.length != 0) {
            // update pool balances state
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction = poolState.t0DebtInAuction;
            }
            poolBalances.pledgedCollateral = poolState.collateral;

            // move collateral from sender to pool
            _transferFromSenderToPool(borrowerTokenIds[borrowerAddress_], tokenIdsToPledge_);
        }

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);

        // move borrowed amount from pool to sender
        if (amountToBorrow_ != 0) {
            // update pool balances state
            poolBalances.t0Debt = poolState.t0Debt;

            // move borrowed amount from pool to sender
            _transferQuoteToken(msg.sender, amountToBorrow_);
        }
    }

    /**
     *  @inheritdoc IERC721PoolBorrowerActions
     *  @dev    === Write state ===
     *  @dev    - decrement `poolBalances.t0Debt accumulator`
     *  @dev    - decrement `poolBalances.t0DebtInAuction accumulator`
     *  @dev    - decrement `poolBalances.pledgedCollateral accumulator`
     *  @dev    - update `t0Debt2ToCollateral` ratio only if loan not in auction, debt and collateral pre action are considered 0 if auction settled
     *  @dev    - update `borrowerTokenIds` and `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `RepayDebt`
     */
    function repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 noOfNFTsToPull_,
        address collateralReceiver_,
        uint256 limitIndex_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        RepayDebtResult memory result = BorrowerActions.repayDebt(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            maxQuoteTokenAmountToRepay_,
            Maths.wad(noOfNFTsToPull_),
            limitIndex_
        );

        emit RepayDebt(borrowerAddress_, result.quoteTokenToRepay, noOfNFTsToPull_, result.newLup);

        // update in memory pool state struct
        poolState.debt       = result.poolDebt;
        poolState.t0Debt     = result.t0PoolDebt;
        if (result.t0DebtInAuctionChange != 0) poolState.t0DebtInAuction -= result.t0DebtInAuctionChange;
        poolState.collateral = result.poolCollateral;

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);

        // adjust t0Debt2ToCollateral ratio if loan not in auction
        if (!result.inAuction) {
            _updateT0Debt2ToCollateral(
                result.settledAuction ? 0 : result.debtPreAction,       // debt pre settle (for loan in auction) not taken into account
                result.debtPostAction,
                result.settledAuction ? 0 : result.collateralPreAction, // collateral pre settle (for loan in auction) not taken into account
                result.collateralPostAction
            );
        }

        // update pool interest rate state
        _updateInterestState(poolState, result.newLup);

        // update pool balances state
        poolBalances.pledgedCollateral = poolState.collateral;

        if (result.quoteTokenToRepay != 0) {
            // update pool balances state
            poolBalances.t0Debt = poolState.t0Debt;
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction = poolState.t0DebtInAuction;
            }

            // move amount to repay from sender to pool
            _transferQuoteTokenFrom(msg.sender, result.quoteTokenToRepay);
        }
        if (noOfNFTsToPull_ != 0) {
            // move collateral from pool to address specified as collateral receiver
            _transferFromPoolToAddress(collateralReceiver_, borrowerTokenIds[msg.sender], noOfNFTsToPull_);
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @inheritdoc IERC721PoolLenderActions
     *  @dev    === Write state ===
     *  @dev    - update `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `AddCollateralNFT`
     */
    function addCollateral(
        uint256[] calldata tokenIds_,
        uint256 index_,
        uint256 expiry_
    ) external override nonReentrant returns (uint256 bucketLP_) {
        _revertOnExpiry(expiry_);
        PoolState memory poolState = _accruePoolInterest();

        bucketLP_ = LenderActions.addCollateral(
            buckets,
            deposits,
            Maths.wad(tokenIds_.length),
            index_
        );

        emit AddCollateralNFT(msg.sender, index_, tokenIds_, bucketLP_);

        // update pool interest rate state
        _updateInterestState(poolState, Deposits.getLup(deposits, poolState.debt));

        // move required collateral from sender to pool
        _transferFromSenderToPool(bucketTokenIds, tokenIds_);
    }

    /**
     *  @inheritdoc IERC721PoolLenderActions
     *  @dev    === Write state ===
     *  @dev    - update `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `MergeOrRemoveCollateralNFT`
     */
    function mergeOrRemoveCollateral(
        uint256[] calldata removalIndexes_,
        uint256 noOfNFTsToRemove_,
        uint256 toIndex_
    ) external override nonReentrant returns (uint256 collateralMerged_, uint256 bucketLP_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();
        uint256 collateralAmount = Maths.wad(noOfNFTsToRemove_);

        (
            collateralMerged_,
            bucketLP_
        ) = LenderActions.mergeOrRemoveCollateral(
            buckets,
            deposits,
            removalIndexes_,
            collateralAmount,
            toIndex_
        );

        emit MergeOrRemoveCollateralNFT(msg.sender, collateralMerged_, bucketLP_);

        // update pool interest rate state
        _updateInterestState(poolState, Deposits.getLup(deposits, poolState.debt));

        if (collateralMerged_ == collateralAmount) {
            // Total collateral in buckets meets the requested removal amount, noOfNFTsToRemove_
            _transferFromPoolToAddress(msg.sender, bucketTokenIds, noOfNFTsToRemove_);
        }

    }

    /**
     *  @inheritdoc IPoolLenderActions
     *  @dev    === Write state ===
     *  @dev    - update `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `RemoveCollateral`
     *  @param noOfNFTsToRemove_ Number of `NFT` tokens to remove.
     */
    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override nonReentrant returns (uint256 removedAmount_, uint256 redeemedLP_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        removedAmount_ = Maths.wad(noOfNFTsToRemove_);
        redeemedLP_ = LenderActions.removeCollateral(
            buckets,
            deposits,
            removedAmount_,
            index_
        );

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_, redeemedLP_);

        // update pool interest rate state
        _updateInterestState(poolState, Deposits.getLup(deposits, poolState.debt));

        _transferFromPoolToAddress(msg.sender, bucketTokenIds, noOfNFTsToRemove_);
    }

    /*******************************/
    /*** Pool Auctions Functions ***/
    /*******************************/

    /**
     *  @inheritdoc IPoolSettlerActions
     *  @dev    === Write state ===
     *  @dev    - decrement `poolBalances.t0Debt` accumulator
     *  @dev    - decrement `poolBalances.t0DebtInAuction` accumulator
     *  @dev    - decrement `poolBalances.pledgedCollateral` accumulator
     *  @dev    - no update of `t0Debt2ToCollateral` ratio as debt and collateral pre settle are not taken into account (pre debt and pre collateral = 0)
     */
    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external nonReentrant override {
        PoolState memory poolState = _accruePoolInterest();

        SettleParams memory params = SettleParams({
            borrower:    borrowerAddress_,
            poolBalance: _getNormalizedPoolQuoteTokenBalance(),
            bucketDepth: maxDepth_
        });

        SettleResult memory result = SettlerActions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            loans,
            reserveAuction,
            poolState,
            params
        );

        _updatePostSettleState(result, poolState);

        // move token ids from borrower array to pool claimable array if any collateral used to settle bad debt
        if (result.collateralSettled != 0) _rebalanceTokens(params.borrower, result.collateralRemaining);
    }

    /**
     *  @inheritdoc IPoolTakerActions
     *  @dev    === Write state ===
     *  @dev    - decrement `poolBalances.t0Debt` accumulator
     *  @dev    - decrement `poolBalances.t0DebtInAuction` accumulator
     *  @dev    - decrement `poolBalances.pledgedCollateral` accumulator
     *  @dev    - update `t0Debt2ToCollateral` ratio only if auction settled, debt and collateral pre action are considered 0
     */
    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        TakeResult memory result = TakerActions.take(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            Maths.wad(collateral_),
            1
        );

        _updatePostTakeState(result, poolState);

        // transfer rounded collateral from pool to taker
        uint256[] memory tokensTaken = _transferFromPoolToAddress(
            callee_,
            borrowerTokenIds[borrowerAddress_],
            result.collateralAmount / 1e18
        );

        uint256 totalQuoteTokenAmount = result.quoteTokenAmount + result.excessQuoteToken;

        if (data_.length != 0) {
            IERC721Taker(callee_).atomicSwapCallback(
                tokensTaken,
                totalQuoteTokenAmount  / _getArgUint256(QUOTE_SCALE),
                data_
            );
        }

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);

        // transfer from taker to pool the amount of quote tokens needed to cover collateral auctioned (including excess for rounded collateral)
        _transferQuoteTokenFrom(msg.sender, totalQuoteTokenAmount);

        // transfer from pool to borrower the excess of quote tokens after rounding collateral auctioned
        if (result.excessQuoteToken != 0) _transferQuoteToken(borrowerAddress_, result.excessQuoteToken);
    }

    /**
     *  @inheritdoc IPoolTakerActions
     *  @dev    === Write state ===
     *  @dev    - decrement `poolBalances.t0Debt` accumulator
     *  @dev    - decrement `poolBalances.t0DebtInAuction` accumulator
     *  @dev    - decrement `poolBalances.pledgedCollateral` accumulator
     *  @dev    - update `t0Debt2ToCollateral` ratio only if auction settled, debt and collateral pre action are considered 0
     */
    function bucketTake(
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external override nonReentrant {

        PoolState memory poolState = _accruePoolInterest();

        TakeResult memory result = TakerActions.bucketTake(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            depositTake_,
            index_,
            1
        );

        _updatePostTakeState(result, poolState);

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Rebalance `NFT` token and transfer difference to floor collateral from borrower to pool claimable array.
     *  @dev    === Write state ===
     *  @dev    - update `borrowerTokens` and `bucketTokenIds` arrays
     *  @dev    === Emit events ===
     *  @dev    - `RemoveCollateral`
     *  @param  borrowerAddress_    Address of borrower.
     *  @param  borrowerCollateral_ Current borrower collateral to be rebalanced.
     */
    function _rebalanceTokens(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal {
        // rebalance borrower's collateral, transfer difference to floor collateral from borrower to pool claimable array
        uint256[] storage borrowerTokens = borrowerTokenIds[borrowerAddress_];

        uint256 noOfTokensPledged    = borrowerTokens.length;
        /*
            eg1. borrowerCollateral_ = 4.1, noOfTokensPledged = 6; noOfTokensToTransfer = 1
            eg2. borrowerCollateral_ = 4, noOfTokensPledged = 6; noOfTokensToTransfer = 2
        */
        uint256 borrowerCollateralRoundedUp = (borrowerCollateral_ + 1e18 - 1) / 1e18;
        uint256 noOfTokensToTransfer = noOfTokensPledged - borrowerCollateralRoundedUp;

        for (uint256 i = 0; i < noOfTokensToTransfer;) {
            uint256 tokenId = borrowerTokens[--noOfTokensPledged]; // start with moving the last token pledged by borrower
            borrowerTokens.pop();                                  // remove token id from borrower
            bucketTokenIds.push(tokenId);                          // add token id to pool claimable tokens

            unchecked { ++i; }
        }
    }

    /**
     *  @notice Helper function for transferring multiple `NFT` tokens from msg.sender to pool.
     *  @dev    Reverts in case token id is not supported by subset pool.
     *  @param  poolTokens_ Array in pool that tracks `NFT` ids (could be tracking `NFT`s pledged by borrower or `NFT`s added by a lender in a specific bucket).
     *  @param  tokenIds_   Array of `NFT` token ids to transfer from `msg.sender` to pool.
     */
    function _transferFromSenderToPool(
        uint256[] storage poolTokens_,
        uint256[] calldata tokenIds_
    ) internal {

        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];

            if (!tokenIdsAllowed(tokenId)) revert OnlySubset();
            tokenIdsAllowed_[tokenId] = true; // optimize future tokenIdsAllowed lookups
            poolTokens_.push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked { ++i; }
        }
    }

    /**
     *  @notice Helper function for transferring multiple `NFT` tokens from pool to given address.
     *  @dev    It transfers `NFT`s from the most recent one added into the pool (pop from array tracking `NFT`s in pool).
     *  @param  toAddress_      Address where pool should transfer tokens to.
     *  @param  poolTokens_     Array in pool that tracks `NFT` ids (could be tracking `NFT`s pledged by borrower or `NFT`s added by a lender in a specific bucket).
     *  @param  amountToRemove_ Number of `NFT` tokens to transfer from pool to given address.
     *  @return Array containing token ids that were transferred from pool to address.
     */
    function _transferFromPoolToAddress(
        address toAddress_,
        uint256[] storage poolTokens_,
        uint256 amountToRemove_
    ) internal returns (uint256[] memory) {
        uint256[] memory tokensTransferred = new uint256[](amountToRemove_);

        uint256 noOfNFTsInPool = poolTokens_.length;

        for (uint256 i = 0; i < amountToRemove_;) {
            uint256 tokenId = poolTokens_[--noOfNFTsInPool]; // start with transferring the last token added in bucket
            poolTokens_.pop();

            _transferNFT(address(this), toAddress_, tokenId);

            tokensTransferred[i] = tokenId;

            unchecked { ++i; }
        }

        return tokensTransferred;
    }

    /**
     *  @notice Helper function to transfer an `NFT` from owner to target address (reused in code to reduce contract deployment bytecode size).
     *  @dev    Since `transferFrom` is used instead of `safeTransferFrom`, calling smart contracts must be careful to check that they support any received `NFT`s.
     *  @param  from_    `NFT` owner address.
     *  @param  to_      New `NFT` owner address.
     *  @param  tokenId_ `NFT` token id to be transferred.
     */
    function _transferNFT(address from_, address to_, uint256 tokenId_) internal {
        // slither-disable-next-line calls-loop
        IERC721Token(_getArgAddress(COLLATERAL_ADDRESS)).transferFrom(from_, to_, tokenId_);
    }

    /*******************************/
    /*** External View Functions ***/
    /*******************************/

    /// @inheritdoc IERC721PoolState
    function totalBorrowerTokens(address borrower_) external view override returns(uint256) {
        return borrowerTokenIds[borrower_].length;
    }

    /// @inheritdoc IERC721PoolState
    function totalBucketTokens() external view override returns(uint256) {
        return bucketTokenIds.length;
    }

}
