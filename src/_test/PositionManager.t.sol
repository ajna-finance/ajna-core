// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

contract PositionManagerTest is DSTestPlus {
    PositionManager internal positionManager;
    ERC20Pool internal pool;
    ERC20PoolFactory internal factory;

    CollateralToken internal collateral;
    QuoteToken internal quote;

    // UserWithQuoteToken internal alice;
    address alice;

    // uint256 constant maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 constant approveBig = 50000000000 * 1e18;

    // nonce for generating random addresses
    uint16 nonce = 0;

    function setUp() public {
        alice = 0x02B9219F667d91fBe64F8f77F691dE3D1000F223;

        collateral = new CollateralToken();
        quote = new QuoteToken();

        // TODO: move logic to internal methods
        quote.mint(alice, 30000000000 * 1e18);

        factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);
        positionManager = new PositionManager();
    }

    function mintAndApproveQuoteTokens(
        address operator,
        uint256 mintAmount,
        uint256 approvalAmount
    ) private {
        quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        quote.approve(address(pool), approvalAmount);
        vm.prank(operator);
        quote.approve(address(positionManager), approvalAmount);
    }

    function mintAndApproveCollateralTokens(
        UserWithCollateral operator,
        uint256 mintAmount
    ) private {
        collateral.mint(address(operator), mintAmount * 1e18);

        operator.approveToken(collateral, address(pool), mintAmount);
        operator.approveToken(collateral, address(positionManager), mintAmount);
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT(
        address minter,
        uint256 mintAmount,
        uint256 mintPrice
    ) private returns (uint256 tokenId) {
        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(minter, address(pool), mintAmount, mintPrice);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(minter, mintAmount, mintPrice);

        vm.prank(mintParams.recipient);
        return positionManager.mint(mintParams);
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        address addr = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(nonce, blockhash(block.number)))
                )
            )
        );
        nonce++;
        return addr;
    }

    function testMint() public {
        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice = 1000 * 10**18;

        mintAndApproveQuoteTokens(alice, mintAmount, approveBig);

        uint256 tokenId = mintNFT(alice, mintAmount, mintPrice);

        require(tokenId != 0, "tokenId nonce not incremented");
        assertEq(pool.totalQuoteToken(), mintAmount);

        // check position info
        (address owner, ) = positionManager.positions(tokenId);
        uint256 lpTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, alice);
        assert(lpTokens != 0);
    }

    function testMintPermissions() public {
        address recipient = generateAddress();
        address externalCaller = generateAddress();
        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice = 1000 * 10**18;

        mintAndApproveQuoteTokens(recipient, mintAmount, approveBig);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(recipient, address(pool), mintAmount, mintPrice);

        // should revert if called by a non-recipient address
        vm.prank(externalCaller);
        vm.expectRevert("Ajna/wrong-caller");
        positionManager.mint(mintParams);
    }

    // TODO: implement test case where multiple users mints multiple NFTs
    function testMintMultiple() public {}

    // TODO: implement test case where caller is not an EOA
    function testMintToContract() public {}

    function testIncreaseLiquidity() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, mintAmount, mintPrice);

        // check position info
        (address originalPositionOwner, ) = positionManager.positions(tokenId);
        uint256 originalLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens != 0);

        uint256 amountToAdd = 50000;

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(testAddress, amountToAdd, mintPrice);

        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParams = IPositionManager
                .IncreaseLiquidityParams(
                    tokenId,
                    testAddress,
                    address(pool),
                    amountToAdd,
                    mintPrice
                );

        vm.prank(testAddress);
        positionManager.increaseLiquidity(increaseLiquidityParams);

        assertEq(pool.totalQuoteToken(), mintAmount + amountToAdd);

        (address updatedPositionOwner, ) = positionManager.positions(tokenId);
        uint256 updatedLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assert(updatedLPTokens > originalLPTokens);
    }

    function testDecreaseLiquidityNoDebt() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, mintAmount, mintPrice);

        // check position info
        (address originalPositionOwner, ) = positionManager.positions(tokenId);
        uint256 originalLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        uint256 lpTokensToRemove = originalLPTokens / 4;

        (
            uint256 collateralTokensToBeRemoved,
            uint256 quoteTokensToBeRemoved
        ) = pool.getLPTokenExchangeValue(lpTokensToRemove, mintPrice);

        IPositionManager.DecreaseLiquidityParams
            memory decreaseLiquidityParams = IPositionManager
                .DecreaseLiquidityParams(
                    tokenId,
                    testAddress,
                    address(pool),
                    mintPrice,
                    lpTokensToRemove
                );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(
            testAddress,
            collateralTokensToBeRemoved,
            quoteTokensToBeRemoved,
            mintPrice
        );

        vm.prank(testAddress);
        positionManager.decreaseLiquidity(decreaseLiquidityParams);

        assertEq(pool.totalQuoteToken(), mintAmount - quoteTokensToBeRemoved);

        (address updatedPositionOwner, ) = positionManager.positions(tokenId);
        uint256 updatedLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assert(updatedLPTokens < originalLPTokens);

        // TODO: check balance of collateral and quote
    }

    function testDecreaseLiquidityWithDebt() public {
        // generate new EOAs
        address testLender = generateAddress();
        uint256 testBucketPrice = 10000 * 10**18;

        uint256 mintAmount = 50000 * 1e18;
        mintAndApproveQuoteTokens(testLender, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testLender, mintAmount, testBucketPrice);

        // check position info
        uint256 originalLPTokens = positionManager.getLPTokens(
            tokenId,
            testBucketPrice
        );

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint = 5000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);

        testBorrower.addCollateral(pool, collateralToMint);

        testBorrower.borrow(pool, collateralToMint / 2, testBucketPrice);
        assertEq(pool.lup(), testBucketPrice);
        assertEq(pool.hdp(), testBucketPrice);
        assertEq(pool.totalDebt(), collateralToMint / 2);

        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50000 * 1e18);

        testBidder.purchaseBid(pool, 1 * 1e18, testBucketPrice);

        uint256 lpTokensToRemove = originalLPTokens / 4;
        (
            uint256 collateralTokensToBeRemoved,
            uint256 quoteTokensToBeRemoved
        ) = pool.getLPTokenExchangeValue(lpTokensToRemove, testBucketPrice);

        IPositionManager.DecreaseLiquidityParams
            memory decreaseLiquidityParams = IPositionManager
                .DecreaseLiquidityParams(
                    tokenId,
                    testLender,
                    address(pool),
                    testBucketPrice,
                    lpTokensToRemove
                );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(
            testLender,
            collateralTokensToBeRemoved,
            quoteTokensToBeRemoved,
            testBucketPrice
        );

        vm.prank(testLender);
        positionManager.decreaseLiquidity(decreaseLiquidityParams);

        uint256 updatedLPTokens = positionManager.getLPTokens(
            tokenId,
            testBucketPrice
        );

        assertTrue(updatedLPTokens < originalLPTokens);
    }

    // TODO: implement test case where users transfer NFTs to another user, and that user Redeems it
    function testNFTTransfer() public {
        emit log("testing transfer");
    }

    function testBurn() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, mintAmount, mintPrice);

        uint256 lpTokensToRemove = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        (
            uint256 collateralTokensToBeRemoved,
            uint256 quoteTokensToBeRemoved
        ) = pool.getLPTokenExchangeValue(lpTokensToRemove, mintPrice);

        IPositionManager.DecreaseLiquidityParams
            memory decreaseLiquidityParams = IPositionManager
                .DecreaseLiquidityParams(
                    tokenId,
                    testAddress,
                    address(pool),
                    mintPrice,
                    lpTokensToRemove
                );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(
            testAddress,
            collateralTokensToBeRemoved,
            quoteTokensToBeRemoved,
            mintPrice
        );

        vm.prank(testAddress);
        positionManager.decreaseLiquidity(decreaseLiquidityParams);

        assertEq(pool.totalQuoteToken(), mintAmount - quoteTokensToBeRemoved);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager
            .BurnParams(tokenId, testAddress, mintPrice);

        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        vm.prank(testAddress);
        positionManager.burn(burnParams);

        (address burntPositionOwner, ) = positionManager.positions(tokenId);

        assertEq(
            burntPositionOwner,
            0x0000000000000000000000000000000000000000
        );
    }

    function testGetPositionValueInQuoteTokens() public {}
}
