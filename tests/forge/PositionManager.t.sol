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

        // check position info
        address owner = _positionManager.ownerOf(tokenId);
        uint256 lps   = _positionManager.getLPs(tokenId, mintPrice);

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
     *          LPs are checked to verify ownership of position.
     *          Reverts:
     *              Attempts to track when lps aren't allowed to be transfered.
     *              Attempts to set position owner when not owner of the LPs.
     */
    function testTrackPositions() external {
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

        // mint an NFT to later track existing positions into
        uint256 tokenId = _mintNFT(testAddress, testAddress, address(_pool));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2550));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2551));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2552));

        // construct track params struct
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );

        // should revert if access hasn't been granted to manage LP tokens
        vm.expectRevert(IPositionManagerErrors.NotLPsManager.selector);
        _positionManager.trackPositions(trackParams);

        assertEq(_pool.lpManagers(testAddress, indexes[0]), address(0));
        assertEq(_pool.lpManagers(testAddress, indexes[1]), address(0));
        assertEq(_pool.lpManagers(testAddress, indexes[2]), address(0));

        // allow position manager to manage positions LPs
        _pool.approveLpManager(address(_positionManager), indexes);

        assertEq(_pool.lpManagers(testAddress, indexes[0]), address(_positionManager));
        assertEq(_pool.lpManagers(testAddress, indexes[1]), address(_positionManager));
        assertEq(_pool.lpManagers(testAddress, indexes[2]), address(_positionManager));

        // track positions
        vm.expectEmit(true, true, true, true);
        emit TrackPositions(testAddress, tokenId, indexes);
        _positionManager.trackPositions(trackParams);

        // check positions through position manager
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2550));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2551));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2552));

        assertEq(_positionManager.getLPs(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[2]), 3_000 * 1e18);

        // check that LPs are still owned by the owner
        (uint256 lpBalance, ) = _pool.lenderInfo(indexes[0], testAddress);
        assertEq(lpBalance, 3_000 * 1e18);
        (lpBalance, ) = _pool.lenderInfo(indexes[1], testAddress);
        assertEq(lpBalance, 3_000 * 1e18);
        (lpBalance, ) = _pool.lenderInfo(indexes[2], testAddress);
        assertEq(lpBalance, 3_000 * 1e18);

        // check that position manager contract doesn't own any LP at positions
        (lpBalance, ) = _pool.lenderInfo(indexes[0], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenderInfo(indexes[1], address(_positionManager));
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenderInfo(indexes[2], address(_positionManager));
        assertEq(lpBalance, 0);

        // check that the owner cannot approve position manager for same indexes
        indexes = new uint256[](1);
        indexes[0] = 2550;
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.approveLpManager(address(_positionManager), indexes);

        indexes = new uint256[](1);
        indexes[0] = 2551;
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.approveLpManager(address(_positionManager), indexes);

        indexes = new uint256[](1);
        indexes[0] = 2552;
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.approveLpManager(address(_positionManager), indexes);

        // check that the owner can approve position manager for a different index
        indexes = new uint256[](1);
        indexes[0] = 111;
        _pool.approveLpManager(address(_positionManager), indexes);
        assertEq(_pool.lpManagers(testAddress, 111), address(_positionManager));

        indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // check that the owner is not allowed to move quote token at tracked indexes
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.moveQuoteToken(testAddress, 1_000 * 1e18, indexes[0], indexes[1], type(uint256).max);

        // check that the owner is not allowed to remove quote token at tracked indexes
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.removeQuoteToken(1_000 * 1e18, indexes[0]);

        // check that the owner is not allowed to remove collateral at tracked indexes
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.removeCollateral(1_000 * 1e18, indexes[0]);

        // check that the owner is not allowed to kick with deposit at tracked indexes
        vm.expectRevert(IPoolErrors.OwnerNotLPsManager.selector);
        _pool.kickWithDeposit(indexes[0]);

        // check that the owner is allowed to increase LP deposit at an already tracked index
        _pool.addQuoteToken(1_000 * 1e18, indexes[0], type(uint256).max);
        (lpBalance, ) = _pool.lenderInfo(indexes[0], testAddress);
        assertEq(lpBalance, 4_000 * 1e18);

        // check that new indexes can be tracked (current tracked indexes are ignored if already tracked)
        indexes = new uint256[](2);
        indexes[0] = 2553;
        indexes[1] = 2554;

        _pool.approveLpManager(address(_positionManager), indexes);

        // track positions
        trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        vm.expectEmit(true, true, true, true);
        emit TrackPositions(testAddress, tokenId, indexes);
        _positionManager.trackPositions(trackParams);

        assertTrue(_positionManager.isIndexInPosition(tokenId, 2550));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2551));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2552));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2553));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2554));

        // check that same indexes cannot be tracked twice
        trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        vm.expectRevert(IPositionManagerErrors.PositionAlreadyTracked.selector);
        _positionManager.trackPositions(trackParams);

        // untrack positions
        IPositionManagerOwnerActions.UntrackPositionsParams memory untrackParams = IPositionManagerOwnerActions.UntrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.untrackPositions(untrackParams);
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2553));
        assertFalse(_positionManager.isIndexInPosition(tokenId, 2554));

        _pool.approveLpManager(address(_positionManager), indexes);

        _positionManager.trackPositions(trackParams);
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2553));
        assertTrue(_positionManager.isIndexInPosition(tokenId, 2554));
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
        // receiver should whitelist position manager as transferor otherwise transfer will fail
        ContractNFTRecipient secondRecipient = new ContractNFTRecipient(recipientOwner);

        uint256 snapshot = vm.snapshot();
        vm.expectRevert(IPoolErrors.TransferorNotApproved.selector);
        recipientContract.transferNFT(address(_positionManager), address(secondRecipient), 1);

        assertEq(_positionManager.ownerOf(1), address(recipientContract));

        vm.revertTo(snapshot);

        changePrank(address(secondRecipient));
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        changePrank(address(recipientContract));
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

        // check LPs
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

        // check position manager state
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // track positions of testMinter
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;

        changePrank(testMinter);
        _pool.approveLpManager(address(_positionManager), indexes);
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(_positionManager));

        // track positions of testMinter
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.trackPositions(trackParams);

        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // transfer should fail if position manager not listed as transferor by NFT receiver
        vm.expectRevert(IPoolErrors.TransferorNotApproved.selector);
        _pool.transferLPs(testMinter, testReceiver, indexes);

        // receiver whitelists position manager as transferor
        changePrank(testReceiver);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        // approve and transfer NFT to different address
        changePrank(testMinter);
        _positionManager.approve(address(this), tokenId);

        vm.expectEmit(true, true, true, true);
        vm.expectEmit(true, true, true, true);
        emit UntrackPositions(testMinter, tokenId, indexes);
        emit TransferLPs(testMinter, testReceiver, indexes, 15_000 * 1e18);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check NFT position new owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        // check that positions are no longer tracked after transfer
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // check that position manager revoked from old owner position management
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(0));

        // check no manager for new owner position
        assertEq(_pool.lpManagers(testReceiver, indexes[0]), address(0));

        // check old owner doesn't have any position at index
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        // check new owner have position at index and with inherited initial deposit time
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
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

        _addInitialLiquidity({
            from:   testMinter,
            amount: 15_000 * 1e18,
            index:  testIndexPrice
        });

        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        // check LPs
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

        // check position manager state
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // track positions of testMinter
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;

        changePrank(testMinter);
        _pool.approveLpManager(address(_positionManager), indexes);
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(_positionManager));

        // memorialize positions of testMinter
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.trackPositions(trackParams);

        assertTrue(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // transfer should fail if position manager not listed as transferor by NFT receiver
        vm.expectRevert(IPoolErrors.TransferorNotApproved.selector);
        _pool.transferLPs(testMinter, testReceiver, indexes);

        // receiver whitelists position manager as transferor
        changePrank(testReceiver);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        address testSpender = makeAddr("testSpender");

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
                                testSpender,
                                tokenId,
                                0,
                                deadline
                            )
                        )
                    )
                )
            );
            changePrank(testSpender);
            _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, tokenId, deadline, v, r, s );
        }

        // check NFT position new owner
        assertEq(_positionManager.ownerOf(tokenId), testReceiver);

        // check that positions are no longer tracked after transfer
        assertFalse(_positionManager.isIndexInPosition(tokenId, testIndexPrice));

        // check that position manager revoked from old owner position management
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(0));

        // check no manager for new owner position
        assertEq(_pool.lpManagers(testReceiver, indexes[0]), address(0));

        // check old owner doesn't have any position at index
        _assertLenderLpBalance({
            lender:      testMinter,
            index:       testIndexPrice,
            lpBalance:   0,
            depositTime: 0
        });
        // check new owner have position at index and with inherited initial deposit time
        _assertLenderLpBalance({
            lender:      testReceiver,
            index:       testIndexPrice,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
    }

    function testPermitByContract() external {
        address testSpender = makeAddr("spender");

        // deploy NFT receiver contract
        (address nonMintingContractOwner, uint256 nonMintingContractPrivateKey) = makeAddrAndKey("nonMintingContract");
        ContractNFTRecipient recipientContract = new ContractNFTRecipient(nonMintingContractOwner);

        // receiver should list position manager as transferor of LPs
        changePrank(address(recipientContract));
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        // deploy contract minter of the NFT
        (address testContractOwner, uint256 ownerPrivateKey) = makeAddrAndKey("testContractOwner");
        ContractNFTRecipient ownerContract = new ContractNFTRecipient(testContractOwner);
        uint256 tokenId = _mintNFT(address(ownerContract), address(ownerContract), address(_pool));

        changePrank(testSpender);

        // check contract owned nft can't be signed by non owner
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(testSpender, tokenId, deadline, nonMintingContractPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        _positionManager.safeTransferFromWithPermit(address(ownerContract), address(recipientContract), tokenId, deadline, v, r, s );

        // check owner can permit their contract to transfer the NFT
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, ownerPrivateKey);
        _positionManager.safeTransferFromWithPermit(address(ownerContract), address(recipientContract), tokenId, deadline, v, r, s );
    }

    function testPermitReverts() external {
        // generate addresses and set test params
        (address testMinter, uint256 minterPrivateKey) = makeAddrAndKey("testMinter");
        (address testReceiver, uint256 receiverPrivateKey) = makeAddrAndKey("testReceiver");
        address testSpender = makeAddr("spender");

        vm.prank(testMinter);
        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), testMinter);

        changePrank(testSpender);

        // check can't use a deadline in the past
        uint256 deadline = block.timestamp - 1 days;
        (uint8 v, bytes32 r, bytes32 s) = _getPermitSig(testSpender, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-permit-expired");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, tokenId, deadline, v, r, s );

        // check can't self approve
        changePrank(testMinter);
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ERC721Permit: approval to current owner");
        _positionManager.safeTransferFromWithPermit(testMinter, testMinter, tokenId, deadline, v, r, s );

        changePrank(testSpender);

        // check signer is authorized to permit
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, receiverPrivateKey);
        vm.expectRevert("ajna/nft-unauthorized");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, tokenId, deadline, v, r, s );

        // check signature is valid
        deadline = block.timestamp + 1 days;
        (v, r, s) = _getPermitSig(testSpender, tokenId, deadline, minterPrivateKey);
        vm.expectRevert("ajna/nft-invalid-signature");
        _positionManager.safeTransferFromWithPermit(testMinter, testReceiver, tokenId, deadline, 0, r, s );
    }

    /**
     *  @notice Tests NFT position can be burned based on tracked positions attached to it.
     *          Attempts to burn NFT without tracked positions.
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
     *  @notice Tests NFT position can & can't be burned based on tracked positions attached to it.
     *          Owner reverts: attempts to burn NFT with tracked positions.
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

        // track positions of testMinter
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = testIndexPrice;

        changePrank(testMinter);
        _pool.approveLpManager(address(_positionManager), indexes);
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(_positionManager));

        // track positions of testMinter
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.trackPositions(trackParams);

        // construct BurnParams
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(tokenId, address(_pool));
        // check that NFT cannot be burnt if it tracks postions
        vm.expectRevert(IPositionManagerErrors.PositionNotUntracked.selector);
        _positionManager.burn(burnParams);

        // check that NFT cannot be burnt if not owner
        changePrank(notOwner);
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.burn(burnParams);

        // untrack positions of testMinter
        changePrank(testMinter);
        IPositionManagerOwnerActions.UntrackPositionsParams memory untrackParams = IPositionManagerOwnerActions.UntrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.untrackPositions(untrackParams);

        // check that position manager revoked from old owner position management
        assertEq(_pool.lpManagers(testMinter, indexes[0]), address(0));

        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);
    }

    function testMoveLiquidityPermissions() external {
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
        assertEq(_positionManager.getLPs(tokenId1, mintIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLPs(tokenId2, mintIndex), 5_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, moveIndex), 0);
        assertFalse(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress1
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = mintIndex;
        indexes[1] = moveIndex;
        changePrank(testAddress1);
        _pool.approveLpManager(address(_positionManager), indexes);

        // track positions of testAddress1
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId1, address(_pool), indexes
        );
        changePrank(testAddress1);
        _positionManager.trackPositions(trackParams);

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
        assertEq(_positionManager.getLPs(tokenId1, mintIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId1, moveIndex), 0);
        assertEq(_positionManager.getLPs(tokenId2, mintIndex), 5_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, moveIndex), 0);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId1, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );

        // move liquidity called by testAddress1 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId1);
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
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLPs(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPs(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, mintIndex), 5_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, moveIndex), 0);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertFalse(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // allow position manager to take ownership of the position of testAddress2
        changePrank(testAddress2);
        _pool.approveLpManager(address(_positionManager), indexes);

        // memorialize positions of testAddress2
        trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId2, address(_pool), indexes
        );
        changePrank(testAddress2);
        _positionManager.trackPositions(trackParams);

        // check position manager state
        assertEq(_positionManager.getLPs(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPs(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, mintIndex), 5_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, moveIndex), 0);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, moveIndex));

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
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress2, tokenId2);
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
            lender:      testAddress1,
            index:       moveIndex,
            lpBalance:   2_500 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      testAddress2,
            index:       moveIndex,
            lpBalance:   5_500 * 1e18,
            depositTime: _startTime
        });


        // check position manager state
        assertEq(_positionManager.getLPs(tokenId1, mintIndex), 0);
        assertEq(_positionManager.getLPs(tokenId1, moveIndex), 2_500 * 1e18);
        assertEq(_positionManager.getLPs(tokenId2, mintIndex), 0);
        assertEq(_positionManager.getLPs(tokenId2, moveIndex), 5_500 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId1, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId1, moveIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, mintIndex));
        assertTrue(_positionManager.isIndexInPosition(tokenId2, moveIndex));

        // check can't move liquidity if not manager of position
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId2, address(_pool), 1000, 2000, block.timestamp + 30
        );
        changePrank(testAddress2);
        vm.expectRevert(IPositionManagerErrors.NotLPsManager.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
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

        // allow position manager to take ownership of the position
        changePrank(lender);
        _pool.approveLpManager(address(_positionManager), indexes);

        // 3rd party minter mints NFT and tracks lender positions
        changePrank(minter);
        uint256 tokenId = _mintNFT(minter, lender, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), lender);
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );

        // check minter cannot track positions if not approved by lender
        vm.expectRevert(IPositionManagerErrors.NoAuth.selector);
        _positionManager.trackPositions(trackParams);

        // lender approves minter to interact with positions NFT on his behalf
        changePrank(lender);
        _positionManager.approve(minter, tokenId);

        // check minter can track positions when approved by lender
        changePrank(minter);
        _positionManager.trackPositions(trackParams);

        // TODO: check minter can move liquidity on behalf of lender.
        // TODO: One issue on move liquidity is that target index should be also approved by lender calling pool.approveLPsManager so out of minter access
        // TODO: check if that's limitation is acceptable

        // check minter can untrack positions when approved by lender
        IPositionManagerOwnerActions.UntrackPositionsParams memory untrackParams = IPositionManagerOwnerActions.UntrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.untrackPositions(untrackParams);

        // minter can burn NFT on behalf of lender
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(tokenId, address(_pool));
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
        _pool.approveLpManager(address(_positionManager), indexes);

        // 3rd party minter mints NFT and memorialize lender positions
        changePrank(minter);
        uint256 tokenId = _mintNFT(minter, lender, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), lender);

        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );

        // lender approves minter to interact with positions NFT on his behalf
        changePrank(lender);
        _positionManager.approve(minter, tokenId);

        changePrank(minter);
        // check minter can track positions when approved by lender
        _positionManager.trackPositions(trackParams);
        // minter approves position manager as transferor in order to receive LPs on NFT transfer
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        // lender transfers NFT ownership and LPs to minter
        changePrank(lender);
        _positionManager.safeTransferFrom(lender, minter, tokenId);
        assertEq(_positionManager.ownerOf(tokenId), minter);

        _assertLenderLpBalance({
            lender:      lender,
            index:       2550,
            lpBalance:   0,
            depositTime: 0
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

        // allow position manager to manage position
        _pool.approveLpManager(address(_positionManager), indexes);

        // track position
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.trackPositions(trackParams);

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

        // check LPs
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
        assertEq(_positionManager.getLPs(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[2]), 3_000 * 1e18);
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertFalse(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct track params struct
        IPositionManagerOwnerActions.TrackPositionsParams memory trackParams = IPositionManagerOwnerActions.TrackPositionsParams(
            tokenId, address(_pool), indexes
        );
        // allow position manager to take ownership of the position
        _pool.approveLpManager(address(_positionManager), indexes);

        // track positions into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TrackPositions(testAddress1, tokenId, indexes);
        _positionManager.trackPositions(trackParams);

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
        assertEq(_positionManager.getLPs(tokenId, indexes[0]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[1]), 3_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[2]), 3_000 * 1e18);
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
            lpBalance:   4_000 * 1e18,
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
            lpBalance:   5_000 * 1e18,
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
            lpBalance:   6_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLPs(tokenId, indexes[0]), 4_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[1]), 5_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[2]), 6_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), indexes[0], indexes[1], block.timestamp + 30
        );

        // move liquidity called by testAddress1
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId);
        changePrank(testAddress1);
        _positionManager.moveLiquidity(moveLiquidityParams);

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
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[1],
            lpBalance:   9_000 * 1e18,
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
            lpBalance:   6_000 * 1e18,
            depositTime: currentTime
        });
        _assertLenderLpBalance({
            lender:      address(_positionManager),
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // check position manager state
        assertEq(_positionManager.getLPs(tokenId, indexes[0]), 0);
        assertEq(_positionManager.getLPs(tokenId, indexes[1]), 9_000 * 1e18);
        assertEq(_positionManager.getLPs(tokenId, indexes[2]), 6_000 * 1e18);
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[0]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[1]));
        assertTrue(_positionManager.isIndexInPosition(tokenId, indexes[2]));

        // approve and transfer NFT to testAddress2 address
        // testAddress2 should whitelist position manager as transferor prior of NFT / LPs transfer
        changePrank(testAddress2);
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLpTransferors(transferors);

        changePrank(testAddress1);
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testAddress1, testAddress2, tokenId);

        // check owner
        assertEq(_positionManager.ownerOf(tokenId), testAddress2);

        // check LPs are owned by NFT receiver
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
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
            lpBalance:   0,
            depositTime: 0
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
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      testAddress1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
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
            depositTime: 0
        });

        // new owner can burn NFT as there's no position tracked
        changePrank(testAddress2);
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, address(_pool)
        );
        _positionManager.burn(burnParams);

        vm.expectRevert("ERC721: invalid token ID");
        _positionManager.ownerOf(tokenId);

    }
}
