// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

// TODO: add multiple pools to tests
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
    function mintNFT(address minter, address _pool)
        private
        returns (uint256 tokenId)
    {
        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(minter, _pool);

        vm.prank(mintParams.recipient);
        return positionManager.mint(mintParams);
    }

    function increaseLiquidity(
        uint256 tokenId,
        address recipient,
        address _pool,
        uint256 _amount,
        uint256 _price
    ) private {
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParams = IPositionManager
                .IncreaseLiquidityParams(
                    tokenId,
                    recipient,
                    _pool,
                    _amount,
                    _price
                );

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient, _amount, _price);

        vm.prank(increaseLiquidityParams.recipient);
        positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(nonce, blockhash(block.number)))
                )
            )
        );
        nonce++;
    }

    function testMint() public {
        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;

        mintAndApproveQuoteTokens(alice, mintAmount, approveBig);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(alice, address(pool), 1);

        uint256 tokenId = mintNFT(alice, address(pool));

        require(tokenId != 0, "tokenId nonce not incremented");

        // check position info
        (address owner, ) = positionManager.positions(tokenId);
        uint256 lpTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, alice);
        assert(lpTokens == 0);
    }

    function testMintPermissions() public {
        address recipient = generateAddress();
        address externalCaller = generateAddress();

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(recipient, address(pool));

        // should revert if called by a non-recipient address
        vm.prank(externalCaller);
        vm.expectRevert("Ajna/wrong-caller");
        positionManager.mint(mintParams);
    }

    function testMemorializePositions() public {
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;

        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        // call pool contract directly to add quote tokens
        uint256 priceOne = 4_000.927678580567537368 * 1e18;
        uint256 priceTwo = 3_010.892022197881557845 * 1e18;
        uint256 priceThree = 1_004.989662429170775094 * 1e18;

        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceOne);
        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceTwo);
        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceThree);

        uint256[] memory prices = new uint256[](3);

        prices[0] = priceOne;
        prices[1] = priceTwo;
        prices[2] = priceThree;

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = mintNFT(testAddress, address(pool));

        // memorialize quote tokens into minted NFT
        IPositionManager.MemorializePositionsParams
            memory memorializeParams = IPositionManager
                .MemorializePositionsParams(
                    tokenId,
                    testAddress,
                    address(pool),
                    prices
                );

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);

        vm.prank(testAddress);
        positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLPTokens = positionManager.getLPTokens(
            tokenId,
            priceOne
        );

        assert(positionAtPriceOneLPTokens > 0);

        // check lp tokens at non added to price
        uint256 positionAtWrongPriceLPTokens = positionManager.getLPTokens(
            tokenId,
            4000000 * 1e18
        );

        assert(positionAtWrongPriceLPTokens == 0);
    }

    // TODO: implement test case where multiple users mints multiple NFTs
    function testMintMultiple() public {}

    // TODO: implement test case where caller is not an EOA
    function testMintToContract() public {}

    function testIncreaseLiquidity() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // check newly minted position with no liquidity added
        (address originalPositionOwner, ) = positionManager.positions(tokenId);
        uint256 originalLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens == 0);

        // add initial liquidity
        increaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintAmount / 4,
            mintPrice
        );

        // check liquidity was added successfully
        (address updatedPositionOwner, ) = positionManager.positions(tokenId);
        uint256 updatedLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assertEq(pool.totalQuoteToken(), mintAmount / 4);
        assertEq(updatedPositionOwner, testAddress);
        assert(updatedLPTokens != 0);

        // Add liquidity to the same price again
        increaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintAmount / 4,
            mintPrice
        );

        uint256 positionUpdatedTwiceTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assertEq(pool.totalQuoteToken(), mintAmount / 2);
        assert(positionUpdatedTwiceTokens > updatedLPTokens);

        // add liquidity to a different price, for same owner and tokenId
        uint256 newPrice = 50_159.593888626183666006 * 1e18;
        increaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintAmount / 2,
            newPrice
        );

        assertEq(pool.totalQuoteToken(), mintAmount);
    }

    function testDecreaseLiquidityNoDebt() public {
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;

        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintAmount,
            mintPrice
        );

        // find number of lp tokens received
        uint256 originalLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        // burn 1/4 of the LP tokens
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

        // decrease liquidity and check change in balances
        vm.prank(testAddress);
        positionManager.decreaseLiquidity(decreaseLiquidityParams);

        assertEq(pool.totalQuoteToken(), mintAmount - quoteTokensToBeRemoved);

        uint256 updatedLPTokens = positionManager.getLPTokens(
            tokenId,
            mintPrice
        );

        assert(updatedLPTokens < originalLPTokens);

        // TODO: check balance of collateral and quote
    }

    function testDecreaseLiquidityWithDebt() public {
        // generate a new address and set test params
        address testLender = generateAddress();
        uint256 testBucketPrice = 10_016.501589292607751220 * 10**18;
        uint256 mintAmount = 50000 * 1e18;

        mintAndApproveQuoteTokens(testLender, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testLender, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(
            tokenId,
            testLender,
            address(pool),
            mintAmount,
            testBucketPrice
        );

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

        // identify number of lp tokens to exchange for quote and collateral accrued
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

        // decrease liquidity and check change in balances
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
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;

        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintAmount,
            mintPrice
        );

        // decrease liquidity
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

        // should emit Burn
        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        // burn and check state changes
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
