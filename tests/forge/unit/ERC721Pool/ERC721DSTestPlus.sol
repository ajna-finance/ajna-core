// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { DSTestPlus }        from '../../utils/DSTestPlus.sol';
import { NFTCollateralToken, Token, TokenWithNDecimals } from '../../utils/Tokens.sol';

import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { IERC721PoolEvents } from 'src/interfaces/pool/erc721/IERC721PoolEvents.sol';

import 'src/interfaces/pool/erc721/IERC721Pool.sol';
import 'src/interfaces/pool/IPoolFactory.sol';
import 'src/interfaces/pool/IPool.sol';
import 'src/PoolInfoUtils.sol';

import 'src/libraries/internal/Maths.sol';

abstract contract ERC721DSTestPlus is DSTestPlus, IERC721PoolEvents {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    
    NFTCollateralToken internal _collateral;
    TokenWithNDecimals internal _quote;
    ERC20              internal _ajnaToken;

    mapping(uint256 => uint256) NFTidToIndex;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /*****************/
    /*** Utilities ***/
    /*****************/

    function repayDebt(
        address borrower
    ) internal {
        changePrank(borrower);
        uint256 borrowerT0debt;
        uint256 borrowerCollateral;
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);

        // calculate current pool Inflator
        (uint256 poolInflator, uint256 lastInflatorUpdate) = _pool.inflatorInfo();

        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 factor = PoolCommons.pendingInterestFactor(interestRate, block.timestamp - lastInflatorUpdate);

        // Calculate current debt of borrower (currentPoolInflator * borrowerT0Debt)
        uint256 currentDebt = Maths.wmul(Maths.wmul(poolInflator, factor), borrowerT0debt);

        // mint quote tokens to borrower address equivalent to the current debt
        deal(_pool.quoteTokenAddress(), borrower, currentDebt);
        Token(_pool.quoteTokenAddress()).approve(address(_pool) , currentDebt);

        // repay current debt and pull all collateral
        uint256 noOfNfts = borrowerCollateral / 1e18; // round down to pull correct num of NFTs
        if (currentDebt != 0 || noOfNfts != 0) {
            _repayDebtNoLupCheck(borrower, borrower, currentDebt, currentDebt, noOfNfts);
        }

        // check borrower state after repay of loan and pull Nfts
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);
        assertEq(borrowerT0debt,     0);
        assertEq(borrowerCollateral, 0);
    }

    function redeemLenderLps(
        address lender,
        EnumerableSet.UintSet storage indexes
    ) internal {
        changePrank(lender);

        // Redeem all lps of lender from all buckets as quote token and collateral token
        for (uint256 j = 0; j < indexes.length(); j++) {
            uint256 lenderLpBalance;
            uint256 bucketIndex = indexes.at(j);
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
            if (lenderLpBalance == 0) continue;

            // Calculating redeemable Quote and Collateral Token in particular bucket
            (uint256 price, , uint256 bucketCollateral, , , ) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // If bucket has a fractional amount of NFTs, we'll need to defragment collateral across buckets
            if (bucketCollateral % 1e18 != 0) {
                revert("Collateral needs to be reconstituted from other buckets");
            }
            uint256 noOfBucketNftsRedeemable = _wadToIntRoundingDown(bucketCollateral);

            // Calculating redeemable Quote and Collateral Token for Lenders lps
            uint256 lpsAsCollateral = _poolUtils.lpToCollateral(address(_pool), lenderLpBalance, bucketIndex);

            // Deposit additional quote token to redeem for all NFTs
            uint256 lpsRedeemed;
            if (bucketCollateral != 0) {
                if (lpsAsCollateral % 1e18 != 0) {
                    uint256 depositRequired;
                    {
                        uint256 fractionOfNftRemaining = lpsAsCollateral % 1e18;
                        assertLt(fractionOfNftRemaining, 1e18);

                        depositRequired = Maths.wmul(1e18 - fractionOfNftRemaining, price);
                    }
                    deal(_pool.quoteTokenAddress(), lender, depositRequired);
                    Token(_pool.quoteTokenAddress()).approve(address(_pool) , depositRequired);
                    _pool.addQuoteToken(depositRequired, bucketIndex, block.timestamp + 1 minutes);
                    (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
                    lpsAsCollateral = _poolUtils.lpToCollateral(address(_pool), lenderLpBalance, bucketIndex);
                }

                // First redeem LP for collateral
                uint256 noOfNftsToRemove = Maths.min(_wadToIntRoundingDown(lpsAsCollateral), noOfBucketNftsRedeemable);
                (, lpsRedeemed) = _pool.removeCollateral(noOfNftsToRemove, bucketIndex);
            }

            // Then redeem LP for quote token
            (, lpsRedeemed) = _pool.removeQuoteToken(type(uint256).max, bucketIndex);
        
            // Confirm all lp balance has been redeemed            
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
        }
    }

    function validateEmpty(
        EnumerableSet.UintSet storage buckets
    ) internal {
        for (uint256 i = 0; i < buckets.length() ; i++) {
            uint256 bucketIndex = buckets.at(i);
            (, uint256 quoteTokens, uint256 collateral, uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // Checking if all bucket lps are redeemed
            assertEq(bucketLps, 0);
            assertEq(quoteTokens, 0);
            assertEq(collateral, 0);
        }
        ( , uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        (uint256 debt, , ,) = _pool.debtInfo();
        assertEq(debt, 0);
        assertEq(loansCount, 0);
        assertEq(_pool.pledgedCollateral(), 0);
    }

    modifier tearDown {
        _;
        for (uint i = 0; i < borrowers.length(); i++) {
            repayDebt(borrowers.at(i));
        }

        for (uint i = 0; i < lenders.length(); i++) {
            redeemLenderLps(lenders.at(i), lendersDepositedIndex[lenders.at(i)]);
        }
        
        validateEmpty(bucketsUsed);
    }

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _addCollateral(
        address from,
        uint256[] memory tokenIds,
        uint256 index,
        uint256 lpAward
    ) internal returns (uint256 lps_){
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(from, index, tokenIds, lpAward);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by borrower
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), tokenIds[i]);
        }

        lps_ = ERC721Pool(address(_pool)).addCollateral(tokenIds, index, block.timestamp + 10 minutes);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));  // token is owned by pool after add
        }

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index); 
    }

    function _borrow(
        address from,
        uint256 amount,
        uint256 indexLimit,
        uint256 newLup
    ) internal {
        changePrank(from);

        uint256[] memory emptyArray;

        vm.expectEmit(true, true, false, true);
        emit DrawDebtNFT(from, amount, emptyArray, newLup);
        _assertQuoteTokenTransferEvent(address(_pool), from, amount);

        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);

        // Add for tearDown
        borrowers.add(from);
    }

    function _drawDebt(
        address from,
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256[] memory tokenIds,
        uint256 newLup
    ) internal {
        changePrank(from);

        if (newLup != 0) {
            vm.expectEmit(true, true, false, true);
            emit DrawDebtNFT(borrower, amountToBorrow, tokenIds, newLup);
        }

        // pledge collateral
        if (tokenIds.length != 0) {
            for (uint256 i = 0; i < tokenIds.length; i++) {
                assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by pledger address
                vm.expectEmit(true, true, false, true);
                emit Transfer(from, address(_pool), tokenIds[i]);
            }
        }

        // borrow quote
        if (amountToBorrow != 0) {
            _assertQuoteTokenTransferEvent(address(_pool), from, amountToBorrow);
        }

        ERC721Pool(address(_pool)).drawDebt(borrower, amountToBorrow, limitIndex, tokenIds);

        // check tokenIds were transferred to the pool
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));
        }

        // Add for tearDown
        borrowers.add(borrower);
    }

    function _drawDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256[] memory tokenIds
    ) internal {
        _drawDebt(from, borrower, amountToBorrow, limitIndex, tokenIds, 0);
    }

    function _pledgeCollateral(
        address from,
        address borrower,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);

        vm.expectEmit(true, true, false, true);
        emit DrawDebtNFT(borrower, 0, tokenIds, _poolUtils.lup(address(_pool)));

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by pledger address
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), tokenIds[i]);
        }

        ERC721Pool(address(_pool)).drawDebt(borrower, 0, 0, tokenIds);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));
        }

        // Add for tearDown
        borrowers.add(borrower);
    }

    function _removeCollateral(
        address from,
        uint256 amount,
        uint256 index,
        uint256 lpRedeem
    ) internal override returns (uint256 lpRedeemed_) {
        uint256[] memory tokenIds = new uint256[](amount);
        (, uint256 noOfTokens, , , ) = _pool.bucketInfo(index);
        noOfTokens = noOfTokens / 1e18;
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = ERC721Pool(address(_pool)).bucketTokenIds(--noOfTokens);
            assertEq(_collateral.ownerOf(tokenId), address(_pool)); // token is owned by pool
            tokenIds[i] = tokenId;
        }

        lpRedeemed_ = super._removeCollateral(from, amount, index, lpRedeem);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by lender address after remove
        }
    }

    function _repayDebt(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull,
        uint256 newLup
    ) internal {
        changePrank(from);

        // repay checks
        if (amountToRepay != 0) {
            _assertQuoteTokenTransferEvent(from, address(_pool), amountRepaid);
        }

        // pre pull checks
        if (collateralToPull != 0) {
            uint256[] memory tokenIds = new uint256[](collateralToPull);
            (, uint256 noOfTokens, ) = _pool.borrowerInfo(from);
            noOfTokens = noOfTokens / 1e18;
            for (uint256 i = 0; i < collateralToPull; i++) {
                uint256 tokenId = ERC721Pool(address(_pool)).borrowerTokenIds(from, --noOfTokens);
                assertEq(_collateral.ownerOf(tokenId), address(_pool)); // token is owned by pool
                tokenIds[i] = tokenId;
            }

            if (newLup != 0) {
                vm.expectEmit(true, true, false, true);
                emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
            }

            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull, borrower, MAX_FENWICK_INDEX);

            // post pull checks
            if (collateralToPull != 0) {
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    assertEq(_collateral.ownerOf(tokenIds[i]), address(from)); // token is owned by borrower after pull
                }
            }
        }
        else {
            // only repay, don't pull collateral
            if (newLup != 0) {
                vm.expectEmit(true, true, false, true);
                emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
            }

            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull, borrower, MAX_FENWICK_INDEX);
        }
    }

    function _repayDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull
    ) internal {
        _repayDebt(from, borrower, amountToRepay, amountRepaid, collateralToPull, 0);
    }

    function _take(
        address from,
        address borrower,
        uint256 maxCollateral,
        uint256 bondChange,
        uint256 givenAmount,
        uint256 collateralTaken,
        bool isReward
    ) internal override {
        (, uint256 noOfTokens, ) = _pool.borrowerInfo(borrower);
        noOfTokens = noOfTokens / 1e18;
        if (maxCollateral < noOfTokens) noOfTokens = maxCollateral;
        uint256[] memory tokenIds = new uint256[](noOfTokens);
        for (uint256 i = 0; i < noOfTokens + 1; i++) {
            uint256 tokenId = ERC721Pool(address(_pool)).borrowerTokenIds(borrower, --noOfTokens);
            assertEq(_collateral.ownerOf(tokenId), address(_pool)); // token is owned by pool before take
            tokenIds[i] = tokenId;
        }

        super._take(from, borrower, maxCollateral, bondChange, givenAmount, collateralTaken, isReward);
    }
 
    function _mergeOrRemoveCollateral(
        address from,
        uint256 toIndex,
        uint256 noOfNFTsToRemove,
        uint256[] memory removeCollateralAtIndex,
        uint256 collateralMerged,
        uint256 toIndexLps
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit MergeOrRemoveCollateralNFT(from, collateralMerged, toIndexLps);
        ERC721Pool(address(_pool)).mergeOrRemoveCollateral(removeCollateralAtIndex, noOfNFTsToRemove, toIndex);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(toIndex);
        bucketsUsed.add(toIndex);
    }

    function _assertBorrower(
        address borrower,
        uint256 borrowerDebt,
        uint256 borrowerCollateral,
        uint256 borrowert0Np,
        uint256 borrowerCollateralization,
        uint256[] memory tokenIds
    ) internal {
        _assertBorrower(
            borrower, 
            borrowerDebt,
            borrowerCollateral,
            borrowert0Np,
            borrowerCollateralization
        );

        uint256 nftCollateral = borrowerCollateral / 1e18; // solidity rounds down, so if 2.5 it will be 2.5 / 1 = 2
        if (nftCollateral != tokenIds.length) revert("ASRT_BORROWER: incorrect number of NFT tokenIds");
        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(borrower, i), tokenIds[i]);
        }
    }

    function _assertCollateralInvariants() internal {
        uint256 collateralInBuckets;
        for (uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateralInBuckets += bucketCollateral;
        }

        uint256 borrowersCollateral;
        for (uint256 i = 0; i < borrowers.length(); i++) {
            (, uint256 borrowerCollateral, ) = _poolUtils.borrowerInfo(address(_pool), borrowers.at(i));
            borrowersCollateral += borrowerCollateral;
        }

        // pool pledged collateral accumulator should be equal with the amounts of collateral owned by borrowers
        assertEq(borrowersCollateral, _pool.pledgedCollateral());

        // collateral in buckets + collateral owned borrowers should be equal with the total number of tokens owned by the pool
        uint256 poolBalance = _collateral.balanceOf(address(_pool));
        assertEq(collateralInBuckets + borrowersCollateral, poolBalance * 1e18);
    }

    /**********************/
    /*** Revert asserts ***/
    /**********************/

    function _assertAddCollateralExpiredRevert(
        address from,
        uint256[] memory tokenIds,
        uint256 index,
        uint256 expiry
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.TransactionExpired.selector);
        ERC721Pool(address(_pool)).addCollateral(tokenIds, index, expiry);
    }

    function _assertDeployWith0xAddressRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        uint256[] memory tokenIds;
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        ERC721PoolFactory(poolFactory).deployPool(collateral, quote, tokenIds, interestRate);
    }

    function _assertDeployWithInvalidRateRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        uint256[] memory tokenIds;
        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        ERC721PoolFactory(poolFactory).deployPool(collateral, quote, tokenIds, interestRate);
    }

    function _assertDeployWithNonNFTRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        uint256[] memory tokenIds;
        vm.expectRevert(abi.encodeWithSignature('NFTNotSupported()'));
        ERC721PoolFactory(poolFactory).deployPool(collateral, quote, tokenIds, interestRate);
    }

    function _assertDeployMultipleTimesRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        uint256[] memory tokenIds;
        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        ERC721PoolFactory(poolFactory).deployPool(collateral, quote, tokenIds, interestRate);
    }

    function _assertPledgeCollateralNotInSubsetRevert(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectRevert(IERC721PoolErrors.OnlySubset.selector);
        ERC721Pool(address(_pool)).drawDebt(from, 0, 0, tokenIds);        
    }

    function _assertBorrowAuctionActiveRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionActive()'));
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);        
    }

    function _assertBorrowLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);
    }

    function _assertMergeRemoveCollateralAuctionNotClearedRevert(
        address from,
        uint256 toIndex,
        uint256 noOfNFTsToRemove,
        uint256[] memory removeCollateralAtIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        ERC721Pool(address(_pool)).mergeOrRemoveCollateral(removeCollateralAtIndex, noOfNFTsToRemove, toIndex);
    }

    function _assertCannotMergeToHigherPriceRevert(
        address from,
        uint256 toIndex,
        uint256 noOfNFTsToRemove,
        uint256[] memory removeCollateralAtIndex
    ) internal virtual {
        changePrank(from);
        vm.expectRevert(IPoolErrors.CannotMergeToHigherPrice.selector);
        ERC721Pool(address(_pool)).mergeOrRemoveCollateral(removeCollateralAtIndex, noOfNFTsToRemove, toIndex);
    }

    function _assertBorrowBorrowerUnderCollateralizedRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerUnderCollateralized.selector);
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);        
    }

    function _assertBorrowDustRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);
    }

    function _assertBorrowMinDebtRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);
    }

    function _assertPullInsufficientCollateralRevert(
        address from,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC721Pool(address(_pool)).repayDebt(from, 0, amount, from, MAX_FENWICK_INDEX);
    }

    function _assertPullLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        ERC721Pool(address(_pool)).repayDebt(from, 0, amount, from, indexLimit);
    }

    function _assertRepayNoDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoDebt.selector);
        ERC721Pool(address(_pool)).repayDebt(borrower, amount, 0, borrower, MAX_FENWICK_INDEX);
    }

    function _assertRepayMinDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        ERC721Pool(address(_pool)).repayDebt(borrower, amount, 0, borrower, MAX_FENWICK_INDEX);
    }

    function _assertRemoveCollateralNoClaimRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        ERC721Pool(address(_pool)).removeCollateral(amount, index);
    }

    function _assertRemoveCollateralInsufficientLPRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLP.selector);
        _pool.removeCollateral(amount, index);
    }
}

abstract contract ERC721HelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    ERC721PoolFactory internal _poolFactory;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _collateral = new NFTCollateralToken();
        vm.makePersistent(address(_collateral));
        _quote      = new TokenWithNDecimals("Quote", "Q", 18);
        vm.makePersistent(address(_quote));
        _ajnaToken  = ERC20(_ajna);
        vm.makePersistent(_ajna);
        _poolUtils  = new PoolInfoUtils();
        vm.makePersistent(address(_poolUtils));
        _poolFactory = new ERC721PoolFactory(_ajna);
        vm.makePersistent(address(_poolFactory));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        uint256[] memory tokenIds;
        address contractAddress = _poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        return ERC721Pool(contractAddress);
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        return ERC721Pool(_poolFactory.deployPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
    }

    function _mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
    }

    function _mintAndApproveCollateralTokens(address operator_, uint256 mintAmount_) internal {
        _collateral.mint(operator_, mintAmount_);
        vm.prank(operator_);
        _collateral.setApprovalForAll(address(_pool), true);
    }

    function _mintAndApproveAjnaTokens(address operator_, uint256 mintAmount_) internal {
        deal(_ajna, operator_, mintAmount_);
        vm.prank(operator_);
        _ajnaToken.approve(address(_pool), type(uint256).max);
    }

    function _approveAndRepayDebt(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull,
        uint256 newLup
    ) internal {
        changePrank(from);
        _quote.approve(address(_pool), amountToRepay);
        _repayDebt(from, borrower, amountToRepay, amountRepaid, collateralToPull, newLup);
    }

    function _approveAndRepayDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull
    ) internal {
        changePrank(from);
        _quote.approve(address(_pool), amountToRepay);
        _repayDebtNoLupCheck(from, borrower, amountToRepay, amountRepaid, collateralToPull);
    }
}

abstract contract ERC721NDecimalsHelperContract is ERC721DSTestPlus {
    using EnumerableSet for EnumerableSet.AddressSet;
    ERC721PoolFactory internal _poolFactory;

    constructor(uint8 decimals) {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _collateral = new NFTCollateralToken();
        vm.makePersistent(address(_collateral));
        _quote      = new TokenWithNDecimals("Quote", "Q", decimals);
        vm.makePersistent(address(_quote));
        _ajnaToken  = ERC20(_ajna);
        vm.makePersistent(_ajna);
        _poolUtils  = new PoolInfoUtils();
        vm.makePersistent(address(_poolUtils));
        _poolFactory = new ERC721PoolFactory(_ajna);
        vm.makePersistent(address(_poolFactory));

        _startTime = block.timestamp;
        uint256[] memory tokenIds;
        address contractAddress = _poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        _pool = ERC721Pool(contractAddress);
    }

    function _mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
    }

    function _mintAndApproveCollateralTokens(address operator_, uint256 mintAmount_) internal {
        _collateral.mint(operator_, mintAmount_);
        vm.prank(operator_);
        _collateral.setApprovalForAll(address(_pool), true);
    }

    /**
     *  @dev Creates debt for an anonymous non-player borrower not otherwise involved in the test.
     **/
    function _anonBorrowerDrawsDebt(uint256 loanAmount) internal {
        // _anonBorrowerCount += 1;
        
        address borrower = makeAddr(string(abi.encodePacked("anonBorrower", borrowers.length())));
        vm.stopPrank();
        _mintAndApproveCollateralTokens(borrower, 1);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = _collateral.totalSupply();

        _drawDebtNoLupCheck({
            from:           borrower,
            borrower:       borrower,
            amountToBorrow: loanAmount,
            limitIndex:     MAX_FENWICK_INDEX,
            tokenIds:       tokenIdsToAdd
        });
    }
}

abstract contract ERC721FuzzyHelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    ERC721PoolFactory internal _poolFactory;

    constructor() {
        _collateral = new NFTCollateralToken();
        _quote      = new TokenWithNDecimals("Quote", "Q", 18);
        _ajnaToken  = ERC20(_ajna);
        _poolUtils  = new PoolInfoUtils();
        _poolFactory = new ERC721PoolFactory(_ajna);
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        uint256[] memory tokenIds;
        address contractAddress = _poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        return ERC721Pool(contractAddress);
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        return ERC721Pool(_poolFactory.deployPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
    }

    function _mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
    }

    function _mintAndApproveCollateralTokens(address operator_, uint256 mintAmount_) internal {
        _collateral.mint(operator_, mintAmount_);
        vm.prank(operator_);
        _collateral.setApprovalForAll(address(_pool), true);
    }

    function _mintAndApproveAjnaTokens(address operator_, uint256 mintAmount_) internal {
        deal(_ajna, operator_, mintAmount_);
        vm.prank(operator_);
        _ajnaToken.approve(address(_pool), type(uint256).max);
    }

    // create an array of NFT's to add to a pool based upon the number of NFT's required for collateralization
    function _NFTTokenIdsToAdd(address borrower_, uint256 requiredCollateral_) internal returns (uint256[] memory tokenIds_) {
        changePrank(borrower_);
        tokenIds_ = new uint256[](requiredCollateral_);
        for (uint i = 0; i < requiredCollateral_; ++i) {
            vm.stopPrank();
            _mintAndApproveCollateralTokens(borrower_, 1);
            tokenIds_[i] = _collateral.totalSupply();
        }
    }

    function _requiredCollateralNFT(uint256 borrowAmount, uint256 indexPrice) internal view returns (uint256 requiredCollateral_) {
        // calculate the required collateral based upon the borrow amount and index price
        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 newInterestRate = Maths.wmul(interestRate, 1.1 * 10**18); // interest rate multipled by increase coefficient
        uint256 expectedDebt = Maths.wmul(borrowAmount, _borrowFeeRate(newInterestRate) + Maths.WAD);

        // get an integer amount rounding up
        requiredCollateral_ = 1 + Maths.wdiv(expectedDebt, _poolUtils.indexToPrice(indexPrice)) / 1e18;
    }

}

    /**
     * @notice Convert a WAD to an integer, rounding down
     */
    function _wadToIntRoundingDown(uint256 a) pure returns (uint256) {
        return Maths.wdiv(a, 10 ** 18) / 10 ** 18;
    }
