// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20Pool/ERC20DSTestPlus.sol';

import '../base/interfaces/IPositionManager.sol';
import '../base/interfaces/IPool.sol';

import '../erc20/ERC20Pool.sol';
import '../erc20/ERC20PoolFactory.sol';

import '../base/PoolInfoUtils.sol';
import '../base/PositionManager.sol';

import '../libraries/Maths.sol';

// TODO: test this against ERC721Pool
abstract contract PositionManagerHelperContract is ERC20HelperContract {

    PositionManager  internal _positionManager;

    constructor() ERC20HelperContract() {
        _positionManager = new PositionManager();
    }

    function _mintQuoteAndApproveManagerTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_positionManager), type(uint256).max);
    }

    /**
     *  @dev Abstract away NFT Minting logic for use by multiple tests.
     */
    function _mintNFT(address minter_, address pool_) internal returns (uint256 tokenId) {
        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(minter_, pool_);
        
        changePrank(mintParams.recipient);
        return _positionManager.mint(mintParams);
    }
}

contract PositionManagerTest is PositionManagerHelperContract {

    /**
     *  @notice Tests base NFT minting functionality.
     */
    function testMint() external {
        uint256 mintAmount  = 50 * 1e18;
        uint256 mintPrice   = 1_004.989662429170775094 * 1e18;
        address testAddress = makeAddr("testAddress");

        _mintQuoteAndApproveManagerTokens(testAddress, mintAmount);

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

        _mintQuoteAndApproveManagerTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[0],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[1],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2],
                newLup: BucketMath.MAX_PRICE
            }
        );

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
        vm.expectRevert(IPoolErrors.NoAllowance.selector);
        _positionManager.memorializePositions(memorializeParams);

        // allow position manager to take ownership of the position
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 9_000 * 1e27);
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

        _mintQuoteAndApproveManagerTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[0],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[1],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2],
                newLup: BucketMath.MAX_PRICE
            }
        );

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 9_000 * 1e27);
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 3_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // add more liquidity
        _addLiquidity(
            {
                from:   testAddress,
                amount: 1_000 * 1e18,
                index:  indexes[0],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 2_000 * 1e18,
                index:  indexes[1],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2],
                newLup: BucketMath.MAX_PRICE
            }
        );

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   1_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[1],
                lpBalance:   2_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 3_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // allow position manager to take ownership of the new LPs
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 1_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 2_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // rememorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), indexes, 6_000 * 1e27);
        _positionManager.memorializePositions(memorializeParams);

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   4_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   5_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   6_000 * 1e27,
                depositTime: 0
            }
        );

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

        _mintQuoteAndApproveManagerTokens(testLender1, mintAmount);
        _mintQuoteAndApproveManagerTokens(testLender2, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;
        indexes[3] = 2553;

        _addLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[0],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[1],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[2],
                newLup: BucketMath.MAX_PRICE
            }
        );

        _addLiquidity(
            {
                from:   testLender2,
                amount: 3_000 * 1e18,
                index:  indexes[0],
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testLender2,
                amount: 3_000 * 1e18,
                index:  indexes[3],
                newLup: BucketMath.MAX_PRICE
            }
        );

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = _mintNFT(testLender1, address(_pool));
        uint256 tokenId2 = _mintNFT(testLender2, address(_pool));

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[3],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[3],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[3],
                lpBalance:   0,
                depositTime: 0
            }
        );

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[1], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[2], tokenId1), 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId2), 0);
        assertEq(_positionManager.getLPTokens(indexes[3], tokenId2), 0);

        (uint256 poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
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
        changePrank(testLender1);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender1, address(_positionManager), lender1Indexes, 9_000 * 1e27);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[3],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[3],
                lpBalance:   0,
                depositTime: 0
            }
        );

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        (poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        changePrank(testLender2);
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
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
        _positionManager.memorializePositions(memorializeParams);

        // // check lender, position manager,  and pool state
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   6_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[3],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[3],
                lpBalance:   3_000 * 1e27,
                depositTime: 0
            }
        );

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId2, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, indexes[3]), 3_000 * 1e27);

        (poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
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

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _addLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId = _mintNFT(testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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

        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _addLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId = _mintNFT(testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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

        vm.prank(testAddress);
        uint256 tokenId = _mintNFT(testAddress, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testAddress);
        // construct BurnParams
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, testAddress, address(_pool)
        );
        // burn and check state changes
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

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _addLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId = _mintNFT(testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

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
        address notOwner    = makeAddr("notOwner");
        _mintQuoteAndApproveManagerTokens(testAddress, 10_000 * 1e18);

        // add initial liquidity
        _addLiquidity(
            {
                from:   testAddress,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // mint position NFT
        uint256 tokenId = _mintNFT(testAddress, address(_pool));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            testAddress, tokenId, address(_pool), 2550, 2551
        );

        // move liquidity should fail because is not performed by owner
        changePrank(notOwner);
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testMoveLiquidity() external {
        // generate a new address
        address testAddress1 = makeAddr("testAddress1");
        address testAddress2 = makeAddr("testAddress2");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintQuoteAndApproveManagerTokens(testAddress1, 10_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(testAddress2, 10_000 * 1e18);

        // add initial liquidity
        _addLiquidity(
            {
                from:   testAddress1,
                amount: 2_500 * 1e18,
                index:  mintIndex,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _addLiquidity(
            {
                from:   testAddress2,
                amount: 5_500 * 1e18,
                index:  mintIndex,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId1 = _mintNFT(testAddress1, address(_pool));
        uint256 tokenId2 = _mintNFT(testAddress2, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId1), testAddress1);
        assertEq(_positionManager.ownerOf(tokenId2), testAddress2);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   5_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       moveIndex,
                lpBalance:   0 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        changePrank(testAddress1);
        _pool.approveLpOwnership(address(_positionManager), mintIndex, 2_500 * 1e27);

        // memorialize positions of testAddress1
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId1, testAddress1, indexes
        );
        changePrank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
       _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   5_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        changePrank(address(testAddress1));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
       _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   5_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       moveIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: 0
            }
        );

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
        changePrank(testAddress2);
        _pool.approveLpOwnership(address(_positionManager), mintIndex, 5_500 * 1e27);

        // memorialize positions of testAddress2
        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, testAddress2, indexes
        );
        changePrank(testAddress2);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
       _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   5_500 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       moveIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: 0
            }
        );

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
        changePrank(address(testAddress2));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
       _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   0 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       moveIndex,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       moveIndex,
                lpBalance:   8_000 * 1e27,
                depositTime: 0
            }
        );

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

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _addLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId = _mintNFT(testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );

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

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _mintQuoteAndApproveManagerTokens(testReceiver, mintAmount);

        _addLiquidity(
            {
                from:   testReceiver,
                amount: 25_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   testReceiver,
                amount: 15_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _addLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256 tokenId = _mintNFT(testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   25_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       2551,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   25_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       2551,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );

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
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   40_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       2551,
                lpBalance:   15_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
    }

}