// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import './interfaces/IERC721Pool.sol';
import './interfaces/IERC721Taker.sol';
import '../base/FlashloanablePool.sol';
import './interfaces/IERC721NonStandard.sol';

contract ERC721Pool is IERC721Pool, FlashloanablePool {

    /*****************/
    /*** Constants ***/
    /*****************/

    // immutable args offset
    uint256 internal constant SUBSET   = 93;
    uint256 internal constant NFT_TYPE = 125;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => bool)      public tokenIdsAllowed;  // set of tokenIds that can be used for a given NFT Subset type pool
    mapping(address => uint256[]) public borrowerTokenIds; // borrower address => array of tokenIds pledged by borrower
    uint256[]                     public bucketTokenIds;   // array of tokenIds added in pool buckets

    struct TakeLocalVars {
        uint256 auctionPrice;     // price of auction that is taken
        uint256 collateralAmount; // collateral amount in taken auction
        uint256 collateralTaken;  // amount of collateral taken
        uint256 excessQuoteToken; // difference of quote token that borrower receives for fractional NFT
        uint256 quoteTokenAmount; // amount of quote tokens that taker should provide
        uint256 t0DebtPenalty;    // t0 initial take penalty (7% from borrower's debt)
        uint256 t0RepayAmount;    // t0 debt repaid when auction is taken
        uint256[] tokensTaken;    // token ids taken
    }

    /****************************/
    /*** Initialize Functions ***/
    /****************************/
    
    function initialize(
        uint256[] memory tokenIds_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        inflatorState.inflator       = uint208(10**18);
        inflatorState.inflatorUpdate = uint48(block.timestamp);

        interestState.interestRate       = uint208(rate_);
        interestState.interestRateUpdate = uint48(block.timestamp);

        uint256 noOfTokens = tokenIds_.length;
        if (noOfTokens != 0) {
            // add subset of tokenIds allowed in the pool
            for (uint256 id = 0; id < noOfTokens;) {
                tokenIdsAllowed[tokenIds_[id]] = true;
                unchecked {
                    ++id;
                }
            }
        }

        Loans.init(loans);

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /******************/
    /*** Immutables ***/
    /******************/

    function isSubset() external pure override returns (bool) {
        return _getArgUint256(SUBSET) != 0;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256[] calldata tokenIdsToPledge_
    ) external {
        (
            bool pledge,
            bool borrow,
            uint256 newLup
        ) = _drawDebt(
            borrowerAddress_,
            amountToBorrow_,
            limitIndex_,
            Maths.wad(tokenIdsToPledge_.length)
        );

        emit DrawDebtNFT(borrowerAddress_, amountToBorrow_, tokenIdsToPledge_, newLup);

        // move collateral from sender to pool
        if (pledge) _transferFromSenderToPool(borrowerTokenIds[borrowerAddress_], tokenIdsToPledge_);
        // move borrowed amount from pool to sender
        if (borrow) _transferQuoteToken(msg.sender, amountToBorrow_);
    }

    function repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 noOfNFTsToPull_
    ) external {
        (uint256 quoteTokenToRepay, uint256 newLup) = _repayDebt(borrowerAddress_, maxQuoteTokenAmountToRepay_, Maths.wad(noOfNFTsToPull_));

        emit RepayDebt(borrowerAddress_, quoteTokenToRepay, noOfNFTsToPull_, newLup);

        if (quoteTokenToRepay != 0) {
            // move amount to repay from sender to pool
            _transferQuoteTokenFrom(msg.sender, quoteTokenToRepay);
        }
        if (noOfNFTsToPull_ != 0) {
            // move collateral from pool to sender
            _transferFromPoolToAddress(msg.sender, borrowerTokenIds[msg.sender], noOfNFTsToPull_);
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(
        uint256[] calldata tokenIdsToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
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

    function mergeOrRemoveCollateral(
        uint256[] calldata removalIndexes_,
        uint256 noOfNFTsToRemove_,
        uint256 toIndex_
    ) external override returns (uint256 collateralMerged_, uint256 bucketLPs_) {
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

    function removeCollateral(
        uint256 noOfNFTsToRemove_,
        uint256 index_
    ) external override returns (uint256 collateralAmount_, uint256 lpAmount_) {
        Auctions.revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        collateralAmount_ = Maths.wad(noOfNFTsToRemove_);
        lpAmount_ = LenderActions.removeCollateral(
            buckets,
            deposits,
            collateralAmount_,
            index_
        );

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        emit RemoveCollateral(msg.sender, index_, noOfNFTsToRemove_, lpAmount_);
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
        PoolState memory poolState = _accruePoolInterest();
        Borrower  memory borrower  = Loans.getBorrowerInfo(loans, borrowerAddress_);
        // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral();

        TakeParams memory params = TakeParams(
            {
                borrower:       borrowerAddress_,
                collateral:     borrower.collateral,
                t0Debt:         borrower.t0Debt,
                takeCollateral: Maths.wad(collateral_),
                inflator:       poolState.inflator
            }
        );

        TakeLocalVars memory vars;
        (
            vars.collateralAmount,
            vars.quoteTokenAmount,
            vars.t0RepayAmount,
            borrower.t0Debt,
            vars.t0DebtPenalty,
            vars.auctionPrice
        ) = Auctions.take(
            auctions,
            params
        );

        // slither-disable-next-line divide-before-multiply
        vars.collateralTaken = (vars.collateralAmount / 1e18) * 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2
        if (vars.collateralTaken != vars.collateralAmount && borrower.collateral >= vars.collateralTaken + 1e18) { // collateral taken not a round number
            vars.collateralTaken += 1e18; // round up collateral to take
            // taker should send additional quote tokens to cover difference between collateral needed to be taken and rounded collateral, at auction price
            // borrower will get quote tokens for the difference between rounded collateral and collateral taken to cover debt
            vars.excessQuoteToken = Maths.wmul(vars.collateralTaken - vars.collateralAmount, vars.auctionPrice);
        }

        // transfer rounded collateral from pool to taker
        vars.tokensTaken = _transferFromPoolToAddress(
            callee_,
            borrowerTokenIds[params.borrower],
            vars.collateralTaken / 1e18
        );

        if (data_.length != 0) {
            IERC721Taker(callee_).atomicSwapCallback(
                vars.tokensTaken,
                vars.quoteTokenAmount / _getArgUint256(QUOTE_SCALE), 
                data_
            );
        }

        // transfer from taker to pool the amount of quote tokens needed to cover collateral auctioned (including excess for rounded collateral)
        _transferQuoteTokenFrom(callee_, vars.quoteTokenAmount + vars.excessQuoteToken);

        // transfer from pool to borrower the excess of quote tokens after rounding collateral auctioned
        if (vars.excessQuoteToken != 0) _transferQuoteToken(params.borrower, vars.excessQuoteToken);

        _takeFromLoan(poolState, borrower, params.borrower, vars.collateralTaken, vars.t0RepayAmount, vars.t0DebtPenalty);
    }


    /*******************************/
    /*** Pool Override Functions ***/
    /*******************************/

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
        bool subset = _getArgUint256(SUBSET) != 0;
        uint8 nftType = _getArgUint8(NFT_TYPE);
        for (uint256 i = 0; i < tokenIds_.length;) {
            uint256 tokenId = tokenIds_[i];
            if (subset && !tokenIdsAllowed[tokenId]) revert OnlySubset();
            poolTokens_.push(tokenId);
            
            if (nftType == uint8(NFTTypes.STANDARD_ERC721)){
                _transferNFT(msg.sender, address(this), tokenId);
            }
            else if (nftType == uint8(NFTTypes.CRYPTOKITTIES)) {
                ICryptoKitties(_getArgAddress(COLLATERAL_ADDRESS)).transferFrom(msg.sender ,address(this), tokenId);
            }
            else{
                ICryptoPunks(_getArgAddress(COLLATERAL_ADDRESS)).buyPunk(tokenId);
            }

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
        uint8 nftType = _getArgUint8(NFT_TYPE);
        for (uint256 i = 0; i < amountToRemove_;) {
            uint256 tokenId = poolTokens_[--noOfNFTsInPool]; // start with transferring the last token added in bucket
            poolTokens_.pop();

            if (nftType == uint8(NFTTypes.STANDARD_ERC721)){
                _transferNFT(address(this), toAddress_, tokenId);
            }
            else if (nftType == uint8(NFTTypes.CRYPTOKITTIES)) {
                ICryptoKitties(_getArgAddress(COLLATERAL_ADDRESS)).transfer(toAddress_, tokenId);
            }
            else{
                ICryptoPunks(_getArgAddress(COLLATERAL_ADDRESS)).transferPunk(toAddress_, tokenId);
            }

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
        // slither-disable-next-line calls-loop
        IERC721Token(_getArgAddress(COLLATERAL_ADDRESS)).safeTransferFrom(from_, to_, tokenId_);
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
