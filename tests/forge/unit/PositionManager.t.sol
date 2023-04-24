// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { Base64 } from '@base64-sol/base64.sol';

import { ERC20HelperContract } from '../unit/ERC20Pool/ERC20DSTestPlus.sol';
import { ERC721HelperContract } from '../unit/ERC721Pool/ERC721DSTestPlus.sol';

import 'src/interfaces/position/IPositionManager.sol';
import 'src/PositionManager.sol';
import 'src/libraries/helpers/SafeTokenNamer.sol';
import 'src/libraries/helpers/PoolHelper.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';

import '../utils/ContractNFTRecipient.sol';
import '../utils/ContractNFTSpender.sol';

abstract contract PositionManagerERC20PoolHelperContract is ERC20HelperContract {

    PositionManager  internal _positionManager;

    constructor() ERC20HelperContract() {
        _positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));
    }

    function _mintQuoteAndApproveManagerTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        vm.prank(operator_);
        _quote.approve(address(_positionManager), type(uint256).max);
        _pool.approveLPTransferors(transferors);
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
        address spender_,
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
                                spender_,
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
        assertEq(tokenId, 1);

        // check position info
        address owner = _positionManager.ownerOf(tokenId);
        uint256 lps   = _positionManager.getLP(tokenId, _indexOf(mintPrice));

        assertEq(owner, testAddress);
        assertEq(lps,   0);

        // deploy a new factory to simulate creating a pool outside of expected factories
        ERC20PoolFactory invalidFactory = new ERC20PoolFactory(_ajna);
        address invalidPool = invalidFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // check can't mint an NFT associated with a non ajna pool
        vm.expectRevert(IPositionManagerErrors.NotAjnaPool.selector);
        _mintNFT(testAddress, testAddress, invalidPool);
    }

    /**
     *  @notice Tests attachment of a created position to an already existing NFT.
     *          LP are checked to verify ownership of position.
     *          Reverts:
     *              Attempts to memorialize when lps aren't allowed to be transfered.
     *              Attempts to set position owner when not owner of the LP.
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

        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2550));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2551));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2552));

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );

        // should revert if access hasn't been granted to transfer LP
        vm.expectRevert(IPoolErrors.NoAllowance.selector);
        _positionManager.memorializePositions(memorializeParams);

        // allow position manager to take ownership of the position
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 3_000 * 1e18;
        amounts[1] = 3_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testAddress, address(_positionManager), indexes, 9_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId, indexes);
        _positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLP = _positionManager.getLP(tokenId, indexes[0]);
        assertGt(positionAtPriceOneLP, 0);

        // check lps at non added to price
        uint256 positionAtWrongPriceLP = _positionManager.getLP(tokenId, uint256(MAX_BUCKET_INDEX));
        assertEq(positionAtWrongPriceLP, 0);

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

        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        // check LP
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        // allow position manager to take ownership of the position
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 3_000 * 1e18;
        amounts[1] = 3_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testAddress, address(_positionManager), indexes, 9_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId, indexes);
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 3_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, indexes[0]));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, indexes[1]));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, indexes[2]));

        (uint256 lps, uint256 depositTime) = _positionManager.getPositionInfo(tokenId, indexes[0]);
        assertEq(lps, 3_000 * 1e18);
        assertEq(depositTime, _startTime);
        (lps, depositTime) = _positionManager.getPositionInfo(tokenId, indexes[1]);
        assertEq(lps, 3_000 * 1e18);
        assertEq(depositTime, _startTime);
        (lps, depositTime) = _positionManager.getPositionInfo(tokenId, indexes[2]);
        assertEq(lps, 3_000 * 1e18);
        assertEq(depositTime, _startTime);

        // add more liquidity
        _addInitialLiquidity({
            from:   testAddress,
            amount: 1_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 2_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        // check LP balance
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[0],
            lpBalance:   1_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[1],
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 3_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // allow position manager to take ownership of the new LP
        amounts[0] = 1_000 * 1e18;
        amounts[1] = 2_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // rememorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testAddress, address(_positionManager), indexes, 6_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId, indexes);
        _positionManager.memorializePositions(memorializeParams);

        // check LP balance
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   4_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   6_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 4_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 5_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 6_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));
    }

    /**
     *  @notice Tests attachment of multiple previously created position to already existing NFTs.
     *          LP are checked to verify ownership of position.
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

        _addInitialLiquidity({
            from:   testLender1,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testLender1,
            amount: 3_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testLender1,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        _addInitialLiquidity({
            from:   testLender2,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testLender2,
            amount: 3_000 * 1e18,
            index:  indexes[3]
        });

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = _mintNFT(testLender1, testLender1, address(_pool));
        uint256 tokenId2 = _mintNFT(testLender2, testLender2, address(_pool));

        // check LP
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[3],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[3],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[3],
            lpBalance:   0,
            depositTime: 0
        });

        assertEq(_positionManager.getLP(tokenId1, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId1, indexes[1]), 0);
        assertEq(_positionManager.getLP(tokenId1, indexes[2]), 0);

        assertEq(_positionManager.getLP(tokenId2, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId2, indexes[3]), 0);

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
        uint256[] memory transferIndexes = new uint256[](3);
        transferIndexes[0] = 2550;
        transferIndexes[1] = 2551;
        transferIndexes[2] = 2552;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 3_000 * 1e18;
        amounts[1] = 3_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), transferIndexes, amounts);

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testLender1, address(_positionManager), lender1Indexes, 9_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1, lender1Indexes);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender1,
            index:       indexes[3],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[3],
            lpBalance:   0,
            depositTime: 0
        });

        assertEq(_positionManager.getLP(tokenId1, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId1, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId1, indexes[2]), 3_000 * 1e18);

        (poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        changePrank(testLender2);
        transferIndexes = new uint256[](2);
        transferIndexes[0] = indexes[0];
        transferIndexes[1] = indexes[3];
        amounts = new uint256[](2);
        amounts[0] = 3_000 * 1e18;
        amounts[1] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), transferIndexes, amounts);

        // memorialize lender 2 quote tokens into minted NFT
        uint256[] memory newIndexes = new uint256[](2);
        newIndexes[0] = 2550;
        newIndexes[1] = 2553;

        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, newIndexes
        );

        vm.expectEmit(true, true, true, true);
        emit TransferLP(testLender2, address(_positionManager), newIndexes, 6_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender2, tokenId2, newIndexes);
        _positionManager.memorializePositions(memorializeParams);

        // // check lender, position manager,  and pool state
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   6_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testLender2,
            index:       indexes[3],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[3],
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });

        assertEq(_positionManager.getLP(tokenId1, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId1, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId1, indexes[2]), 3_000 * 1e18);

        assertEq(_positionManager.getLP(tokenId2, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId2, indexes[3]), 3_000 * 1e18);

        (poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize, 15_000 * 1e18);
    }

    function testMemorializeAndRedeemBucketBankruptcy() external {
        address testMinter        = makeAddr("testMinter");
        address testBorrower      = makeAddr("testBorrower");
        address testBorrowerTwo   = makeAddr("testBorrowerTwo");

        uint256 testIndex = _i9_91;

        /************************/
        /*** Setup Pool State ***/
        /************************/

        _mintCollateralAndApproveTokens(testBorrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(testBorrowerTwo, 1_000 * 1e18);

        // add initial liquidity
        _mintQuoteAndApproveManagerTokens(testMinter, 500_000 * 1e18);

        _addInitialLiquidity({
            from:   testMinter,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     testBorrower,
            borrower: testBorrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       testBorrower,
            amount:     19.25 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     testBorrowerTwo,
            borrower: testBorrowerTwo,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       testBorrowerTwo,
            amount:     7_980 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        _borrow({
            from:       testBorrowerTwo,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /****************************/
        /*** Memorialize Position ***/
        /****************************/

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndex,
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndex,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndex));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndex;
        // allow position manager to take ownership of the position of testMinter
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndex,
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime
        });

        // check position state
        (uint256 lps, uint256 depositTime) = _positionManager.getPositionInfo(tokenId, testIndex);
        assertEq(lps, 2_000 * 1e18);
        assertEq(depositTime, _startTime);

        // check position is not bankrupt
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, testIndex));

        /*************************/
        /*** Bucket Bankruptcy ***/
        /*************************/

        // Skip to make borrower undercollateralized
        skip(100 days);

        // minter kicks borrower
        _kick({
            from:           testMinter,
            borrower:       testBorrowerTwo,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        // take entire collateral
        _take({
            from:            testMinter,
            borrower:        testBorrowerTwo,
            maxCollateral:   1_000 * 1e18,
            bondChange:      6.531114528261135360 * 1e18,
            givenAmount:     653.111452826113536000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _settle({
            from:        testMinter,
            borrower:    testBorrowerTwo,
            maxDepth:    10,
            settledDebt: 9_891.935520844277346922 * 1e18
        });

        // bucket is insolvent, balances are reset
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // check position is bankrupt
        assertTrue(_positionManager.isPositionBucketBankrupt(tokenId, testIndex));

        // redeem should fail as the bucket has bankrupted
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );
        vm.expectRevert(IPositionManagerErrors.BucketBankrupt.selector);
        _positionManager.reedemPositions(reedemParams);

        // move liquidity should fail as the bucket has bankrupted
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_91, _i9_72, block.timestamp + 30
        );
        vm.expectRevert(IPositionManagerErrors.BucketBankrupt.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check lender state after bankruptcy before rememorializing
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndex,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check can rememorialize additional liquidity into the bankrupted bucket
        skip(3 days);
        vm.roll(block.number + 1);
        amounts = new uint256[](1);
        amounts[0] = 30_000 * 1e18;

        changePrank(testMinter);
        _pool.addQuoteToken(amounts[0], _i9_91, type(uint256).max);

        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        _pool.approveLPTransferors(transferors);
        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check lender state after bankruptcy after rememorializing
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndex,
            lpBalance:   0,
            depositTime: block.timestamp
        });
        // check position manager lp balance does not account 2000 lps memorialized before bucket bankruptcy
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndex,
            lpBalance:   30_000 * 1e18,
            depositTime: block.timestamp
        });

        // check position is not bankrupt
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, testIndex));
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

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LP
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15_000 * 1e18;
        // allow position manager to take ownership of the position of testMinter
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // allow position manager as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 15_000 * 1e18);
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
        // allow position manager as transferor
        _pool.approveLPTransferors(transferors);

        _positionManager.reedemPositions(reedemParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
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
        _mintQuoteAndApproveManagerTokens(testMinter, 50_000 * 1e18);

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LP
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15_000 * 1e18;
        // allow position manager to take ownership of the position of testMinter
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 15_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // deploy spender contract
        ContractNFTSpender spenderContract = new ContractNFTSpender(address(_positionManager));

        {
            uint256 deadline = block.timestamp + 10000;
            (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(address(spenderContract), tokenId, deadline, minterPrivateKey);
            changePrank(testMinter);
            spenderContract.transferFromWithPermit(testReceiver, tokenId, deadline, v, r, s);
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
        // allow position manager as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        _positionManager.reedemPositions(reedemParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));
    }

    function testPermitByContract() external {
        // deploy recipient contract
        (address recipientContractOwner, uint256 recipientContractOwnerPrivateKey) = makeAddrAndKey("recipientContract");
        ContractNFTRecipient recipientContract = new ContractNFTRecipient(recipientContractOwner);

        // deploy contract to mint the NFT
        (address mintingContractOwner, uint256 mintingOwnerPrivateKey) = makeAddrAndKey("mintingContractOwner");
        ContractNFTRecipient mintingContract = new ContractNFTRecipient(mintingContractOwner);
        uint256 tokenId = _mintNFT(address(mintingContract), address(mintingContract), address(_pool));

        // deploy spender contract
        ContractNFTSpender spenderContract = new ContractNFTSpender(address(_positionManager));

        // check contract owned nft can't be signed by non owner
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(address(spenderContract), tokenId, deadline, recipientContractOwnerPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        spenderContract.transferFromWithPermit(address(recipientContract), tokenId, deadline, v, r, s );

        // check owner can permit their contract to transfer the NFT
        changePrank(address(mintingContract));
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(address(spenderContract), tokenId, deadline, mintingOwnerPrivateKey);
        spenderContract.transferFromWithPermit(address(recipientContract), tokenId, deadline, v, r, s );
    }

    function testPermitReverts() external {
        // generate addresses and set test params
        (address testMinter, uint256 minterPrivateKey) = makeAddrAndKey("testMinter");
        (address testReceiver, uint256 receiverPrivateKey) = makeAddrAndKey("testReceiver");
        address testSpender = makeAddr("spender");

        // deploy spender contract
        ContractNFTSpender spenderContract = new ContractNFTSpender(address(_positionManager));

        changePrank(testMinter);
        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check can't use a deadline in the past
        uint256 deadline = block.timestamp - 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(testSpender, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-permit-expired");
        spenderContract.transferFromWithPermit(testReceiver, tokenId, deadline, v, r, s );

        // check signer is authorized to permit
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, receiverPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        spenderContract.transferFromWithPermit(testReceiver, tokenId, deadline, v, r, s );

        // check signature is valid
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-invalid-signature");
        spenderContract.transferFromWithPermit(testReceiver, tokenId, deadline, 0, r, s );

        // check can't self approve
        (v, r, s) = _getPermitSig(testMinter, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ERC721Permit: approval to current owner");
        _positionManager.permit(testMinter, tokenId, deadline, v, r, s);
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

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15_000 * 1e18;
        // allow position manager to take ownership of the position of testMinter
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // approve position manager as a transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

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

    function testMoveLiquidityPermissions() external tearDown {
        // generate a new address
        address testAddress = makeAddr("testAddress");
        address notOwner    = makeAddr("notOwner");
        _mintQuoteAndApproveManagerTokens(testAddress, 10_000 * 1e18);

        _addInitialLiquidity({
            from:   testAddress,
            amount: 10_000 * 1e18,
            index:  2550
        });

        // mint position NFT
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), 2550, 2551, block.timestamp + 30
        );

        // move liquidity should fail because is not performed by owner
        changePrank(notOwner);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testMoveLiquidity() external tearDown {
        // generate a new address
        address testAddress1 = makeAddr("testAddress1");
        address testAddress2 = makeAddr("testAddress2");
        address testAddress3 = makeAddr("testAddress3");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintQuoteAndApproveManagerTokens(testAddress1, 10_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(testAddress2, 10_000 * 1e18);
        _mintCollateralAndApproveTokens(testAddress3, 10_000 * 1e18);

        _addInitialLiquidity({
            from:   testAddress1,
            amount: 2_500 * 1e18,
            index:  mintIndex
        });
        _addInitialLiquidity({
            from:   testAddress2,
            amount: 5_500 * 1e18,
            index:  mintIndex
        });

        uint256 tokenId1 = _mintNFT(testAddress1, testAddress1, address(_pool));
        uint256 tokenId2 = _mintNFT(testAddress2, testAddress2, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId1), testAddress1);
        assertEq(_positionManager.ownerOf(tokenId2), testAddress2);

        // check pool state
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       mintIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       mintIndex,
            lpBalance:   5_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0 * 1e18,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress1
        changePrank(testAddress1);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2_500 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize positions of testAddress1
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId1, indexes
        );
        changePrank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       mintIndex,
            lpBalance:   5_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId1, mintIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLP(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, moveIndex), 0);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId1, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );

        // move liquidity called by testAddress1 owner
        uint256 lpRedeemed = 2_500 * 1e18;
        uint256 lpAwarded  = 2_500 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId1, mintIndex, moveIndex, lpRedeemed, lpAwarded);
        changePrank(address(testAddress1));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       mintIndex,
            lpBalance:   5_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLP(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress2
        changePrank(testAddress2);
        amounts[0] = 5_500 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize positions of testAddress2
        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, indexes
        );
        changePrank(testAddress2);
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
       _assertLenderLpBalance({
            lender:      testAddress1,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   5_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLP(tokenId2, mintIndex), 5_500 * 1e18);
        assertEq(_positionManager.getLP(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // construct move liquidity params
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId2, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );

        _addCollateral({
            from:    testAddress3,
            amount:  10_000 * 1e18,
            index:   mintIndex,
            lpAward: 30_108_920.22197881557845 * 1e18
        });

        // move liquidity called by testAddress2 owner
        lpRedeemed = 5_500 * 1e18;
        lpAwarded  = 5_500 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress2, tokenId2, mintIndex, moveIndex, lpRedeemed, lpAwarded);
        changePrank(address(testAddress2));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
       _assertLenderLpBalance({
            lender:      testAddress1,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   0 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   8_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLP(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLP(tokenId2, moveIndex), 5_500 * 1e18);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // check can't move liquidity from position with no liquidity
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId2, address(_pool), 1000, 2000, block.timestamp + 30
        );
        changePrank(address(testAddress2));
        vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    function testMoveLiquidityWithInterest() external tearDown {
        address lender1  = makeAddr("lender1");
        address lender2  = makeAddr("lender2");
        address borrower = makeAddr("borrower");
        _mintQuoteAndApproveManagerTokens(lender1, 2_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(lender2, 3_000 * 1e18);
        _mintCollateralAndApproveTokens(borrower, 250 * 1e18);
        _mintQuoteAndApproveTokens(borrower, 500 * 1e18);

        uint256 mintIndex = _i9_91;
        uint256 moveIndex = _i9_52;

        // two lenders add liquidity to the same bucket
        _addInitialLiquidity({
            from:   lender1,
            amount: 2_000 * 1e18,
            index:  mintIndex
        });
        _addInitialLiquidity({
            from:   lender2,
            amount: 3_000 * 1e18,
            index:  mintIndex
        });
        skip(2 hours);

        // borrower draws debt
        _drawDebt({
            from:               borrower,
            borrower:           borrower,
            amountToBorrow:     1_000 * 1e18,
            limitIndex:         mintIndex,
            collateralToPledge: 250 * 1e18,
            newLup:             _p9_91
        });
        skip(22 hours);

        // lenders mint and memorialize positions
        changePrank(lender1);
        uint256 tokenId1 = _mintNFT(lender1, lender1, address(_pool));
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = 
            IPositionManagerOwnerActions.MemorializePositionsParams(tokenId1, indexes);
        _positionManager.memorializePositions(memorializeParams);
        skip(1 days);

        changePrank(lender2);
        uint256 tokenId2 = _mintNFT(lender2, lender2, address(_pool));
        amounts[0] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(tokenId2, indexes);
        _positionManager.memorializePositions(memorializeParams);
        skip(1 days);

        // check pool state
        _assertLenderLpBalance({
            lender:      lender1,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      lender2,
            index:       mintIndex,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });

        // lender 1 moves liquidity
        changePrank(lender1);
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = 
            IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId1, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       mintIndex,
            lpBalance:   3_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       moveIndex,
            lpBalance:   1_999.865897356084855977 * 1e18,
            depositTime: _startTime
        });
        skip(1 weeks);

        // lender1 redeems their NFT
        changePrank(lender1);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);
        indexes[0] = moveIndex;
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = 
            IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId1, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);
        skip(2 days);

        // borrower repays
        _repayDebt({
            from:             borrower,
            borrower:         borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     1_002.608307827389905517 * 1e18,
            collateralToPull: 250 * 1e18,
            newLup:           MAX_PRICE
        });

        // lender2 redeems their NFT
        skip(1 days);
        changePrank(lender2);
        _pool.approveLPTransferors(transferors);
        indexes[0] = mintIndex;
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId2, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);

        // tearDown ensures buckets are empty
    }

    function testRedeemPositions() external {
        address testMinter     = makeAddr("testMinter");
        address notOwner       = makeAddr("notOwner");
        uint256 testIndexPrice = 2550;

        // add initial liquidity
        uint256 mintAmount = 50_000 * 1e18;
        _mintQuoteAndApproveManagerTokens(testMinter, mintAmount);

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 15_000 * 1e18);
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
        emit RedeemPosition(testMinter, tokenId, indexes);
        changePrank(testMinter);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // should fail if trying to redeem one more time
        vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
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
        vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
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

        _addInitialLiquidity({
            from:   testReceiver,
            amount: 25_000 * 1e18,
            index:  testIndexPrice
        });
        _addInitialLiquidity({
            from:   testReceiver,
            amount: 15_000 * 1e18,
            index:  2551
        });

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   25_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       2551,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // memorialize positions
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;
        // allow position manager to take ownership of the position of testMinter
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 15_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        // approve position manager as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);
        // memorialize positions of testMinter
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   25_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       2551,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 15_000 * 1e18);
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
        changePrank(testReceiver);
        vm.expectEmit(true, true, true, true);
        emit TransferLP(address(_positionManager), testReceiver, indexes, 15_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit RedeemPosition(testReceiver, tokenId, indexes);
        _pool.approveLPTransferors(transferors);
        _positionManager.reedemPositions(reedemParams);

        // check pool state
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   40_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       2551,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, testIndexPrice), 0);
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

        _addInitialLiquidity({
            from:   lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _assertLenderLpBalance({
            lender:      lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2550,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2550,
            lpBalance:   0,
            depositTime: 0
        });

        // allow position manager to take ownership of the position
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        // 3rd party minter mints NFT and memorialize lender positions
        uint256 tokenId = _mintNFT(minter, lender, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), lender);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance({
            lender:      lender,
            index:       2550,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2550,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });

        // minter cannot move liquidity on behalf of lender (is not approved)
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), 2550, 2551, block.timestamp + 30
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

        _assertLenderLpBalance({
            lender:      lender,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2551,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });

        // minter can redeem liquidity on behalf of lender
        indexes[0] = 2551;
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.reedemPositions(reedemParams);

        _assertLenderLpBalance({
            lender:      lender,
            index:       2551,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2551,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       2551,
            lpBalance:   0,
            depositTime: _startTime
        });

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

        _addInitialLiquidity({
            from:   lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _assertLenderLpBalance({
            lender:      lender,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2550,
            lpBalance:   0,
            depositTime: 0
        });

        // allow position manager to take ownership of the position
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

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

        // minter is owner so can reddeem LP
        changePrank(minter);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), indexes
        );

        // minter approves position manager as a transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        _positionManager.reedemPositions(reedemParams);

        _assertLenderLpBalance({
            lender:      lender,
            index:       2550,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      minter,
            index:       2550,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
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

        _addInitialLiquidity({
            from:   testAddress,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });

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
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize position
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        string memory uriString = _positionManager.tokenURI(tokenId);
        // emit log(uriString);
        assertGt(bytes(uriString).length, 0);
    }

    function testMemorializePositionsTwoAccountsSameBucket() external {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        uint256 mintAmount  = 10_000 * 1e18;

        uint256 lpBalance;
        uint256 depositTime;

        _mintQuoteAndApproveManagerTokens(alice, mintAmount);
        _mintQuoteAndApproveManagerTokens(bob, mintAmount);

        // call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3_000 * 1e18;
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        // alice adds liquidity now
        _addInitialLiquidity({
            from:   alice,
            amount: amounts[0],
            index:  indexes[0]
        });
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], alice);
        uint256 aliceDepositTime = block.timestamp;
        assertEq(lpBalance, amounts[0]);
        assertEq(depositTime, aliceDepositTime);

        // bob adds liquidity later
        skip(1 hours);
        _addInitialLiquidity({
            from:   bob,
            amount: amounts[0],
            index:  indexes[0]
        });
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], bob);
        assertEq(lpBalance, amounts[0]);
        assertEq(depositTime, aliceDepositTime + 1 hours);


        // bob memorializes first, alice memorializes second
        address[] memory addresses = new address[](2);
        addresses[0] = bob;
        addresses[1] = alice;
        uint256[] memory tokenIds = new uint256[](2);

        // bob and alice mint an NFT to later memorialize existing positions into
        tokenIds[0] = _mintNFT(bob, bob, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenIds[0], 2550));
        tokenIds[1] = _mintNFT(alice, alice, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenIds[1], 2550));

        for (uint256 i = 0; i < addresses.length; ++i) {
            // construct memorialize params struct
            IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
                tokenIds[i], indexes
            );

            // allow position manager to take ownership of the position
            changePrank(addresses[i]);
            _pool.approveLPTransferors(transferors);
            _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

            // memorialize quote tokens into minted NFT
            vm.expectEmit(true, true, true, true);
            emit TransferLP(addresses[i], address(_positionManager), indexes, amounts[0]);
            vm.expectEmit(true, true, true, true);
            emit MemorializePosition(addresses[i], tokenIds[i], indexes);

            _positionManager.memorializePositions(memorializeParams);
        }

        // LP transferred to position manager
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], alice);
        assertEq(lpBalance, 0);
        assertEq(depositTime, aliceDepositTime);
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], bob);
        assertEq(lpBalance, 0);
        assertEq(depositTime, aliceDepositTime + 1 hours);
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], address(_positionManager));
        assertEq(lpBalance, 6_000 * 1e18);
        assertEq(depositTime, aliceDepositTime + 1 hours);

        // both alice and bob redeem
        for (uint256 i = 0; i < addresses.length; ++i) {
            // construct memorialize params struct
            IPositionManagerOwnerActions.RedeemPositionsParams memory params = IPositionManagerOwnerActions.RedeemPositionsParams(
                tokenIds[i], address(_pool), indexes
            );
            changePrank(addresses[i]);
            _positionManager.reedemPositions(params);
        }

        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], alice);
        assertEq(lpBalance, 3_000 * 1e18);
        assertEq(depositTime, aliceDepositTime + 1 hours);
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], bob);
        assertEq(lpBalance, 3_000 * 1e18);
        assertEq(depositTime, aliceDepositTime + 1 hours);
        (lpBalance, depositTime) = _pool.lenderInfo(indexes[0], address(_positionManager));
        assertEq(lpBalance, 0);
        assertEq(depositTime, aliceDepositTime + 1 hours);

        // attempt to redeem again should fail
        for (uint256 i = 0; i < addresses.length; ++i) {
            // construct memorialize params struct
            IPositionManagerOwnerActions.RedeemPositionsParams memory params = IPositionManagerOwnerActions.RedeemPositionsParams(
                tokenIds[i], address(_pool), indexes
            );
            changePrank(addresses[i]);
            vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
            _positionManager.reedemPositions(params);
        }
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

        _addInitialLiquidity({
            from:   testAddress1,
            amount: 3_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testAddress1,
            amount: 3_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testAddress1,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = _mintNFT(testAddress1, testAddress1, address(_pool), keccak256("ERC721_NON_SUBSET_HASH"));

        // check LP
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, indexes
        );
        // allow position manager to take ownership of the position
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 3_000 * 1e18;
        amounts[1] = 3_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // approve position manager as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testAddress1, address(_positionManager), indexes, 9_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress1, tokenId, indexes);
        _positionManager.memorializePositions(memorializeParams);

        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 3_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // add more liquidity
        _addInitialLiquidity({
            from:   testAddress1,
            amount: 1_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   testAddress1,
            amount: 2_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   testAddress1,
            amount: 3_000 * 1e18,
            index:  indexes[2]
        });

        // check LP balance
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   1_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   2_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   3_000 * 1e18,
            depositTime: currentTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 3_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // allow position manager to take ownership of the new LP
        amounts = new uint256[](3);
        amounts[0] = 1_000 * 1e18;
        amounts[1] = 2_000 * 1e18;
        amounts[2] = 3_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // approve position manager as transferor
        _pool.approveLPTransferors(transferors);

        // rememorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLP(testAddress1, address(_positionManager), indexes, 6_000 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress1, tokenId, indexes);
        _positionManager.memorializePositions(memorializeParams);

        // check LP balance
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   4_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   5_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   6_000 * 1e18,
            depositTime: currentTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 4_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 5_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 6_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), indexes[0], indexes[1], block.timestamp + 30
        );

        // move liquidity called by testAddress1
        uint256 lpRedeemed = 4_000 * 1e18;
        uint256 lpAwarded  = 4_000 * 1e18;
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId, indexes[0], indexes[1], lpRedeemed, lpAwarded);
        changePrank(testAddress1);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check LP balance
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   9_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   6_000 * 1e18,
            depositTime: currentTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 9_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 6_000 * 1e18);
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
        _pool.approveLPTransferors(transferors);
        _positionManager.reedemPositions(reedemParams);

         // check pool state
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[0],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       indexes[1],
            lpBalance:   9_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[1],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       indexes[2],
            lpBalance:   6_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: currentTime
        });

        // check position manager state
        assertEq(_positionManager.getLP(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[1]), 0);
        assertEq(_positionManager.getLP(tokenId, indexes[2]), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // burn and check state changes
        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);

    }
}
