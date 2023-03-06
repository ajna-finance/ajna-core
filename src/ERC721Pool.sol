// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import {
    IERC721Token,
    IPoolErrors,
    IPoolLenderActions,
    IPoolLiquidationActions
}                           from './interfaces/pool/IPool.sol';
import {
    BucketTakeResult,
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

import { FlashloanablePool } from './base/FlashloanablePool.sol';

import { 
    _revertIfAuctionClearable,
    _revertOnExpiry 
}                               from './libraries/helpers/RevertsHelper.sol';

import { Maths }    from './libraries/internal/Maths.sol';
import { Deposits } from './libraries/internal/Deposits.sol';
import { Loans }    from './libraries/internal/Loans.sol';

import { Auctions }        from './libraries/external/Auctions.sol';
import { LenderActions }   from './libraries/external/LenderActions.sol';
import { BorrowerActions } from './libraries/external/BorrowerActions.sol';

/**
 *  @title  ERC721 Pool contract
 *  @notice Entrypoint of ERC721 Pool actions for pool actors:
 *          - Lenders: add, remove and move quote tokens; transfer LPs
 *          - Borrowers: draw and repay debt
 *          - Traders: add, remove and move quote tokens; add and remove collateral
 *          - Kickers: auction undercollateralized loans; settle auctions; claim bond rewards
 *          - Bidders: take auctioned collateral
 *          - Reserve purchasers: start auctions; take reserves
 *          - Flash borrowers: initiate flash loans on ERC20 quote tokens
 *  @dev    Contract is FlashloanablePool with flash loan logic.
 *  @dev    Contract is base Pool with logic to handle ERC721 collateral.
 *  @dev    Calls logic from external PoolCommons, LenderActions, BorrowerActions and Auctions libraries.
 */
contract ERC721Pool is FlashloanablePool, IERC721Pool {

    /*****************/
    /*** Constants ***/
    /*****************/

    // immutable args offset
    uint256 internal constant SUBSET   = 93;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed;  // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerTokenIds; // borrower address => array of tokenIds pledged by borrower
    uint256[]                     public bucketTokenIds;   // array of tokenIds added in pool buckets

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

        uint256 noOfTokens = tokenIds_.length;

        if (noOfTokens != 0) {
            // add subset of tokenIds allowed in the pool
            for (uint256 id = 0; id < noOfTokens;) {
                tokenIdsAllowed[tokenIds_[id]] = true;

                unchecked { ++id; }
            }
        }

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

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @inheritdoc IERC721PoolBorrowerActions
     *  @dev write state:
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - increment poolBalances.pledgedCollateral accumulator
     *          - increment poolBalances.t0Debt accumulator
     *          - update borrowerTokenIds and bucketTokenIds arrays
     *  @dev emit events:
     *          - DrawDebtNFT
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

        // adjust t0Debt2ToCollateral ratio
        _updateT0Debt2ToCollateral(
            result.debtPreAction,
            result.debtPostAction,
            result.collateralPreAction,
            result.collateralPostAction
        );

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.t0Debt     = result.t0PoolDebt;
        poolState.collateral = result.poolCollateral;
        _updateInterestState(poolState, result.newLup);

        if (tokenIdsToPledge_.length != 0) {
            // update pool balances state
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= result.t0DebtInAuctionChange;
            }
            poolBalances.pledgedCollateral = result.poolCollateral;

            // move collateral from sender to pool
            _transferFromSenderToPool(borrowerTokenIds[borrowerAddress_], tokenIdsToPledge_);
        }

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);

        // move borrowed amount from pool to sender
        if (amountToBorrow_ != 0) {
            // update pool balances state
            poolBalances.t0Debt = result.t0PoolDebt;

            // move borrowed amount from pool to sender
            _transferQuoteToken(msg.sender, amountToBorrow_);
        }
    }

    /**
     *  @inheritdoc IERC721PoolBorrowerActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     *          - update borrowerTokenIds and bucketTokenIds arrays
     *  @dev emit events:
     *          - RepayDebt
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

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);

        // adjust t0Debt2ToCollateral ratio
        _updateT0Debt2ToCollateral(
            result.debtPreAction,
            result.debtPostAction,
            result.collateralPreAction,
            result.collateralPostAction
        );

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.t0Debt     = result.t0PoolDebt;
        poolState.collateral = result.poolCollateral;
        _updateInterestState(poolState, result.newLup);

        // update pool balances state
        poolBalances.pledgedCollateral = result.poolCollateral;

        if (result.quoteTokenToRepay != 0) {
            // update pool balances state
            poolBalances.t0Debt = result.t0PoolDebt;
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= result.t0DebtInAuctionChange;
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
     *  @dev write state:
     *          - update bucketTokenIds arrays
     *  @dev emit events:
     *          - AddCollateralNFT
     */
    function addCollateral(
        uint256[] calldata tokenIdsToAdd_,
        uint256 index_,
        uint256 expiry_
    ) external override nonReentrant returns (uint256 bucketLPs_) {
        _revertOnExpiry(expiry_);
        PoolState memory poolState = _accruePoolInterest();

        bucketLPs_ = LenderActions.addCollateral(
            buckets,
            deposits,
            Maths.wad(tokenIdsToAdd_.length),
            index_
        );

        emit AddCollateralNFT(msg.sender, index_, tokenIdsToAdd_, bucketLPs_);

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        // move required collateral from sender to pool
        _transferFromSenderToPool(bucketTokenIds, tokenIdsToAdd_);
    }

    /**
     *  @inheritdoc IERC721PoolLenderActions
     *  @dev write state:
     *          - update bucketTokenIds arrays
     *  @dev emit events:
     *          - MergeOrRemoveCollateralNFT
     */
    function mergeOrRemoveCollateral(
        uint256[] calldata removalIndexes_,
        uint256 noOfNFTsToRemove_,
        uint256 toIndex_
    ) external override nonReentrant returns (uint256 collateralMerged_, uint256 bucketLPs_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();
        uint256 collateralAmount = Maths.wad(noOfNFTsToRemove_);

        (
            collateralMerged_,
            bucketLPs_
        ) = LenderActions.mergeOrRemoveCollateral(
            buckets,
            deposits,
            removalIndexes_,
            collateralAmount,
            toIndex_
        );

        emit MergeOrRemoveCollateralNFT(msg.sender, collateralMerged_, bucketLPs_);

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        if (collateralMerged_ == collateralAmount) {
            // Total collateral in buckets meets the requested removal amount, noOfNFTsToRemove_
            _transferFromPoolToAddress(msg.sender, bucketTokenIds, noOfNFTsToRemove_);
        }

    }

    /**
     *  @inheritdoc IPoolLenderActions
     *  @dev write state:
     *          - update bucketTokenIds arrays
     *  @dev emit events:
     *          - RemoveCollateral
     */
    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override nonReentrant returns (uint256 collateralAmount_, uint256 lpAmount_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        collateralAmount_ = Maths.wad(noOfNFTsToRemove_);
        lpAmount_ = LenderActions.removeCollateral(
            buckets,
            deposits,
            collateralAmount_,
            index_
        );

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_, lpAmount_);

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        _transferFromPoolToAddress(msg.sender, bucketTokenIds, noOfNFTsToRemove_);
    }

    /*******************************/
    /*** Pool Auctions Functions ***/
    /*******************************/

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external nonReentrant override {
        PoolState memory poolState = _accruePoolInterest();

        uint256 assets = Maths.wmul(poolBalances.t0Debt, poolState.inflator) + _getNormalizedPoolQuoteTokenBalance();

        uint256 liabilities = Deposits.treeSum(deposits) + auctions.totalBondEscrowed + reserveAuction.unclaimed;

        SettleParams memory params = SettleParams(
            {
                borrower:    borrowerAddress_,
                reserves:    (assets > liabilities) ? (assets-liabilities) : 0,
                inflator:    poolState.inflator,
                bucketDepth: maxDepth_,
                poolType:    poolState.poolType
            }
        );

        SettleResult memory result = Auctions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            loans,
            params
        );

        if (result.collateralSettled > 0) _rebalanceTokens(params.borrower, result.collateralRemaining);

        // update pool balances state
        poolBalances.t0Debt            -= result.t0DebtSettled;
        poolBalances.t0DebtInAuction   -= result.t0DebtSettled;
        poolBalances.pledgedCollateral -= result.collateralSettled;

        // adjust t0Debt2ToCollateral ratio
        _updateT0Debt2ToCollateral(
            result.debtPreAction,
            result.debtPostAction,
            result.collateralPreAction,
            result.collateralRemaining
        );

        // update pool interest rate state
        poolState.debt       -= Maths.wmul(result.t0DebtSettled, poolState.inflator);
        poolState.t0Debt     -= result.t0DebtSettled;
        poolState.collateral -= result.collateralSettled;
        _updateInterestState(poolState, _lup(poolState.debt));
    }

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        TakeResult memory result = Auctions.take(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            Maths.wad(collateral_),
            1
        );

        // update pool balances state
        uint256 t0DebtInAuction = poolBalances.t0DebtInAuction;
        t0DebtInAuction += result.t0DebtPenalty;
        t0DebtInAuction -= result.t0DebtInAuctionChange;

        poolBalances.t0Debt          = result.t0PoolDebt;
        poolBalances.t0DebtInAuction = t0DebtInAuction;

        // the total collateral taken from borrower pledged collateral (collateral taken plus collateral compensated if auction settled)
        uint256 collateralSettled = result.collateralAmount + result.compensatedCollateral;
        poolBalances.pledgedCollateral -= collateralSettled;

        // adjust t0Debt2ToCollateral ratio
        _updateT0Debt2ToCollateral(
            result.debtPreAction,
            result.debtPostAction,
            result.collateralPreAction,
            result.collateralPostAction
        );

        // update pool interest rate state
        poolState.debt       =  result.poolDebt;
        poolState.t0Debt     =  result.t0PoolDebt;
        poolState.collateral -= collateralSettled;
        _updateInterestState(poolState, result.newLup);

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
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
    function bucketTake(
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external override nonReentrant {

        PoolState memory poolState = _accruePoolInterest();

        BucketTakeResult memory result = Auctions.bucketTake(
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

        // update pool balances state
        uint256 t0DebtInAuction = poolBalances.t0DebtInAuction;
        t0DebtInAuction += result.t0DebtPenalty;
        t0DebtInAuction -= result.t0DebtInAuctionChange;

        poolBalances.t0Debt          = result.t0PoolDebt;
        poolBalances.t0DebtInAuction = t0DebtInAuction;

        // the total collateral taken from borrower pledged collateral (collateral taken plus collateral compensated if auction settled)
        uint256 collateralSettled = result.collateralAmount + result.compensatedCollateral;
        poolBalances.pledgedCollateral -= collateralSettled;

        // adjust t0Debt2ToCollateral ratio
        _updateT0Debt2ToCollateral(
            result.debtPreAction,
            result.debtPostAction,
            result.collateralPreAction,
            result.collateralPostAction
        );

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.t0Debt     = result.t0PoolDebt;
        poolState.collateral -= collateralSettled;
        _updateInterestState(poolState, result.newLup);

        if (result.settledAuction) _rebalanceTokens(borrowerAddress_, result.remainingCollateral);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Rebalance NFT token and transfer difference to floor collateral from borrower to pool claimable array
     *  @dev    write state:
     *              - update borrowerTokens and bucketTokenIds arrays
     *  @dev    emit events:
     *              - RemoveCollateral
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
        uint256 noOfTokensToTransfer = borrowerCollateral_ != 0 ? noOfTokensPledged - borrowerCollateral_ / 1e18 : noOfTokensPledged;

        for (uint256 i = 0; i < noOfTokensToTransfer;) {
            uint256 tokenId = borrowerTokens[--noOfTokensPledged]; // start with moving the last token pledged by borrower
            borrowerTokens.pop();                                  // remove token id from borrower
            bucketTokenIds.push(tokenId);                          // add token id to pool claimable tokens

            unchecked { ++i; }
        }
    }

    /**
     *  @notice Helper function for transferring multiple NFT tokens from msg.sender to pool.
     *  @notice Reverts in case token id is not supported by subset pool.
     *  @param  poolTokens_ Array in pool that tracks NFT ids (could be tracking NFTs pledged by borrower or NFTs added by a lender in a specific bucket).
     *  @param  tokenIds_   Array of NFT token ids to transfer from msg.sender to pool.
     */
    function _transferFromSenderToPool(
        uint256[] storage poolTokens_,
        uint256[] calldata tokenIds_
    ) internal {
        bool subset   = _getArgUint256(SUBSET) != 0;

        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();
            poolTokens_.push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked { ++i; }
        }
    }

    /**
     *  @notice Helper function for transferring multiple NFT tokens from pool to given address.
     *  @notice It transfers NFTs from the most recent one added into the pool (pop from array tracking NFTs in pool).
     *  @param  toAddress_      Address where pool should transfer tokens to.
     *  @param  poolTokens_     Array in pool that tracks NFT ids (could be tracking NFTs pledged by borrower or NFTs added by a lender in a specific bucket).
     *  @param  amountToRemove_ Number of NFT tokens to transfer from pool to given address.
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
     *  @dev Helper function to transfer an NFT from owner to target address (reused in code to reduce contract deployment bytecode size).
     *  @dev Since transferFrom is used instead of safeTransferFrom, calling smart contracts must be careful to check that they support any received NFTs.
     *  @param from_    NFT owner address.
     *  @param to_      New NFT owner address.
     *  @param tokenId_ NFT token id to be transferred.
     */
    function _transferNFT(address from_, address to_, uint256 tokenId_) internal {
        // slither-disable-next-line calls-loop
        IERC721Token(_getArgAddress(COLLATERAL_ADDRESS)).transferFrom(from_, to_, tokenId_);
    }

}
