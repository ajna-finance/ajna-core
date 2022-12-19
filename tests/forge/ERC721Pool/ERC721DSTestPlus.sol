// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { DSTestPlus }                from '../utils/DSTestPlus.sol';
import { NFTCollateralToken, Token } from '../utils/Tokens.sol';

import { ERC721Pool }        from 'src/erc721/ERC721Pool.sol';
import { ERC721PoolFactory } from 'src/erc721/ERC721PoolFactory.sol';
import { IERC721PoolEvents } from 'src/erc721/interfaces/pool/IERC721PoolEvents.sol';

import 'src/erc721/interfaces/IERC721Pool.sol';
import 'src/base/interfaces/IPoolFactory.sol';
import 'src/base/interfaces/IPool.sol';
import 'src/base/PoolInfoUtils.sol';

import 'src/libraries/Maths.sol';

abstract contract ERC721DSTestPlus is DSTestPlus, IERC721PoolEvents {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    
    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    ERC20              internal _ajnaToken;

    mapping(address => EnumerableSet.UintSet) borrowerPlegedNFTIds;
    mapping(uint256 => uint256) NFTidToIndex;

    mapping(address => EnumerableSet.UintSet) bidderDepositedIndex;
    EnumerableSet.AddressSet bidders;

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
        (uint256 poolInflatorSnapshot, uint256 lastInflatorSnapshotUpdate) = _pool.inflatorInfo();

        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 factor = PoolCommons.pendingInterestFactor(interestRate, block.timestamp - lastInflatorSnapshotUpdate);

        // Calculate current debt of borrower (currentPoolInflator * borrowerT0Debt)
        uint256 currentDebt = Maths.wmul(Maths.wmul(poolInflatorSnapshot, factor), borrowerT0debt);

        // mint quote tokens to borrower address equivalent to the current debt
        deal(_pool.quoteTokenAddress(), borrower, currentDebt);
        Token(_pool.quoteTokenAddress()).approve(address(_pool) , currentDebt);

        // repay current debt and pull all collateral
        _repayDebtNoLupCheck(borrower, borrower, currentDebt, currentDebt, borrowerPlegedNFTIds[borrower].length());

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
        for(uint256 j = 0; j < indexes.length(); j++){
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
            uint256 noOfBucketNftsRedeemable = Maths.wadToIntRoundingDown(bucketCollateral);

            // Calculating redeemable Quote and Collateral Token for Lenders lps
            uint256 lpsAsCollateral = _poolUtils.lpsToCollateral(address(_pool), lenderLpBalance, bucketIndex);

            // Deposit additional quote token to redeem for all NFTs
            uint256 lpsRedeemed;
            if (bucketCollateral != 0) {
                if (lpsAsCollateral % 1e18 != 0) {
                    uint256 depositRequired;
                    {
                        uint256 fractionOfNftRemaining = lpsAsCollateral % 1e18;
                        assertLt(fractionOfNftRemaining, 1e18);
                        // TODO: eliminate the 1 wei workaround for rounding error
                        depositRequired = Maths.wmul(1e18 - fractionOfNftRemaining + 1, price);
                    }
                    deal(_pool.quoteTokenAddress(), lender, depositRequired);
                    Token(_pool.quoteTokenAddress()).approve(address(_pool) , depositRequired);
                    _pool.addQuoteToken(depositRequired, bucketIndex);
                    (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
                    lpsAsCollateral = _poolUtils.lpsToCollateral(address(_pool), lenderLpBalance, bucketIndex);
                }

                // First redeem LP for collateral
                uint256 noOfNftsToRemove = Maths.min(Maths.wadToIntRoundingDown(lpsAsCollateral), noOfBucketNftsRedeemable);
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
        for(uint256 i = 0; i < buckets.length() ; i++){
            uint256 bucketIndex = buckets.at(i);
            (, uint256 quoteTokens, uint256 collateral, uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // Checking if all bucket lps are redeemed
            assertEq(bucketLps, 0);
            assertEq(quoteTokens, 0);
            assertEq(collateral, 0);
        }
        ( , uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        (uint256 debt, , ) = _pool.debtInfo();
        assertEq(debt, 0);
        assertEq(loansCount, 0);
        assertEq(_pool.pledgedCollateral(), 0);
    }

    modifier tearDown {
        _;
        for(uint i = 0; i < borrowers.length(); i++ ){
            repayDebt(borrowers.at(i));
        }

        for(uint i = 0; i < lenders.length(); i++ ){
            redeemLenderLps(lenders.at(i),lendersDepositedIndex[lenders.at(i)]);
        }
        
        for(uint256 i = 0; i < bidders.length(); i++){
            redeemLenderLps(bidders.at(i), bidderDepositedIndex[bidders.at(i)]);
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

        lps_ = ERC721Pool(address(_pool)).addCollateral(tokenIds, index);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));  // token is owned by pool after add
        }

        // Add for tearDown
        bidders.add(from);
        bidderDepositedIndex[from].add(index);
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
        _assertTokenTransferEvent(address(_pool), from, amount);

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

        vm.expectEmit(true, true, false, true);
        emit DrawDebtNFT(borrower, amountToBorrow, tokenIds, newLup);

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
            _assertTokenTransferEvent(address(_pool), from, amountToBorrow);
        }

        ERC721Pool(address(_pool)).drawDebt(borrower, amountToBorrow, limitIndex, tokenIds);

        // check tokenIds were transferred to the pool
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));
        }

        // Add for tearDown
        borrowers.add(borrower);
        for (uint256 i=0; i < tokenIds.length; i++) {
            borrowerPlegedNFTIds[borrower].add(tokenIds[i]);
        }
    }

    function _drawDebtNoCheckLup(
        address from,
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);

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
            _assertTokenTransferEvent(address(_pool), from, amountToBorrow);
        }

        ERC721Pool(address(_pool)).drawDebt(borrower, amountToBorrow, limitIndex, tokenIds);

        // check tokenIds were transferred to the pool
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));
        }

        // Add for tearDown
        borrowers.add(borrower);
        for (uint256 i=0; i < tokenIds.length; i++) {
            borrowerPlegedNFTIds[borrower].add(tokenIds[i]);
        }
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
        for (uint256 i=0; i < tokenIds.length; i++) {
            borrowerPlegedNFTIds[borrower].add(tokenIds[i]);
        }
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
            _assertTokenTransferEvent(from, address(_pool), amountRepaid);
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

            vm.expectEmit(true, true, false, true);
            emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull);

            // post pull checks
            if (collateralToPull != 0) {
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    assertEq(_collateral.ownerOf(tokenIds[i]), address(from)); // token is owned by borrower after pull
                }

                // Add for tearDown
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    borrowerPlegedNFTIds[from].remove(tokenIds[i]);
                }
            }
        }
        else {
            // only repay, don't pull collateral
            vm.expectEmit(true, true, false, true);
            emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull);
        }
    }

    function _repayDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull
    ) internal {
        changePrank(from);
        // repay checks
        if (amountToRepay != 0) {
            _assertTokenTransferEvent(from, address(_pool), amountRepaid);
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

            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull);

            // post pull checks
            if (collateralToPull != 0) {
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    assertEq(_collateral.ownerOf(tokenIds[i]), address(from)); // token is owned by borrower after pull
                }
 
                // Add for tearDown
                for (uint256 i = 0; i < tokenIds.length; i++) {
                    borrowerPlegedNFTIds[from].remove(tokenIds[i]);
                }
            }
        }
        else {
            // only repay, don't pull collateral
            ERC721Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull);
        }
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

        for (uint256 i = 0; i < tokenIds.length; i++) {
            borrowerPlegedNFTIds[borrower].remove(tokenIds[i]); // for tearDown, remove NFTs taken from borrower pledged NFTs
        }
    }
 
    function _mergeOrRemoveCollateral(
        address from,
        uint256 toIndex,
        uint256 noOfNFTsToRemove,
        uint256[] memory removeCollateralAtIndex,
        uint256 collateralMerged,
        uint256 toIndexLps
    ) internal virtual {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit MergeOrRemoveCollateralNFT(from, collateralMerged, toIndexLps);
        ERC721Pool(address(_pool)).mergeOrRemoveCollateral(removeCollateralAtIndex, noOfNFTsToRemove, toIndex);
    }

    /**********************/
    /*** Revert asserts ***/
    /**********************/

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
        vm.expectRevert(IPoolErrors.LimitIndexReached.selector);
        uint256[] memory emptyArray;
        ERC721Pool(address(_pool)).drawDebt(from, amount, indexLimit, emptyArray);
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
        ERC721Pool(address(_pool)).repayDebt(from, 0, amount);
    }

    function _assertRepayNoDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoDebt.selector);
        ERC721Pool(address(_pool)).repayDebt(borrower, amount, 0);
    }

    function _assertRepayMinDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        ERC721Pool(address(_pool)).repayDebt(borrower, amount, 0);
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

    function _assertRemoveCollateralInsufficientLPsRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLPs.selector);
        _pool.removeCollateral(amount, index);
    }
}

abstract contract ERC721HelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _collateral = new NFTCollateralToken();
        vm.makePersistent(address(_collateral));
        _quote      = new Token("Quote", "Q");
        vm.makePersistent(address(_quote));
        _ajnaToken  = ERC20(_ajna);
        vm.makePersistent(_ajna);
        _poolUtils  = new PoolInfoUtils();
        vm.makePersistent(address(_poolUtils));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        uint256[] memory tokenIds;
        address contractAddress = new ERC721PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        return ERC721Pool(contractAddress);
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        return ERC721Pool(new ERC721PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
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
}
