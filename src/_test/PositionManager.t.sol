// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

// https://w.mirror.xyz/mOUlpgkWA178HNUW7xR20TdbGRV6dMid7uChqxf9Z58

contract PositionManagerTest is DSTestPlus {
    PositionManager internal positionManager;
    ERC20Pool internal pool;
    ERC20PoolFactory internal factory;

    CollateralToken internal collateral;
    QuoteToken internal quote;

    // UserWithQuoteToken internal alice;
    address alice;
    UserWithQuoteToken internal bob;

    // uint256 constant maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 constant approveBig = 50000000000 * 1e18;

    // nonce for generating random addresses
    uint16 nonce = 0;

    function setUp() public {
        // alice = new UserWithQuoteToken();
        alice = 0x02B9219F667d91fBe64F8f77F691dE3D1000F223;
        bob = new UserWithQuoteToken();

        collateral = new CollateralToken();
        quote = new QuoteToken();

        // TODO: move logic to internal methods
        quote.mint(alice, 30000000000 * 1e18);
        quote.mint(address(bob), 10000000 * 1e18);

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
        address operator,
        uint256 mintAmount,
        uint256 approvalAmount
    ) private {
        collateral.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        collateral.approve(address(pool), approvalAmount);
        vm.prank(operator);
        collateral.approve(address(positionManager), approvalAmount);
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT(IPositionManager.MintParams memory mintParams)
        private
        returns (uint256 tokenId)
    {
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
        // execute calls from alice address
        vm.prank(alice);
        quote.approve(address(pool), approveBig);
        vm.prank(alice);
        quote.approve(address(positionManager), approveBig);

        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice = 1000 * 10**18;

        // have alice execute mint to enable delegatecall
        vm.prank(alice);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(alice, address(pool), mintAmount, mintPrice);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(alice, mintAmount, mintPrice);

        // check tokenId has been incremented
        uint256 tokenId = positionManager.mint(mintParams);
        require(tokenId != 0, "tokenId nonce not incremented");

        // TODO: switch to calling struct directly
        // check position info
        PositionManager.Position memory position = positionManager.getPosition(
            tokenId
        );
        assertEq(position.owner, alice);
        assert(position.lpTokens != 0);
    }

    function testIncreaseLiquidity() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        vm.prank(testAddress);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(testAddress, address(pool), mintAmount, mintPrice);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testAddress, mintAmount, mintPrice);

        uint256 tokenId = positionManager.mint(mintParams);

        PositionManager.Position memory originalPosition = positionManager
            .getPosition(tokenId);

        uint256 amountToAdd = 50000;

        vm.prank(testAddress);
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

        positionManager.increaseLiquidity(increaseLiquidityParams);

        PositionManager.Position memory updatedPosition = positionManager
            .getPosition(tokenId);
        assert(updatedPosition.lpTokens > originalPosition.lpTokens);
    }

    function testDecreaseLiquidityNoDebt() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        vm.prank(testAddress);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(testAddress, address(pool), mintAmount, mintPrice);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testAddress, mintAmount, mintPrice);

        uint256 tokenId = positionManager.mint(mintParams);

        PositionManager.Position memory originalPosition = positionManager
            .getPosition(tokenId);

        uint256 lpTokensToRemove = originalPosition.lpTokens / 4;

        (
            uint256 collateralTokensToBeRemoved,
            uint256 quoteTokensToBeRemoved
        ) = pool.getLPTokenExchangeValue(lpTokensToRemove, mintPrice);

        vm.prank(testAddress);
        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(
            testAddress,
            collateralTokensToBeRemoved,
            quoteTokensToBeRemoved,
            mintPrice
        );

        // TODO: finish implementing
        IPositionManager.DecreaseLiquidityParams
            memory decreaseLiquidityParams = IPositionManager
                .DecreaseLiquidityParams(
                    tokenId,
                    testAddress,
                    address(pool),
                    mintPrice,
                    lpTokensToRemove
                );

        positionManager.decreaseLiquidity(decreaseLiquidityParams);
    }

    function testDecreaseLiquidityWithDebt() public {
        // generate new EOAs
        address testLender = generateAddress();
        address testBorrower = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(testLender, mintAmount, approveBig);

        vm.prank(testLender);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(testLender, address(pool), mintAmount, mintPrice);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testLender, mintAmount, mintPrice);

        uint256 tokenId = positionManager.mint(mintParams);

        PositionManager.Position memory originalPosition = positionManager
            .getPosition(tokenId);

        uint256 lpTokensToRemove = originalPosition.lpTokens / 4;

        // check balance of collateral and quote
    }

    function testGetLPTokenExchangeValue() public {
        // pool.getLPTokenExchangeValue()
    }

    function testNFTTransfer() public {
        emit log("testing transfer");
    }

    function testBurn() public {}
}
