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
        deal(address(_quote), address(operator_), mintAmount_);

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
        address owner    = _positionManager.ownerOf(tokenId);
        uint256 lpTokens = _positionManager.getLPTokens(tokenId, mintPrice);

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
        vm.expectRevert("S:TLT:NO_ALLOWANCE");
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // allow position manager to take ownership of the position
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), prices, 9_000 * 1e27);
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
        uint256[] memory lender1Indexes = new uint256[](3);
        lender1Indexes[0] = 2550;
        lender1Indexes[1] = 2551;
        lender1Indexes[2] = 2552;

        uint256[] memory lender1Prices = new uint256[](3);
        lender1Prices[0] = _p3010;
        lender1Prices[1] = _p2995;
        lender1Prices[2] = _p2981;
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId1, testLender1, lender1Indexes
        );

        // allow position manager to take ownership of lender 1's position
        vm.prank(testLender1);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        vm.prank(testLender1);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        vm.prank(testLender1);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender1, address(_positionManager), lender1Prices, 9_000 * 1e27);
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
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        vm.prank(testLender2);
        _pool.approveLpOwnership(address(_positionManager), indexes[3], 3_000 * 1e27);

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
        emit MemorializePosition(testLender2, tokenId2);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender2, address(_positionManager), prices, 6_000 * 1e27);
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
     *  @notice Tests minting an NFT, transfering NFT, memorialize positions.
     *          Checks that old owner cannot memorialize positions.
     *          Old owner reverts: attempts to memorialize positions without permission.
     */
    function testNFTTransfer() external {
        // generate addresses and set test params
        address testMinter     = makeAddr("testMinter");
        address testReceiver   = makeAddr("testReceiver");
        uint256 testIndexPrice = 2550;
        uint256 tokenId        = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(testMinter, mintAmount);
        vm.startPrank(testMinter);
        _pool.addQuoteToken(15_000 * 1e18, testIndexPrice);
        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 15_000 * 1e27);
        // memorialize positions of testMinter
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        (uint256 lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2551, address(_positionManager));
        assertEq(lpBalance, 0);
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, 2551), 0);

        // approve and transfer NFT to different address
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        // check old owner cannot move positions
        // construct move liquidity params
        IPositionManager.MoveLiquidityParams memory moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testReceiver, tokenId, address(_pool), testIndexPrice, 2551
        );
        // move liquidity called by old owner
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check new owner can move positions
        // construct move liquidity params
        moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testReceiver, tokenId, address(_pool), testIndexPrice, 2551
        );
        // move liquidity called by new owner
        changePrank(testReceiver);
        _positionManager.moveLiquidity(moveLiquidityParams);

        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(2551, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertEq(_positionManager.getLPTokens(tokenId, 2551), 15_000 * 1e27);
    }

    /**
     *  @notice Tests NFT position can & can't be burned based on liquidity attached to it.
     *          Checks that old owner cannot move positions.
     *          Owner reverts: attempts to burn NFT with liquidity.
     */
    function testBurnNFTWithoutPositions() external {
        // generate a new address and set test params
        address testAddress = makeAddr("testAddress");

        uint256 tokenId = _mintNFT(testAddress, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testAddress);
        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testAddress, address(_pool));
        // burn and check state changes
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);
    }

    /**
     *  @notice Tests NFT position can & can't be burned based on liquidity attached to it.
     *          Checks that old owner cannot move positions.
     *          Owner reverts: attempts to burn NFT with liquidity.
     */
    function testBurnNFTWithPositions() external {
        address testMinter     = makeAddr("testMinter");
        address notOwner       = makeAddr("notOwner");
        uint256 testIndexPrice = 2550;
        uint256 tokenId        = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(testMinter, mintAmount);
        vm.startPrank(testMinter);
        _pool.addQuoteToken(15_000 * 1e18, testIndexPrice);
        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 15_000 * 1e27);
        // memorialize positions of testMinter
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testMinter, address(_pool));
        // check that NFT cannot be burnt if it tracks postions
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        _positionManager.burn(burnParams);

        // check that NFT cannot be burnt if not owner
        changePrank(notOwner);
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.burn(burnParams);

        // redeem positions of testMinter
        changePrank(testMinter);
        IPositionManager.RedeemPositionsParams memory reedemParams = IPositionManager.RedeemPositionsParams(
            testMinter, tokenId, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);

        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);
    }

    function testMoveLiquidityPermissions() external {
        // generate a new address
        address testAddress = makeAddr("testAddress");
        _mintAndApproveQuoteTokens(testAddress, 10_000 * 1e18);

        // add initial liquidity
        vm.prank(testAddress);
        _pool.addQuoteToken(10_000 * 1e18, 2550);

        // mint position NFT
        uint256 tokenId = _mintNFT(testAddress, address(_pool));

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
        address testAddress1 = makeAddr("testAddress1");
        address testAddress2 = makeAddr("testAddress2");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintAndApproveQuoteTokens(testAddress1, 10_000 * 1e18);
        _mintAndApproveQuoteTokens(testAddress2, 10_000 * 1e18);

        // add initial liquidity
        vm.prank(testAddress1);
        _pool.addQuoteToken(2_500 * 1e18, mintIndex);
        vm.prank(testAddress2);
        _pool.addQuoteToken(5_500 * 1e18, mintIndex);

        uint256 tokenId1 = _mintNFT(testAddress1, address(_pool));
        uint256 tokenId2 = _mintNFT(testAddress2, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId1), testAddress1);
        assertEq(_positionManager.ownerOf(tokenId2), testAddress2);

        // check pool state
        (uint256 lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress1);
        assertEq(lpBalance, 2_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress1
        vm.prank(testAddress1);
        _pool.approveLpOwnership(address(_positionManager), mintIndex, 2_500 * 1e27);

        // memorialize positions of testAddress1
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId1, testAddress1, indexes
        );
        vm.prank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 2_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId1, mintIndex), 2_500 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, moveIndex), 0);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // construct move liquidity params
        IPositionManager.MoveLiquidityParams memory moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testAddress1, tokenId1, address(_pool), mintIndex, moveIndex
        );

        // move liquidity called by testAddress1 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId1);
        vm.prank(address(testAddress1));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 2_500 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId1, moveIndex), 2_500 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress2
        vm.prank(testAddress2);
        _pool.approveLpOwnership(address(_positionManager), mintIndex, 5_500 * 1e27);

        // memorialize positions of testAddress2
        memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId2, testAddress2, indexes
        );
        vm.prank(testAddress2);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 2_500 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId1, moveIndex), 2_500 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, mintIndex), 5_500 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // construct move liquidity params
        moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testAddress2, tokenId2, address(_pool), mintIndex, moveIndex
        );

        // move liquidity called by testAddress2 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress2, tokenId2);
        vm.prank(address(testAddress2));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(moveIndex, address(_positionManager));
        assertEq(lpBalance, 8_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId1, moveIndex), 2_500 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLPTokens(tokenId2, moveIndex), 5_500 * 1e27);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, moveIndex));
    }

    function testRedeemPositions() external {
        address testMinter     = makeAddr("testMinter");
        address notOwner       = makeAddr("notOwner");
        uint256 testIndexPrice = 2550;
        uint256 tokenId        = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(testMinter, mintAmount);
        vm.startPrank(testMinter);
        _pool.addQuoteToken(15_000 * 1e18, testIndexPrice);

        // check pool state
        (uint256 lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 15_000 * 1e27);
        // memorialize positions of testMinter
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // redeem positions of testMinter
        IPositionManager.RedeemPositionsParams memory reedemParams = IPositionManager.RedeemPositionsParams(
            testMinter, tokenId, address(_pool), indexes
        );

        // should fail if trying to redeem from different address but owner
        changePrank(notOwner);
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.reedemPositions(reedemParams);

        // redeem from owner
        vm.expectEmit(true, true, true, true);
        emit RedeemPosition(testMinter, tokenId);
        changePrank(testMinter);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // should fail if trying to redeem one more time
        vm.expectRevert("PM:R:REMOVE_FAIL");
        _positionManager.reedemPositions(reedemParams);
    }

    function testRedeemEmptyPositions() external {
        address testMinter = makeAddr("testMinter");
        uint256 tokenId    = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // redeem positions of testMinter
        uint256[] memory indexes = new uint256[](1);
        IPositionManager.RedeemPositionsParams memory reedemParams = IPositionManager.RedeemPositionsParams(
            testMinter, tokenId, address(_pool), indexes
        );

        // should fail if trying to redeem from different address but owner
        changePrank(testMinter);
        vm.expectRevert("PM:R:REMOVE_FAIL");
        _positionManager.reedemPositions(reedemParams);
    }

    function testRedeemPositionsByNewNFTOwner() external {
        address testMinter     = makeAddr("testMinter");
        address testReceiver   = makeAddr("testReceiver");
        uint256 testIndexPrice = 2550;
        uint256 tokenId        = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintAndApproveQuoteTokens(testMinter, mintAmount);
        _mintAndApproveQuoteTokens(testReceiver, mintAmount);

        vm.startPrank(testReceiver);
        _pool.addQuoteToken(25_000 * 1e18, testIndexPrice);
        _pool.addQuoteToken(15_000 * 1e18, 2551);
        changePrank(testMinter);
        _pool.addQuoteToken(15_000 * 1e18, testIndexPrice);

        // check pool state
        (uint256 lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 25_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 15_000 * 1e27);
        // memorialize positions of testMinter
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 25_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // approve and transfer NFT to different address
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check new owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        IPositionManager.RedeemPositionsParams memory reedemParams = IPositionManager.RedeemPositionsParams(
            testMinter, tokenId, address(_pool), indexes
        );

        // check old owner cannot redeem positions
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.reedemPositions(reedemParams);

        // check position manager cannot redeem positions
        changePrank(address(_positionManager));
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.reedemPositions(reedemParams);

        // redeem from new owner
        uint256[] memory prices = new uint256[](1);
        prices[0] = _p3010;
        reedemParams = IPositionManager.RedeemPositionsParams(
            testReceiver, tokenId, address(_pool), indexes
        );
        vm.expectEmit(true, true, true, true);
        emit RedeemPosition(testReceiver, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_positionManager), testReceiver, prices, 15_000 * 1e27);
        changePrank(testReceiver);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 40_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.bucketLenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
    }

}