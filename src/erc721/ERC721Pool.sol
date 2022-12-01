// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IERC721Pool.sol';
import './interfaces/IERC721Taker.sol';
import '../base/FlashloanablePool.sol';

contract ERC721Pool is IERC721Pool, FlashloanablePool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed;  // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerTokenIds; // borrower address => array of tokenIds pledged by borrower
    uint256[]                     public bucketTokenIds;   // array of tokenIds added in pool buckets

    bool public isSubset; // true if pool is a subset pool

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256[] memory tokenIds_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        inflatorSnapshot           = uint208(10**18);
        lastInflatorSnapshotUpdate = uint48(block.timestamp);
        interestRate               = uint208(rate_);
        interestRateUpdate         = uint48(block.timestamp);

        uint256 noOfTokens = tokenIds_.length;
        if (noOfTokens > 0) {
            isSubset = true;
            // add subset of tokenIds allowed in the pool
            for (uint256 id = 0; id < noOfTokens;) {
                tokenIdsAllowed[tokenIds_[id]] = true;
                unchecked {
                    ++id;
                }
            }
        }

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function drawDebt(
        address borrower_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256[] calldata tokenIdsToPledge_
    ) external {
        PoolState memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrower_);

        uint256 newLup = _lup(poolState.accruedDebt);

        // pledge collateral to pool
        if (tokenIdsToPledge_.length != 0) {
            borrower.collateral  += Maths.wad(tokenIdsToPledge_.length);
            poolState.collateral += Maths.wad(tokenIdsToPledge_.length);

            if (
                auctions.isActive(borrower_)
                &&
                _isCollateralized(
                    Maths.wmul(borrower.t0debt, poolState.inflator),
                    borrower.collateral,
                    newLup
                )
            )
            {
                // borrower becomes collateralized, remove debt from pool accumulator and settle auction
                t0DebtInAuction     -= borrower.t0debt;
                borrower.collateral = _settleAuction(borrower_, borrower.collateral);
            }

            pledgedCollateral = poolState.collateral;

            // move collateral from sender to pool
            _transferFromSenderToPool(borrowerTokenIds[borrower_], tokenIdsToPledge_);
        }

        // borrow against pledged collateral
        if (amountToBorrow_ != 0 || limitIndex_ != 0) {

            // if borrower auctioned then it cannot draw more debt
            auctions.revertIfActive(borrower_);

            uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);

            // add origination fee to the amount to borrow and add to borrower's debt
            uint256 debtChange   = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate) + Maths.WAD);
            borrowerDebt += debtChange;
            _checkMinDebt(poolState.accruedDebt, borrowerDebt);

            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
            if (lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            newLup = PoolUtils.indexToPrice(lupId);
            if (
                !_isCollateralized(borrowerDebt, borrower.collateral, newLup)
            ) revert BorrowerUnderCollateralized();

            // check borrow won't push pool into a state of under-collateralization
            poolState.accruedDebt += debtChange;
            if (
                !_isCollateralized(poolState.accruedDebt, poolState.collateral, newLup)
            ) revert PoolUnderCollateralized();

            uint256 t0debtChange = Maths.wdiv(debtChange, poolState.inflator);
            borrower.t0debt += t0debtChange;

            t0poolDebt += t0debtChange;

            // move borrowed amount from pool to sender
            _transferQuoteToken(msg.sender, amountToBorrow_);
        }

        emit DrawDebtNFT(borrower_, amountToBorrow_, tokenIdsToPledge_, newLup);

        loans.update(
            deposits,
            borrower_,
            true,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            newLup
        );

        _updateInterestParams(poolState, newLup);
    }

    function pullCollateral(
        uint256 noOfNFTsToPull_
    ) external override {
        _pullCollateral(Maths.wad(noOfNFTsToPull_));

        emit PullCollateral(msg.sender, noOfNFTsToPull_);
        // move collateral from pool to sender
        _transferFromPoolToAddress(msg.sender, borrowerTokenIds[msg.sender], noOfNFTsToPull_);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(
        uint256[] calldata tokenIdsToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _addCollateral(Maths.wad(tokenIdsToAdd_.length), index_);

        emit AddCollateralNFT(msg.sender, index_, tokenIdsToAdd_);
        // move required collateral from sender to pool
        _transferFromSenderToPool(bucketTokenIds, tokenIdsToAdd_);
    }

    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override returns (uint256 collateralAmount_, uint256 lpAmount_) {
        auctions.revertIfAuctionClearable(loans);

        collateralAmount_ = Maths.wad(noOfNFTsToRemove_);
        Buckets.Bucket storage bucket = buckets[index_];
        if (collateralAmount_ > bucket.collateral) revert InsufficientCollateral();

        PoolState memory poolState = _accruePoolInterest();

        lpAmount_ = Buckets.collateralToLPs(
            bucket.collateral,
            bucket.lps,
            deposits.valueAt(index_),
            collateralAmount_,
            PoolUtils.indexToPrice(index_)
        );

        (uint256 lenderLpBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        // ensure lender has enough balance to remove collateral amount
        if (lenderLpBalance == 0 || lpAmount_ > lenderLpBalance) revert InsufficientLPs();

        Buckets.removeCollateral(
            bucket,
            collateralAmount_,
            lpAmount_
        );

        _updateInterestParams(poolState, _lup(poolState.accruedDebt));

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_);
        _transferFromPoolToAddress(msg.sender, bucketTokenIds, noOfNFTsToRemove_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral();

        Auctions.TakeParams memory params = Auctions.take(
            auctions,
            borrowerAddress_,
            borrower,
            Maths.wad(collateral_),
            poolState.inflator
        );

        uint256 excessQuoteToken;
        uint256 collateralTaken = (params.collateralAmount / 1e18) * 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2
        if (collateralTaken !=  params.collateralAmount) { // collateral taken not a round number
            collateralTaken += 1e18; // round up collateral to take
            // taker should send additional quote tokens to cover difference between collateral needed to be taken and rounded collateral, at auction price
            // borrower will get quote tokens for the difference between rounded collateral and collateral taken to cover debt
            excessQuoteToken = Maths.wmul(collateralTaken - params.collateralAmount, params.auctionPrice);
        }

        borrower.collateral  -= collateralTaken;
        poolState.collateral -= collateralTaken;

        emit Take(
            borrowerAddress_,
            params.quoteTokenAmount,
            params.collateralAmount,
            params.bondChange,
            params.isRewarded
        );

        // transfer rounded collateral from pool to taker
        uint256[] memory tokensTaken = _transferFromPoolToAddress(callee_, borrowerTokenIds[borrowerAddress_], collateralTaken / 1e18);

        if (data_.length != 0) {
            IERC721Taker(callee_).atomicSwapCallback(
                tokensTaken, 
                params.quoteTokenAmount / _getArgUint256(40), 
                data_
            );
        }

        // transfer from taker to pool the amount of quote tokens needed to cover collateral auctioned (including excess for rounded collateral)
        _transferQuoteTokenFrom(callee_, params.quoteTokenAmount + excessQuoteToken);

        // transfer from pool to borrower the excess of quote tokens after rounding collateral auctioned
        if (excessQuoteToken != 0) _transferQuoteToken(borrowerAddress_, excessQuoteToken);

        _payLoan(params.t0repayAmount, poolState, borrowerAddress_, borrower);
        pledgedCollateral = poolState.collateral;
    }


    /*******************************/
    /*** Pool Override Functions ***/
    /*******************************/

    /**
     *  @notice Overrides default implementation and use floor(amount of collateral) to calculate collateralization.
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure override returns (bool) {
        //slither-disable-next-line divide-before-multiply
        collateral_ = (collateral_ / Maths.WAD) * Maths.WAD; // use collateral floor
        return Maths.wmul(collateral_, price_) >= debt_;
    }

    /**
     *  @notice Performs NFT auction settlement by rounding down borrower's collateral amount and by moving borrower's token ids to pool claimable array.
     *  @param borrowerAddress_    Address of the borrower that exits auction.
     *  @param borrowerCollateral_ Borrower collateral amount before auction exit (could be fragmented as result of partial takes).
     *  @return Rounded down collateral, the number of NFT tokens borrower can pull after auction exit.
     */
    function _settleAuction(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal override returns (uint256) {
        (uint256 floorCollateral, uint256 lps, uint256 bucketIndex) = Auctions.settleNFTAuction(
            auctions,
            buckets,
            deposits,
            borrowerTokenIds[borrowerAddress_],
            bucketTokenIds,
            borrowerAddress_,
            borrowerCollateral_
        );
        emit AuctionNFTSettle(borrowerAddress_, floorCollateral, lps, bucketIndex);
        return floorCollateral;
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

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
        bool subset = isSubset;
        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();
            poolTokens_.push(tokenId);

            _transferNFT(msg.sender, address(this), tokenId);

            unchecked {
                ++i;
            }
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

            unchecked {
                ++i;
            }
        }

        return tokensTransferred;
    }

    /**
     *  @dev Helper function to transfer an NFT from owner to target address (reused in code to reduce contract deployment bytecode size).
     *  @param from_    NFT owner address.
     *  @param to_      New NFT owner address.
     *  @param tokenId_ NFT token id to be transferred.
     */
    function _transferNFT(address from_, address to_, uint256 tokenId_) internal {
        //slither-disable-next-line calls-loop
        IERC721Token(_getArgAddress(0)).safeTransferFrom(from_, to_, tokenId_);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
