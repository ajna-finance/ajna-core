// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { CollateralToken, NFTCollateralToken, QuoteToken } from "./utils/Tokens.sol";
import { DSTestPlus }                                      from "./utils/DSTestPlus.sol";

import { Maths } from "../libraries/Maths.sol";

import { ERC20Pool }       from "../erc20/ERC20Pool.sol";
import { ERC20PoolFactory} from "../erc20/ERC20PoolFactory.sol";

import { PositionManager } from "../base/PositionManager.sol";

import { IPositionManager } from "../base/interfaces/IPositionManager.sol";

abstract contract PositionManagerHelperContract is DSTestPlus {
    CollateralToken  internal _collateral;
    ERC20Pool        internal _pool;
    ERC20PoolFactory internal _factory;
    PositionManager  internal _positionManager;
    QuoteToken       internal _quote;

    constructor() {
        _collateral      = new CollateralToken();
        _quote           = new QuoteToken();
        _factory         = new ERC20PoolFactory();
        _positionManager = new PositionManager();
        _pool            = ERC20Pool(_factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
    }

    function _mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) internal {
        _quote.mint(operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_positionManager), type(uint256).max);

    }

    function _mintAndApproveCollateralTokens(address operator_, uint256 mintAmount_) internal{
        deal(address(_collateral), address(operator_), mintAmount_);

        _collateral.approve(address(_pool),            mintAmount_);
        _collateral.approve(address(_positionManager), mintAmount_);
    }

    /**
     *  @dev Abstract away NFT Minting logic for use by multiple tests.
     */
    function _mintNFT(address minter_, address pool_) internal returns (uint256 tokenId) {
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(minter_, pool_);

        vm.prank(mintParams.recipient);
        return _positionManager.mint(mintParams);
    }

    function _increaseLiquidity(
        uint256 tokenId_, address recipient_, address pool_, uint256 amount_, uint256 index_, uint256 price_
    ) internal {
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId_, recipient_, pool_, amount_, index_
        );

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient_, price_, amount_);

        vm.prank(recipient_);
        _positionManager.increaseLiquidity(increaseLiquidityParams);
    }
}
contract PositionManagerTest is PositionManagerHelperContract {

    /**
     *  @notice Tests base NFT minting functionality.
     */
    function testMint() external {
        uint256 mintAmount  = 50 * 1e18;
        uint256 mintPrice   = _p1004;
        address testAddress = makeAddr("testAddress");

        _mintAndApproveQuoteTokens(testAddress, mintAmount);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testAddress, address(_pool), 1);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        require(tokenId != 0, "tokenId nonce not incremented");

        // check position info
        (, address owner, ) = _positionManager.positions(tokenId);
        uint256 lpTokens    = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, testAddress);
        assert(lpTokens == 0);
    }

    /**
     *  @notice Tests attachment of a created position to an already existing NFT.
     *          LP tokens are checked to verify ownership of position.
     *          Reverts:
     *              Attempts to memorialize when lp tokens aren't allowed to be transfered
     *              Attempts to set position owner when not owner of the LP tokens
     */
    function testMemorializePositions() external {
        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 10000 * 1e18;

        _mintAndApproveQuoteTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        uint256[] memory prices = new uint256[](3);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;

        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[1]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2550));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2551));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2552));

        // construct memorialize params struct
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testAddress, indexes
        );

        // should revert if access hasn't been granted to transfer LP tokens
        vm.expectRevert("S:TLT:NOT_OWNER");
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // allow position manager to take ownership of the position
        vm.prank(testAddress);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), prices, 9_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLPTokens = _positionManager.getLPTokens(tokenId, indexes[0]);
        assert(positionAtPriceOneLPTokens > 0);

        // check lp tokens at non added to price
        uint256 positionAtWrongPriceLPTokens = _positionManager.getLPTokens(tokenId, 4000000 * 1e18);
        assert(positionAtWrongPriceLPTokens == 0);

        assertTrue(_positionManager.isIndexInPosition(tokenId, 2550));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2551));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2552));
    }

    /**
     *  @notice Tests attachment of multiple previously created position to already existing NFTs.
     *          LP tokens are checked to verify ownership of position.
     */
    function testMemorializeMultiple() external {
        address testLender1 = makeAddr("testLender1");
        address testLender2 = makeAddr("testLender2");
        uint256 mintAmount  = 10000 * 1e18;

        _mintAndApproveQuoteTokens(testLender1, mintAmount);
        _mintAndApproveQuoteTokens(testLender2, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;
        indexes[3] = 2553;

        uint256[] memory prices = new uint256[](4);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;
        prices[3] = _p2966;

        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[1]);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, indexes[3]);

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = _mintNFT(testLender1, address(_pool));
        uint256 tokenId2 = _mintNFT(testLender2, address(_pool));

        // check lender, position manager, and pool state
        (uint256 lpBalance, ) = _pool.bucketLenders(indexes[0], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[1], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[2], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);

        (lpBalance, ) = _pool.bucketLenders(indexes[0], testLender2);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[3], testLender2);
        assertEq(lpBalance, 3_000 * 1e27);

        (lpBalance, ) = _pool.bucketLenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[1], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[2], tokenId1), 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId2), 0);
        assertEq(_positionManager.getLPTokens(indexes[3], tokenId2), 0);

        assertEq(_pool.poolSize(), 15_000 * 1e18);

        // construct memorialize lender 1 params struct
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId1, testLender1, indexes
        );

        // allow position manager to take ownership of lender 1's position
        vm.prank(testLender1);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender1, address(_positionManager), prices, 9_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1);
        vm.prank(testLender1);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        (lpBalance, ) = _pool.bucketLenders(indexes[0], address(testLender1));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[1], address(testLender1));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[2], address(testLender1));
        assertEq(lpBalance, 0);

        (lpBalance, ) = _pool.bucketLenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 0);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_pool.poolSize(), 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        vm.prank(testLender2);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize lender 2 quote tokens into minted NFT
        uint256[] memory newIndexes = new uint256[](2);
        newIndexes[0] = 2550;
        newIndexes[1] = 2553;

        prices = new uint256[](2);
        prices[0] = _p3010;
        prices[1] = _p2966;
        memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId2, testLender2, newIndexes
        );

        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender2, address(_positionManager), prices, 6_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender2, tokenId2);
        vm.prank(testLender2);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        (lpBalance, ) = _pool.bucketLenders(indexes[0], testLender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(indexes[3], testLender2);
        assertEq(lpBalance, 0);

        (lpBalance, ) = _pool.bucketLenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 6_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId2, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, indexes[3]), 3_000 * 1e27);

        assertEq(_pool.poolSize(), 15_000 * 1e18);
    }

    function testMemorializeMultipleAndModifyLiquidity() external {
        // TODO implement
    }

    /**
     *  @notice Tests a contract minting an NFT.
     */
    function testMintToContract() external {
        // TODO to be reviewed
        address lender = makeAddr("lender");
        _quote.mint(address(lender), 200_000 * 1e18);

        // check that contract can successfully receive the NFT
        vm.expectEmit(true, true, true, true);
        emit Mint(address(lender), address(_pool), 1);
        _mintNFT(address(lender), address(_pool));
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity at two different prices.
     */
    function testIncreaseLiquidity() external {
        // generate a new address
        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 10000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;
        _mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));
        

        // check newly minted position with no liquidity added
        (, address originalPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens == 0);

        assertFalse(_positionManager.isIndexInPosition(tokenId, 2550));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2551));

        // add no liquidity
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, testAddress, address(_pool), 0, mintIndex
        );

        vm.prank(testAddress);
        vm.expectRevert("PM:IL:NO_LP_TOKENS");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // add initial liquidity
        _increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintIndex, mintPrice);

        // check liquidity was added successfully
        (, address updatedPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(_pool.poolSize(), mintAmount / 4);
        assertEq(updatedPositionOwner, testAddress);
        assert(updatedLPTokens != 0);

        // Add liquidity to the same price again
        _increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintIndex, mintPrice);

        uint256 positionUpdatedTwiceTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(_pool.poolSize(), mintAmount / 2);
        assert(positionUpdatedTwiceTokens > updatedLPTokens);

        assertTrue(_positionManager.isIndexInPosition(tokenId, mintIndex));

        // add liquidity to a different price, for same owner and tokenId
        _increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 2, 2551, _p2995);

        assertTrue(_positionManager.isIndexInPosition(tokenId, 2551));

        assertEq(_pool.poolSize(), mintAmount);
    }

    /**
     *  @notice Tests minting an NFT and failing to increase liquidity for invalid recipient.
     *          Recipient reverts: attempts to increase liquidity when not permited.
     */
    function testIncreaseLiquidityPermissions() external {
        address recipient      = makeAddr("recipient");
        address externalCaller = makeAddr("externalCaller");
        uint256 tokenId        = _mintNFT(recipient, address(_pool));
        uint256 mintAmount     = 10000 * 1e18;
        uint256 mintIndex      = 2550;

        _mintAndApproveQuoteTokens(recipient, mintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, recipient, address(_pool), mintAmount / 4, mintIndex
        );

        // should revert if called by a non-recipient address
        vm.prank(externalCaller);
        vm.expectRevert("PM:NO_AUTH");

        _positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity and decreasing liquidity.
     */
    function testDecreaseLiquidityNoDebt() external {
        // generate a new address and set test params
        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 10_000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        _mintAndApproveQuoteTokens(testAddress, mintAmount);
        uint256 testerQuoteBalance = _quote.balanceOf(testAddress);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        _increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintIndex, mintPrice);

        // check initial pool balance
        uint256 postAddPoolQuote = _pool.poolSize();

        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - mintAmount);
        assertEq(_pool.poolSize(), mintAmount);

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // find number of lp tokens received
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex); // RAY
        assertEq(originalLPTokens, 10_000 * 1e27);

        assertTrue(_positionManager.isIndexInPosition(tokenId, mintIndex));

        // remove 1/4 of the LP tokens
        uint256 lpTokensToRemove = originalLPTokens / 4;
        assertEq(lpTokensToRemove, 2_500 * 1e27);

        assertEq(_pool.poolSize(), 10_000 * 1e18);

        // decrease liquidity
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testAddress, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testAddress, mintPrice);

        // decrease liquidity and check change in balances
        vm.prank(testAddress);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check quote token removed
        assertEq(_pool.poolSize(), 7_500 * 1e18);
        assertGt(postAddPoolQuote, _pool.poolSize());
        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - _pool.poolSize());

        // check lp tokens matches expectations
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);
        assertLt(updatedLPTokens, originalLPTokens);

        assertTrue(_positionManager.isIndexInPosition(tokenId, mintIndex));
    }

    /**
     *  @notice Tests minting an NFT, transfering NFT, increasing liquidity.
     *          Checks that old owner cannot increase liquidity.
     *          Old owner reverts: attempts to increase liquidity without permission.
     */
    function testNFTTransfer() external {
        // generate addresses and set test params
        address testMinter      = makeAddr("testMinter");
        address testReceiver    = makeAddr("testReceiver");
        uint256 testIndexPrice  = 2550;
        uint256 testBucketPrice = _p3010;
        uint256 tokenId         = _mintNFT(testMinter, address(_pool));

        // check owner
        (, address originalOwner, ) = _positionManager.positions(tokenId);
        assertEq(originalOwner, testMinter);

        // approve and transfer NFT to different address
        vm.prank(testMinter);
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check owner
        (, address newOwner, ) = _positionManager.positions(tokenId);
        assertEq(newOwner, testReceiver);
        assert(newOwner != originalOwner);

        // check new owner can increaseLiquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(newOwner, mintAmount);

        _increaseLiquidity(tokenId, newOwner, address(_pool), mintAmount, testIndexPrice, testBucketPrice);

        // check previous owner can no longer modify the NFT
        uint256 nextMintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(originalOwner, nextMintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, originalOwner, address(_pool), mintAmount / 4, testIndexPrice
        );

        vm.expectRevert("PM:NO_AUTH");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // check new owner can decreaseLiquidity
        uint256 lpTokensToAttempt = _positionManager.getLPTokens(tokenId, testIndexPrice);
        assertEq(lpTokensToAttempt, 50_000 * 1e27);

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, newOwner, address(_pool), testIndexPrice, lpTokensToAttempt
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(newOwner, testBucketPrice);
        vm.prank(newOwner);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);
    }

    /**
     *  @notice Tests NFT position can & can't be burned based on liquidity attached to it.
     *          Checks that old owner cannot increase liquidity.
     *          Owner reverts: attempts to burn NFT with liquidity.
     */
    function testBurn() external {
        // generate a new address and set test params
        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 10000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        _mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        _increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintIndex, mintPrice);

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testAddress, mintIndex, address(_pool));

        // should revert if liquidity not removed
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        // remove all lp tokens
        uint256 lpTokensToRemove = _positionManager.getLPTokens(tokenId, mintIndex);
        assertEq(lpTokensToRemove, 10_000 * 10**27);
        assertEq(_pool.poolSize(), 10_000 * 1e18);

        assertTrue(_positionManager.isIndexInPosition(tokenId, mintIndex));

        // decrease liquidity
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testAddress, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testAddress, mintPrice);

        // decrease liquidity and check change in balances
        vm.prank(testAddress);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);
        assertEq(_pool.poolSize(), 0);

        // should emit Burn
        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        // burn and check state changes
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        (, address burntPositionOwner, ) = _positionManager.positions(tokenId);
        assertEq(burntPositionOwner, 0x0000000000000000000000000000000000000000);

        assertFalse(_positionManager.isIndexInPosition(tokenId, mintIndex));
    }

    function testMoveLiquidityPermissions() external {
       // generate a new address
        address testAddress = makeAddr("testAddress");
        _mintAndApproveQuoteTokens(testAddress, 10_000 * 1e18);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // add initial liquidity
        _increaseLiquidity(tokenId, testAddress, address(_pool), 10_000 * 1e18, 2550, _p3010);

        // construct move liquidity params
        IPositionManager.MoveLiquidityParams memory moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testAddress, tokenId, address(_pool), 2550, 2551
        );

        // move liquidity should fail because is not performed by owner
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testMoveLiquidity() external {
        // generate a new address
        address testAddress = makeAddr("testAddress");
        uint256 mintIndex   = 2550;
        uint256 moveIndex   = 2551;
        _mintAndApproveQuoteTokens(testAddress, 10_000 * 1e18);

        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // add initial liquidity
        _increaseLiquidity(tokenId, testAddress, address(_pool), 2_500 * 1e18, mintIndex, _p3010);

        // check pool state
        (uint256 lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertGt(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 0);

        assertTrue(_positionManager.isIndexInPosition(tokenId, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId, moveIndex));

        // construct move liquidity params
        IPositionManager.MoveLiquidityParams memory moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testAddress, tokenId, address(_pool), mintIndex, moveIndex
        );

        // move liquidity called by owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress, tokenId);
        vm.prank(testAddress);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertGt(lpBalance, 0);

        assertFalse(_positionManager.isIndexInPosition(tokenId, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId, moveIndex));
    }
}

contract PositionManagerDecreaseLiquidityWithDebtTest is PositionManagerHelperContract {

    address internal _testLender;
    address internal _testLender2;
    uint256 internal _mintAmount;
    uint256 internal _mintIndex;
    uint256 internal _mintPrice;
    uint256 internal _tokenId;

    address internal _testBorrower;

    function setUp() public {
        _testLender  = makeAddr("testLender");
        _testLender2 = makeAddr("testLender2");
        _mintAmount  = 50_000 * 1e18;
        _mintIndex   = 2550;
        _mintPrice   = _p3010;

        _mintAndApproveQuoteTokens(_testLender, _mintAmount);
        _mintAndApproveQuoteTokens(_testLender2, _mintAmount);

        _tokenId = _mintNFT(_testLender, address(_pool));

        // add liquidity that can later be decreased
        _increaseLiquidity(_tokenId, _testLender, address(_pool), _mintAmount, _mintIndex, _mintPrice);

        // Borrow against the pool
        _testBorrower            = makeAddr("borrower");
        uint256 collateralToMint = 5_000 * 1e18;
        vm.startPrank(_testBorrower);
        _mintAndApproveCollateralTokens(_testBorrower, collateralToMint);

        // add collateral and borrow against it
        _pool.pledgeCollateral(collateralToMint, address(0), address(0));
        _pool.borrow(25_000 * 1e18, 3000, address(0), address(0));
    }

    modifier checkInitialState() {
        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(_tokenId, _mintIndex);
        assertEq(originalLPTokens, 50_000 * 1e27);

        assertTrue(_positionManager.isIndexInPosition(_tokenId, _mintIndex));

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.poolSize(),     50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),         5_000 * 1e18);
        assertEq(_collateral.balanceOf(_testLender),            0);
        assertEq(_collateral.balanceOf(address(_testBorrower)), 0);

        assertEq(_quote.balanceOf(address(_pool)),         25_000 * 1e18);
        assertEq(_quote.balanceOf(_testLender),            0);
        assertEq(_quote.balanceOf(address(_testBorrower)), 25_000 * 1e18);
        _;
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     *  @notice Lender that removes liquidity will end up with both collateral and quote tokens.
     */
    function testDecreaseLiquidityWithDebtRedeemCollateralAndQuoteTokens() external checkInitialState {

        // bidder add less collateral to bucket than lender can redeem.
        // Lender will redeem all collateral from bucket and rest of LP tokens as quote tokens
        address testBidder = makeAddr("bidder");
        changePrank(testBidder);
        _mintAndApproveCollateralTokens(testBidder, 50_000 * 1e18);
        _pool.addCollateral(1 * 1e18, _mintIndex);

        // add additional quote tokens to enable reallocation decrease liquidity
        changePrank(_testLender2);
        _pool.addQuoteToken(40_000 * 1e18, _mintIndex);

        // lender removes their entire provided liquidity
        changePrank(_testLender);
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            _tokenId, _testLender, address(_pool), _mintIndex, 50_000 * 1e27
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(_testLender, _mintPrice);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.poolSize(),     43_010.892022197881557845 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),         5_000 * 1e18);
        assertEq(_collateral.balanceOf(_testLender),            1 * 1e18);
        assertEq(_collateral.balanceOf(address(_testBorrower)), 0);

        assertEq(_quote.balanceOf(address(_pool)),         18_010.892022197881557845 * 1e18);
        assertEq(_quote.balanceOf(_testLender),            46_989.107977802118442155 * 1e18);
        assertEq(_quote.balanceOf(address(_testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(_tokenId, _p10016);
        assertEq(updatedLPTokens, 0);

        assertFalse(_positionManager.isIndexInPosition(_tokenId, _mintIndex));
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     *  @notice Lender that removes liquidity will end up with collateral only.
     */
    function testDecreaseLiquidityWithDebtRedeemCollateralOnly() external checkInitialState {

        // bidder add more collateral to bucket than lender can redeem.
        // Lender will redeem all LPs as collateral
        address testBidder = makeAddr("bidder");
        changePrank(testBidder);
        _mintAndApproveCollateralTokens(testBidder, 50_000 * 1e18);
        _pool.addCollateral(100 * 1e18, _mintIndex);

        // add additional quote tokens to enable reallocation decrease liquidity
        changePrank(address(_testLender2));
        _pool.addQuoteToken(40_000 * 1e18, _mintIndex);

        // lender removes their entire provided liquidity
        changePrank(address(_testLender));
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            _tokenId, _testLender, address(_pool), _mintIndex, 50_000 * 1e27
        );
        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(_testLender, _mintPrice);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.poolSize(),     90_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),         5_083.393625665957573560 * 1e18);
        assertEq(_collateral.balanceOf(_testLender),            16.606374334042426440 * 1e18);
        assertEq(_collateral.balanceOf(address(_testBorrower)), 0);

        assertEq(_quote.balanceOf(address(_pool)),         65_000 * 1e18);
        assertEq(_quote.balanceOf(_testLender),            0);
        assertEq(_quote.balanceOf(address(_testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(_tokenId, _p10016);
        assertEq(updatedLPTokens, 0);

        assertFalse(_positionManager.isIndexInPosition(_tokenId, _mintIndex));
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     *  @notice Lender that removes liquidity will end up with quote tokens only.
     */
    function testDecreaseLiquidityWithDebtRedeemQuoteTokensOnly() external checkInitialState {

        // add additional quote tokens to enable reallocation decrease liquidity
        changePrank(_testLender2);
        _pool.addQuoteToken(40_000 * 1e18, _mintIndex);

        // lender removes their entire provided liquidity
        changePrank(_testLender);
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            _tokenId, _testLender, address(_pool), _mintIndex, 50_000 * 1e27
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(_testLender, _mintPrice);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.poolSize(),     40_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),         5_000 * 1e18);
        assertEq(_collateral.balanceOf(_testLender),            0 * 1e18);
        assertEq(_collateral.balanceOf(address(_testBorrower)), 0);

        assertEq(_quote.balanceOf(address(_pool)),         15_000 * 1e18);
        assertEq(_quote.balanceOf(_testLender),            50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(_tokenId, _p10016);
        assertEq(updatedLPTokens, 0);

        assertFalse(_positionManager.isIndexInPosition(_tokenId, _mintIndex));
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity in an NFT Pool.
     *          Lender reverts when attempting to interact with a pool the tokenId wasn't minted in
     */
    function testDecreaseLiquidityWithDebtNFTPool() external {
        // TODO implement when ERC721 pool backported
    }

}