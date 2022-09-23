// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/Tokens.sol';
import './utils/DSTestPlus.sol';

import '../base/interfaces/IPositionManager.sol';
import '../base/interfaces/IPool.sol';

import '../erc20/ERC20Pool.sol';
import '../erc20/ERC20PoolFactory.sol';

import '../base/PoolInfoUtils.sol';
import '../base/PositionManager.sol';

import '../libraries/Maths.sol';

// TODO: test this against ERC721Pool
abstract contract PositionManagerHelperContract is DSTestPlus {
    ERC20Pool        internal _pool;
    ERC20PoolFactory internal _factory;
    PositionManager  internal _positionManager;
    Token            internal _collateral;
    Token            internal _quote;
    PoolInfoUtils    internal _poolUtils;

    constructor() {
        _collateral      = new Token("Collateral", "C");
        _quote           = new Token("Quote", "Q");
        _factory         = new ERC20PoolFactory();
        _positionManager = new PositionManager();
        _pool            = ERC20Pool(_factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils       = new PoolInfoUtils();
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
        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(minter_, pool_);

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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testAddress, indexes
        );

        // should revert if access hasn't been granted to transfer LP tokens
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
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
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 9_000 * 1e27);
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

    function testRememorializePositions() external {
        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 50_000 * 1e18;

        _mintAndApproveQuoteTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[1]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // check pool state
        (uint256 lpBalance, ) = _pool.lenders(indexes[0], testAddress);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], testAddress);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], testAddress);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 0);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testAddress, indexes
        );
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
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 9_000 * 1e27);
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(indexes[0], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 3_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // add more liquidity
        vm.prank(testAddress);
        _pool.addQuoteToken(1_000 * 1e18, indexes[0]);
        vm.prank(testAddress);
        _pool.addQuoteToken(2_000 * 1e18, indexes[1]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        // check pool state
        (lpBalance, ) = _pool.lenders(indexes[0], testAddress);
        assertEq(lpBalance, 1_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], testAddress);
        assertEq(lpBalance, 2_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], testAddress);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 3_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // allow position manager to take ownership of the new LPs
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 1_000 * 1e27);
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 2_000 * 1e27);
        vm.prank(testAddress);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // rememorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 6_000 * 1e27);
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(indexes[0], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], testAddress);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 4_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 5_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 6_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 4_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 5_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 6_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));
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
        (uint256 lpBalance, ) = _pool.lenders(indexes[0], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], testLender1);
        assertEq(lpBalance, 3_000 * 1e27);

        (lpBalance, ) = _pool.lenders(indexes[0], testLender2);
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[3], testLender2);
        assertEq(lpBalance, 3_000 * 1e27);

        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[1], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[2], tokenId1), 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId2), 0);
        assertEq(_positionManager.getLPTokens(indexes[3], tokenId2), 0);

        (uint256 poolSize, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);

        // construct memorialize lender 1 params struct
        uint256[] memory lender1Indexes = new uint256[](3);
        lender1Indexes[0] = 2550;
        lender1Indexes[1] = 2551;
        lender1Indexes[2] = 2552;

        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
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
        emit TransferLPTokens(testLender1, address(_positionManager), lender1Indexes, 9_000 * 1e27);
        vm.prank(testLender1);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        (lpBalance, ) = _pool.lenders(indexes[0], address(testLender1));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], address(testLender1));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], address(testLender1));
        assertEq(lpBalance, 0);

        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 0);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        (poolSize, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        vm.prank(testLender2);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        vm.prank(testLender2);
        _pool.approveLpOwnership(address(_positionManager), indexes[3], 3_000 * 1e27);

        // memorialize lender 2 quote tokens into minted NFT
        uint256[] memory newIndexes = new uint256[](2);
        newIndexes[0] = 2550;
        newIndexes[1] = 2553;

        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, testLender2, newIndexes
        );

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender2, tokenId2);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender2, address(_positionManager), newIndexes, 6_000 * 1e27);
        vm.prank(testLender2);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        (lpBalance, ) = _pool.lenders(indexes[0], testLender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[3], testLender2);
        assertEq(lpBalance, 0);

        (lpBalance, ) = _pool.lenders(indexes[0], address(_positionManager));
        assertEq(lpBalance, 6_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[1], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[3], address(_positionManager));
        assertEq(lpBalance, 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId2, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, indexes[3]), 3_000 * 1e27);

        (poolSize, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);
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
     *  @notice Tests minting an NFT, transfering NFT by approve, memorialize and redeem positions.
     *          Checks that old owner cannot redeem positions.
     *          Old owner reverts: attempts to redeem positions without permission.
     */
    function testNFTTransferByApprove() external {
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

        // check pool state
        (uint256 lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // approve and transfer NFT to different address
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        // check old owner cannot redeem positions
        // construct redeem liquidity params
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            testReceiver, tokenId, address(_pool), indexes
        );
        // redeem liquidity called by old owner
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.reedemPositions(reedemParams);

        // check new owner can redeem positions
        changePrank(testReceiver);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
    }

    /**
     *  @notice Tests minting an NFT, transfering NFT by permit, memorialize and redeem positions.
     *          Checks that old owner cannot redeem positions.
     *          Old owner reverts: attempts to redeem positions without permission.
     */
    function testNFTTransferByPermit() external {
        // generate addresses and set test params
        (address testMinter, uint256 minterPrivateKey) = makeAddrAndKey("testMinter");

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

        // check pool state
        (uint256 lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // approve and transfer NFT by permit to different address
        {
            uint256 deadline = block.timestamp + 1 days;
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(
                minterPrivateKey,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        _positionManager.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                _positionManager.PERMIT_TYPEHASH(),
                                testReceiver,
                                tokenId,
                                0,
                                deadline
                            )
                        )
                    )
                )
            );
            _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, testReceiver, tokenId, deadline, v, r, s );
        }

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        // check old owner cannot redeem positions
        // construct redeem liquidity params
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            testReceiver, tokenId, address(_pool), indexes
        );
        // redeem liquidity called by old owner
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.reedemPositions(reedemParams);

        // check new owner can redeem positions
        changePrank(testReceiver);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
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
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, testAddress, address(_pool)
        );
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // construct BurnParams
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(tokenId, testMinter, address(_pool));
        // check that NFT cannot be burnt if it tracks postions
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        _positionManager.burn(burnParams);

        // check that NFT cannot be burnt if not owner
        changePrank(notOwner);
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.burn(burnParams);

        // redeem positions of testMinter
        changePrank(testMinter);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
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
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
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
        (uint256 lpBalance, ) = _pool.lenders(mintIndex, testAddress1);
        assertEq(lpBalance, 2_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, address(_positionManager));
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId1, testAddress1, indexes
        );
        vm.prank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 2_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, address(_positionManager));
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
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            testAddress1, tokenId1, address(_pool), mintIndex, moveIndex
        );

        // move liquidity called by testAddress1 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId1);
        vm.prank(address(testAddress1));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress2);
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, address(_positionManager));
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
        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, testAddress2, indexes
        );
        vm.prank(testAddress2);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 5_500 * 1e27);
        (lpBalance, ) = _pool.lenders(moveIndex, address(_positionManager));
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
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            testAddress2, tokenId2, address(_pool), mintIndex, moveIndex
        );

        // move liquidity called by testAddress2 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress2, tokenId2);
        vm.prank(address(testAddress2));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, testAddress2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(mintIndex, address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(moveIndex, address(_positionManager));
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
        (uint256 lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // redeem positions of testMinter
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
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
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
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
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            testMinter, tokenId, address(_pool), indexes
        );

        // should fail if trying to redeem empty position
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
        (uint256 lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 25_000 * 1e27);
        (lpBalance, ) = _pool.lenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
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
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, testMinter, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 25_000 * 1e27);
        (lpBalance, ) = _pool.lenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 15_000 * 1e27);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // approve and transfer NFT to different address
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check new owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
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
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            testReceiver, tokenId, address(_pool), indexes
        );
        vm.expectEmit(true, true, true, true);
        emit RedeemPosition(testReceiver, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_positionManager), testReceiver, indexes, 15_000 * 1e27);
        changePrank(testReceiver);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        (lpBalance, ) = _pool.lenders(testIndexPrice, testMinter);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(testIndexPrice, testReceiver);
        assertEq(lpBalance, 40_000 * 1e27);
        (lpBalance, ) = _pool.lenders(2551, testReceiver);
        assertEq(lpBalance, 15_000 * 1e27);
        (lpBalance, ) = _pool.lenders(testIndexPrice, address(_positionManager));
        assertEq(lpBalance, 0);

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
    }

}