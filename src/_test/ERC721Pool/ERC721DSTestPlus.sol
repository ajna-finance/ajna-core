// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import { DSTestPlus }                from '../utils/DSTestPlus.sol';
import { NFTCollateralToken, Token } from '../utils/Tokens.sol';

import { ERC721Pool }        from '../../erc721/ERC721Pool.sol';
import { ERC721PoolFactory } from '../../erc721/ERC721PoolFactory.sol';

import '../../erc721/interfaces/IERC721Pool.sol';
import '../../base/interfaces/IPoolFactory.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

abstract contract ERC721DSTestPlus is DSTestPlus {
    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    ERC20              internal _ajna;

    // Pool events
    event AddCollateralNFT(address indexed actor_, uint256 indexed price_, uint256[] tokenIds_);
    event PledgeCollateralNFT(address indexed borrower_, uint256[] tokenIds_);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /*****************/
    /*** Utilities ***/
    /*****************/

    mapping(address => uint256[]) borrowerPlegedNFTIds;
    mapping(uint256 => uint256) NFTidToIndex;

    mapping(address => mapping(uint256 => uint256)) noOfBidderNftsOnIndex;
    mapping(address => uint256[]) bidderDepositedIndex;
    address[] bidders;
    mapping(address => bool) bidderExist;
    uint256[] totalNftIdsAddedByAllBidders;
    mapping(uint256 => uint256) indexOfNftIdsAddedByAllBidders;  

    function repayDebt(
        address borrower
    ) internal {
        changePrank(borrower);
        uint256 borrowerT0debt;
        uint256 borrowerCollateral;
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);

        // calculate current pool Inflator
        (uint256 poolInflatorSnapshot, uint256 lastInflatorSnapshotUpdate) = _pool.inflatorInfo();

        uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
        uint256 factor = PoolUtils.pendingInterestFactor(_pool.interestRate(), elapsed);

        uint256 currentPoolInflator = Maths.wmul(poolInflatorSnapshot, factor);

        // Calculate current debt of borrower
        uint256 currentDebt = Maths.wmul(currentPoolInflator, borrowerT0debt);

        // mint quote tokens to borrower address equivalent to the current debt
        deal(_pool.quoteTokenAddress(), borrower, currentDebt);
        Token(_pool.quoteTokenAddress()).approve(address(_pool) , currentDebt);

        // repay current debt ( all debt )
        if(currentDebt > 0){
            _pool.repay(borrower, currentDebt);
        }

        // pull borrower's Nfts
        ERC721Pool(address(_pool)).pullCollateral(borrowerPlegedNFTIds[borrower].length);

        // check borrower state after repay of loan and pull Nfts
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);
        assertEq(borrowerT0debt,     0);
        assertEq(borrowerCollateral, 0);
    }

    function redeemLenderLps(
        address lender,
        uint256[] memory indexes
    ) internal {
        changePrank(lender);
        // Redeem all lps of lender from all buckets as quote token and collateral token
        for(uint256 j = 0; j < indexes.length; j++){
            uint256 lenderLpBalance;
            uint256 bucketIndex = indexes[j];
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
            if(lenderLpBalance == 0) return;

            // Calculating redeemable Quote and Collateral Token in particular bucket
            (uint256 price, uint256 bucketQuoteToken, uint256 bucketCollateral, uint256 bucketLPs, , ) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // If bucket has a fractional amount of NFTs, we'll need to defragment collateral across buckets
            if (bucketCollateral % 1e18 != 0) {
                revert("Collateral needs to be reconstituted from other buckets");
            }
            uint256 noOfBucketNftsRedeemable = Maths.wadToIntRoundingDown(bucketCollateral);

            // Calculating redeemable Quote and Collateral Token for Lenders lps
            uint256 lpsAsCollateral = ERC721Pool(address(_pool)).lpsToCollateral(bucketQuoteToken, lenderLpBalance, bucketIndex);

            // Deposit additional quote token to redeem for all NFTs
            if (bucketCollateral != 0 && lpsAsCollateral % 1e18 != 0) {
                uint256 fractionOfNftRemaining = lpsAsCollateral % 1e18;
                assertLt(fractionOfNftRemaining, 1e18);
                uint256 depositRequired = Maths.wmul(1e18 - fractionOfNftRemaining, price);
                deal(_pool.quoteTokenAddress(), lender, depositRequired);
                Token(_pool.quoteTokenAddress()).approve(address(_pool) , depositRequired);
                _pool.addQuoteToken(depositRequired, bucketIndex);
                (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
                lpsAsCollateral = ERC721Pool(address(_pool)).lpsToCollateral(bucketQuoteToken + depositRequired, lenderLpBalance, bucketIndex);
            }

            // First redeem LP for collateral
            uint256 noOfNftsToRemove = Maths.min(Maths.wadToIntRoundingDown(lpsAsCollateral), noOfBucketNftsRedeemable);
            uint256 lpsRedeemed = _pool.removeCollateral(noOfNftsToRemove, bucketIndex);

            // Then redeem LP for quote token
            (, lpsRedeemed) = _pool.removeAllQuoteToken(bucketIndex);
        
            // Confirm all lp balance has been redeemed            
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
        }
    }

    function validateEmpty(
        uint256[] memory buckets
    ) internal {
        for(uint256 i = 0; i < buckets.length ; i++){
            uint256 bucketIndex = buckets[i];
            (, , , uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // Checking if all bucket lps are redeemed
            assertEq(bucketLps, 0 );
        }
    }

    modifier tearDown {
        _;
        for(uint i = 0; i < borrowers.length; i++ ){
            repayDebt(borrowers[i]);
        }

        for(uint i = 0; i < lenders.length; i++ ){
            redeemLenderLps(lenders[i],lendersDepositedIndex[lenders[i]]);
        }
        
        // for(uint256 i = 0; i < bidders.length; i++){
        //     redeemLenderLps(bidders[i] , bidderDepositedIndex[bidders[i]]);
        // }
        // validateEmpty(bucketsUsed);
    }

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _addCollateral(
        address from,
        uint256[] memory tokenIds,
        uint256 index
    ) internal returns (uint256 lps_){
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(from, index, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by borrower
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), i);
        }

        lps_ = ERC721Pool(address(_pool)).addCollateral(tokenIds, index);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));  // token is owned by pool after add
        }

        if(!bidderExist[from]){
            bidderExist[from] = true;
            bidders.push(from);
        }
        bidderDepositedIndex[from].push(index);
        uint256 totalNftsBefore = totalNftIdsAddedByAllBidders.length;
        for(uint256 i = 0; i < tokenIds.length; i++){
            indexOfNftIdsAddedByAllBidders[tokenIds[i]] = totalNftsBefore + i;
            totalNftIdsAddedByAllBidders.push(tokenIds[i]);
        }
        noOfBidderNftsOnIndex[from][index] += tokenIds.length;
        bucketsUsed.push(index); 
    }

    function _pledgeCollateral(
        address from,
        address borrower,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(borrower, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by pledger address
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), i);
        }

        ERC721Pool(address(_pool)).pledgeCollateral(borrower, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(_pool));
        }
        uint256 totalNftsBefore = borrowerPlegedNFTIds[borrower].length;
        for (uint256 i=0; i < tokenIds.length; i++) {
            NFTidToIndex[tokenIds[i]] = totalNftsBefore + i;
            borrowerPlegedNFTIds[borrower].push(tokenIds[i]);
        }
    }

    function _pullCollateral(
        address from,
        uint256 amount 
    ) internal override {
        uint256[] memory tokenIds = new uint256[](amount);
        (, uint256 noOfTokens, ) = _pool.borrowerInfo(from);
        noOfTokens = noOfTokens / 1e18;
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenId = ERC721Pool(address(_pool)).borrowerTokenIds(from, --noOfTokens);
            assertEq(_collateral.ownerOf(tokenId), address(_pool)); // token is owned by pool
            tokenIds[i] = tokenId;
        }

        super._pullCollateral(from, amount);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), address(from)); // token is owned by borrower after pull
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 index = NFTidToIndex[tokenIds[i]];
            if (borrowerPlegedNFTIds[from].length > 1) {
                borrowerPlegedNFTIds[from][index] = borrowerPlegedNFTIds[from][
                    borrowerPlegedNFTIds[from].length - 1
                ];
                NFTidToIndex[borrowerPlegedNFTIds[from][index]] = index;
            }
            borrowerPlegedNFTIds[from].pop();
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

        if(bidderExist[from]){
            noOfBidderNftsOnIndex[from][index] -= amount;
            for (uint256 i = 0; i < tokenIds.length; i++) {
                uint256 nftIndex = indexOfNftIdsAddedByAllBidders[tokenIds[i]];
                if (totalNftIdsAddedByAllBidders.length > 1) {
                    totalNftIdsAddedByAllBidders[nftIndex] = totalNftIdsAddedByAllBidders[
                        totalNftIdsAddedByAllBidders.length - 1
                    ];
                    indexOfNftIdsAddedByAllBidders[totalNftIdsAddedByAllBidders[nftIndex]] = nftIndex;
                }
                totalNftIdsAddedByAllBidders.pop();
            }
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
        (, uint256 noOfTokens, ) = _pool.borrowerInfo(from);
        noOfTokens = noOfTokens / 1e18;
        if (maxCollateral < noOfTokens) noOfTokens = maxCollateral;
        uint256[] memory tokenIds = new uint256[](noOfTokens);
        for (uint256 i = 0; i < noOfTokens; i++) {
            uint256 tokenId = ERC721Pool(address(_pool)).borrowerTokenIds(borrower, --noOfTokens);
            assertEq(_collateral.ownerOf(tokenId), address(_pool)); // token is owned by pool before take
            tokenIds[i] = tokenId;
        }

        super._take(from, borrower, maxCollateral, bondChange, givenAmount, collateralTaken, isReward);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            assertEq(_collateral.ownerOf(tokenIds[i]), from); // token is owned by taker address after remove
        }
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
        ERC721Pool(address(_pool)).pledgeCollateral(from, tokenIds);
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
        _ajna       = ERC20(address(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079));
        vm.makePersistent(address(_ajna));
        _poolUtils  = new PoolInfoUtils();
        vm.makePersistent(address(_poolUtils));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        uint256[] memory tokenIds;
        address contractAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        return ERC721Pool(contractAddress);
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        return ERC721Pool(new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
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
        deal(address(_ajna), operator_, mintAmount_);
        vm.prank(operator_);
        _ajna.approve(address(_pool), type(uint256).max);
    }
}
