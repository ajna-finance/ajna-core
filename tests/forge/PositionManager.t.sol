// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { Base64 } from '@base64-sol/base64.sol';

import { ERC20HelperContract } from './ERC20Pool/ERC20DSTestPlus.sol';
import { ERC721HelperContract } from './ERC721Pool/ERC721DSTestPlus.sol';

import 'src/interfaces/position/IPositionManager.sol';
import 'src/PositionManager.sol';
import 'src/libraries/helpers/SafeTokenNamer.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';

import './utils/ContractNFTRecipient.sol';

abstract contract PositionManagerERC20PoolHelperContract is ERC20HelperContract {

    PositionManager  internal _positionManager;

    constructor() ERC20HelperContract() {
        _positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));
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
    function _mintNFT(address minter_, address lender_, address pool_) internal returns (uint256 tokenId) {
        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(lender_, pool_, keccak256("ERC20_NON_SUBSET_HASH"));
        
        changePrank(minter_);
        return _positionManager.mint(mintParams);
    }

    function _getPermitSig(
        address receiver_,
        uint256 tokenId_,
        uint256 deadline_,
        uint256 ownerPrivateKey_
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        return vm.sign(
                ownerPrivateKey_,
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        _positionManager.DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                _positionManager.PERMIT_TYPEHASH(),
                                receiver_,
                                tokenId_,
                                0,
                                deadline_
                            )
                        )
                    )
                )
            );
    }
}

contract PositionManagerERC20PoolTest is PositionManagerERC20PoolHelperContract {

    /**
     *  @notice Tests base NFT minting functionality.
     *          Reverts:
     *              Attempts to mint an NFT associated with an invalid pool.
     */
    function testMint() external {
        uint256 mintAmount  = 50 * 1e18;
        uint256 mintPrice   = 1_004.989662429170775094 * 1e18;
        address testAddress = makeAddr("testAddress");

        _mintQuoteAndApproveManagerTokens(testAddress, mintAmount);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testAddress, address(_pool), 1);
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        require(tokenId != 0, "tokenId nonce not incremented");

        // check position info
        address owner    = _positionManager.ownerOf(tokenId);
        uint256 lpTokens = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, testAddress);
        assertEq(lpTokens, 0);

        // deploy a new factory to simulate creating a pool outside of expected factories
        ERC20PoolFactory invalidFactory = new ERC20PoolFactory(_ajna);
        address invalidPool = invalidFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // check can't mint an NFT associated with a non ajna pool
        vm.expectRevert(IPositionManagerErrors.NotAjnaPool.selector);
        _mintNFT(testAddress, testAddress, invalidPool);
    }

    /**
     *  @notice Tests attachment of a created position to an already existing NFT.
     *          LP tokens are checked to verify ownership of position.
     *          Reverts:
     *              Attempts to memorialize when lp tokens aren't allowed to be transfered.
     *              Attempts to set position owner when not owner of the LP tokens.
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

        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2550));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2551));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2552));

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
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
        assertGt(positionAtPriceOneLPTokens, 0);

        // check lp tokens at non added to price
        uint256 positionAtWrongPriceLPTokens = _positionManager.getLPTokens(tokenId, 4000000 * 1e18);
        assertEq(positionAtWrongPriceLPTokens, 0);

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

        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId, indexes
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 1_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 2_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[0],
                lpBalance:   1_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[1],
                lpBalance:   2_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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

        _addInitialLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testLender1,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        _addInitialLiquidity(
            {
                from:   testLender2,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testLender2,
                amount: 3_000 * 1e18,
                index:  indexes[3]
            }
        );

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = _mintNFT(testLender1, testLender1, address(_pool));
        uint256 tokenId2 = _mintNFT(testLender2, testLender2, address(_pool));

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testLender1,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testLender2,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId1, lender1Indexes
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId2, newIndexes
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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
                depositTime: _startTime
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

    /**
     *  @notice Tests a contract minting an NFT.
     */
    function testMintToContract() external {
        address mintingOwner = makeAddr("mintingOwner");
        address recipientOwner = makeAddr("recipientOwner");

        // deploy contract to receive the NFT
        ContractNFTRecipient recipientContract = new ContractNFTRecipient(mintingOwner);

        // check that contract can successfully receive the NFT
        vm.expectEmit(true, true, true, true);
        emit Mint(address(recipientContract), address(_pool), 1);
        _mintNFT(address(recipientContract), address(recipientContract), address(_pool));

        // check contract is owner of minted NFT
        assertEq(_positionManager.ownerOf(1), address(recipientContract));

        // check contract owner can transfer to another smart contract
        ContractNFTRecipient secondRecipient = new ContractNFTRecipient(recipientOwner);
        recipientContract.transferNFT(address(_positionManager), address(secondRecipient), 1);
        assertEq(_positionManager.ownerOf(1), address(secondRecipient));
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
        _addInitialLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice
            }
        );

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
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
            tokenId, indexes
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
                depositTime: _startTime
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
            tokenId, address(_pool), indexes
        );
        // redeem liquidity called by old owner
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
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
                depositTime: _startTime
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
        _addInitialLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice
            }
        );

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
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
            tokenId, indexes
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
                depositTime: _startTime
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
            tokenId, address(_pool), indexes
        );
        // redeem liquidity called by old owner
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
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
                depositTime: _startTime
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

    function testPermitByContract() external {
        // deploy recipient contract
        (address nonMintingContractOwner, uint256 nonMintingContractPrivateKey) = makeAddrAndKey("nonMintingContract");
        ContractNFTRecipient recipientContract = new ContractNFTRecipient(nonMintingContractOwner);

        // deploy contract to receive the NFT
        (address testContractOwner, uint256 ownerPrivateKey) = makeAddrAndKey("testContractOwner");
        ContractNFTRecipient ownerContract = new ContractNFTRecipient(testContractOwner);
        uint256 tokenId = _mintNFT(address(ownerContract), address(ownerContract), address(_pool));

        // check contract owned nft can't be signed by non owner
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(address(recipientContract), tokenId, deadline, nonMintingContractPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        _positionManager.safeTransferFromWithPermit(address(ownerContract), address(recipientContract), address(recipientContract), tokenId, deadline, v, r, s );

        // check owner can permit their contract to transfer the NFT
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(address(recipientContract), tokenId, deadline, ownerPrivateKey);
        _positionManager.safeTransferFromWithPermit(address(ownerContract), address(recipientContract), address(recipientContract), tokenId, deadline, v, r, s );
    }

    function testPermitReverts() external {
        // generate addresses and set test params
        (address testMinter, uint256 minterPrivateKey) = makeAddrAndKey("testMinter");
        (address testReceiver, uint256 receiverPrivateKey) = makeAddrAndKey("testReceiver");

        vm.prank(testMinter);
        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check can't use a deadline in the past
        uint256 deadline = block.timestamp - 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(testReceiver, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-permit-expired");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, testReceiver, tokenId, deadline, v, r, s );

        // check can't self approve
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testMinter, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ERC721Permit: approval to current owner");
        _positionManager.safeTransferFromWithPermit(testMinter, testMinter, testMinter, tokenId, deadline, v, r, s );

        // check signer is authorized to permit
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testReceiver, tokenId, deadline, receiverPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, testReceiver, tokenId, deadline, v, r, s );

        // check signature is valid
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testReceiver, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-invalid-signature");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, testReceiver, tokenId, deadline, 0, r, s );
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
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testAddress);
        // construct BurnParams
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, address(_pool)
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
        _addInitialLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice
            }
        );

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 15_000 * 1e27);
        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // construct BurnParams
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(tokenId, address(_pool));
        // check that NFT cannot be burnt if it tracks postions
        vm.expectRevert(IPositionManagerErrors.LiquidityNotRemoved.selector);
        _positionManager.burn(burnParams);

        // check that NFT cannot be burnt if not owner
        changePrank(notOwner);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.burn(burnParams);

        // redeem positions of testMinter
        changePrank(testMinter);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
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

        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );

        // mint position NFT
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), 2550, 2551
        );

        // move liquidity should fail because is not performed by owner
        changePrank(notOwner);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testMoveLiquidity() external {
        // generate a new address
        address testAddress1 = makeAddr("testAddress1");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintQuoteAndApproveManagerTokens(testAddress1, 10_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(testAddress2, 10_000 * 1e18);
        _mintCollateralAndApproveTokens(testAddress3, 10_000 * 1e18);

        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 2_500 * 1e18,
                index:  mintIndex
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress2,
                amount: 5_500 * 1e18,
                index:  mintIndex
            }
        );

        uint256 tokenId1 = _mintNFT(testAddress1, testAddress1, address(_pool));
        uint256 tokenId2 = _mintNFT(testAddress2, testAddress2, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId1), testAddress1);
        assertEq(_positionManager.ownerOf(tokenId2), testAddress2);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       mintIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       mintIndex,
                lpBalance:   5_500 * 1e27,
                depositTime: _startTime
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
            tokenId1, indexes
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
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   2_500 * 1e27,
                depositTime: _startTime
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
            tokenId1, address(_pool), mintIndex, moveIndex
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
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       mintIndex,
                lpBalance:   0,
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId2, indexes
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
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId2, address(_pool), mintIndex, moveIndex
        );

        _addCollateral(
            {
                from:    testAddress3,
                amount:  10_000 * 1e18,
                index:   mintIndex,
                lpAward: 30_108_920.22197881557845 * 1e27
            }
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
                depositTime: _startTime
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
                depositTime: _startTime
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

        // check can't move liquidity from position with no liquidity
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId2, address(_pool), 1000, 2000
        );
        changePrank(address(testAddress2));
        vm.expectRevert(IPositionManagerErrors.RemoveLiquidityFailed.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testRedeemPositions() external {
        address testMinter     = makeAddr("testMinter");
        address notOwner       = makeAddr("notOwner");
        uint256 testIndexPrice = 2550;

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);
        _addInitialLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice
            }
        );

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
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
            tokenId, indexes
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
                depositTime: _startTime
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, testIndexPrice), 15_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // redeem positions of testMinter
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );

        // should fail if trying to redeem from different address but owner
        changePrank(notOwner);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
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
                depositTime: _startTime
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
        vm.expectRevert(IPositionManagerErrors.RemoveLiquidityFailed.selector);
        _positionManager.reedemPositions(reedemParams);
    }

    function testRedeemEmptyPositions() external {
        address testMinter = makeAddr("testMinter");
        uint256 tokenId    = _mintNFT(testMinter, testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // redeem positions of testMinter
        uint256[] memory indexes = new uint256[](1);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );

        // should fail if trying to redeem empty position
        changePrank(testMinter);
        vm.expectRevert(IPositionManagerErrors.RemoveLiquidityFailed.selector);
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
        _addInitialLiquidity(
            {
                from:   testReceiver,
                amount: 25_000 * 1e18,
                index:  testIndexPrice
            }
        );
        _addInitialLiquidity(
            {
                from:   testReceiver,
                amount: 15_000 * 1e18,
                index:  2551
            }
        );

        _addInitialLiquidity(
            {
                from:   testMinter,
                amount: 15_000 * 1e18,
                index:  testIndexPrice
            }
        );

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance(
            {
                lender:      testMinter,
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testReceiver,
                index:       testIndexPrice,
                lpBalance:   25_000 * 1e27,
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId, indexes
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
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       testIndexPrice,
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime
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
                depositTime: _startTime
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
            tokenId, address(_pool), indexes
        );

        // check old owner cannot redeem positions
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.reedemPositions(reedemParams);

        // check position manager cannot redeem positions
        changePrank(address(_positionManager));
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.reedemPositions(reedemParams);

        // redeem from new owner
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
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
                depositTime: _startTime
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
                depositTime: _startTime
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

    function test3rdPartyMinter() external {
        address lender = makeAddr("lender");
        address minter = makeAddr("minter");
        uint256 mintAmount  = 10000 * 1e18;

        _mintQuoteAndApproveManagerTokens(lender, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;

        _addInitialLiquidity(
            {
                from:   lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        // allow position manager to take ownership of the position
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 10_000 * 1e27);

        // 3rd party minter mints NFT and memorialize lender positions
        uint256 tokenId = _mintNFT(minter, lender, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), lender);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );

        // minter cannot move liquidity on behalf of lender (is not approved)
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), 2550, 2551
        );
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // minter cannot redeem positions on behalf of lender (is not approved)
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.reedemPositions(reedemParams);

        // minter cannot burn positions NFT on behalf of lender (is not approved)
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, address(_pool)
        );
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.burn(burnParams);

        // lender approves minter to interact with positions NFT on his behalf
        changePrank(lender);
        _positionManager.approve(minter, tokenId);

        changePrank(minter);
        // minter can move liquidity on behalf of lender
        _positionManager.moveLiquidity(moveLiquidityParams);
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2551,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       2551,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );

        // minter can redeem liquidity on behalf of lender
        indexes[0] = 2551;
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2551,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2551,
                lpBalance:   0,
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

        // minter can burn NFT on behalf of lender
        _positionManager.burn(burnParams);
        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);
    }

    function test3rdPartyMinterAndRedeemer() external {
        address lender = makeAddr("lender");
        address minter = makeAddr("minter");
        uint256 mintAmount  = 10000 * 1e18;

        _mintQuoteAndApproveManagerTokens(lender, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;

        _addInitialLiquidity(
            {
                from:   lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        // allow position manager to take ownership of the position
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 10_000 * 1e27);

        // 3rd party minter mints NFT and memorialize lender positions
        changePrank(minter);
        uint256 tokenId = _mintNFT(minter, lender, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), lender);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // lender transfers NFT ownership to minter
        changePrank(lender);
        _positionManager.safeTransferFrom(lender, minter, tokenId);
        assertEq(_positionManager.ownerOf(tokenId), minter);

        // minter is owner so can reddeem LPs
        changePrank(minter);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);
        _assertLenderLpBalance(
            {
                lender:      lender,
                index:       2550,
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      minter,
                index:       2550,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
    }

    function testMayInteractReverts() external {
        address lender  = makeAddr("lender");
        address lender1 = makeAddr("lender1");
        // should revert if token id not minted
        changePrank(lender);
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            11, address(_pool)
        );
        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.burn(burnParams);

        uint256 tokenId = _mintNFT(lender, lender, address(_pool));

        // should revert if user not authorized to interact with tokenId
        changePrank(lender1);
        burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, address(_pool)
        );
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.burn(burnParams);

        // should revert if pool address is not the one associated with tokenId
        changePrank(lender);
        burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, makeAddr("wrongPool")
        );
        vm.expectRevert(IPositionManagerErrors.WrongPool.selector);
        _positionManager.burn(burnParams);
    }

    function testTokenURI() external {
        // should revert if using non-existant tokenId
        vm.expectRevert();
        _positionManager.tokenURI(1);

        address testAddress = makeAddr("testAddress");
        uint256 mintAmount  = 10_000 * 1e18;

        _mintQuoteAndApproveManagerTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;

        _addInitialLiquidity(
            {
                from:   testAddress,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );

        // mint NFT
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        // check retrieval of pool token symbols
        address collateralTokenAddress = IPool(_positionManager.poolKey(tokenId)).collateralAddress();
        address quoteTokenAddress = IPool(_positionManager.poolKey(tokenId)).quoteTokenAddress();
        assertEq(tokenSymbol(collateralTokenAddress), "C");
        assertEq(tokenSymbol(quoteTokenAddress), "Q");
        assertEq(tokenName(collateralTokenAddress), "Collateral");
        assertEq(tokenName(quoteTokenAddress), "Quote");

        // allow position manager to take ownership of the position
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);

        // memorialize position
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        string memory uriString = _positionManager.tokenURI(tokenId);
        // emit log(uriString);
        assertGt(bytes(uriString).length, 0);
    }

}

abstract contract PositionManagerERC721PoolHelperContract is ERC721HelperContract {

    PositionManager  internal _positionManager;

    constructor() ERC721HelperContract() {
        _positionManager = new PositionManager(new ERC20PoolFactory(_ajna), _poolFactory);
        _pool = _deployCollectionPool();
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
    function _mintNFT(address minter_, address lender_, address pool_, bytes32 subsetHash_) internal returns (uint256 tokenId) {
        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(lender_, pool_, subsetHash_);
        
        changePrank(minter_);
        return _positionManager.mint(mintParams);
    }
}

contract PositionManagerERC721PoolTest is PositionManagerERC721PoolHelperContract {
    function testPositionFlowForERC721Pool() external {

        address testAddress1  = makeAddr("testAddress1");
        uint256 mintAmount   = 50_000 * 1e18;
        address testAddress2 = makeAddr("testAddress2");
        uint256 currentTime = block.timestamp;

        _mintQuoteAndApproveManagerTokens(testAddress1, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 3_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 3_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress1, testAddress1, address(_pool), keccak256("ERC721_NON_SUBSET_HASH"));

        // check LPs
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
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
                lender:      testAddress1,
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
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
                lender:      testAddress1,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
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
            tokenId, indexes
        );
        // allow position manager to take ownership of the position
        _pool.approveLpOwnership(address(_positionManager), indexes[0], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[1], 3_000 * 1e27);
        _pool.approveLpOwnership(address(_positionManager), indexes[2], 3_000 * 1e27);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress1, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress1, address(_positionManager), indexes, 9_000 * 1e27);
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
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
        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 1_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 2_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   testAddress1,
                amount: 3_000 * 1e18,
                index:  indexes[2]
            }
        );

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   1_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[1],
                lpBalance:   2_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[2],
                lpBalance:   3_000 * 1e27,
                depositTime: currentTime
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
        emit MemorializePosition(testAddress1, tokenId);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress1, address(_positionManager), indexes, 6_000 * 1e27);
        _positionManager.memorializePositions(memorializeParams);

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 4_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 5_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 6_000 * 1e27);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), indexes[0], indexes[1]
        );

        // move liquidity called by testAddress1
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId);
        changePrank(testAddress1);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check LP balance
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   0,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[1],
                lpBalance:   9_000 * 1e27,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
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
                depositTime: currentTime
            }
        );

        // check position manager state
        assertEq(_positionManager.getLPTokens(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[1]), 9_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId, indexes[2]), 6_000 * 1e27);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // approve and transfer NFT to testAddress2 address
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testAddress1, testAddress2, tokenId);

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testAddress2);

        // construct BurnParams
        changePrank(testAddress2);
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(tokenId, address(_pool));
        // check that NFT cannot be burnt if it tracks postions
        vm.expectRevert(IPositionManagerErrors.LiquidityNotRemoved.selector);
        _positionManager.burn(burnParams);

        // check that NFT cannot be burnt if not owner
        changePrank(testAddress1);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.burn(burnParams);

        // Indexes that have non zero position
        uint256[] memory newIndexes = new uint256[](2);
        newIndexes[0] = indexes[1];
        newIndexes[1] = indexes[2];

        // check old owner cannot redeem positions
        // construct redeem liquidity params
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), newIndexes
        );
        // redeem liquidity called by old owner
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.reedemPositions(reedemParams);

        // check new owner can redeem positions
        changePrank(testAddress2);
        _positionManager.reedemPositions(reedemParams);

         // check pool state
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      address(_positionManager),
                index:       indexes[0],
                lpBalance:   0,
                depositTime: currentTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       indexes[1],
                lpBalance:   9_000 * 1e27,
                depositTime: currentTime
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
                lender:      testAddress1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      testAddress2,
                index:       indexes[2],
                lpBalance:   6_000 * 1e27,
                depositTime: currentTime
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

        // burn and check state changes
        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);

    }
}
