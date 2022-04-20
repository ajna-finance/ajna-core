// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";
import {Maths} from "../libraries/Maths.sol";

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
        pool = factory.deployPool(address(collateral), address(quote));
        positionManager = new PositionManager();
    }

    // -------------------- Utility Functions --------------------

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

    function mintAndApproveCollateralTokens(UserWithCollateral operator, uint256 mintAmount)
        private
    {
        collateral.mint(address(operator), mintAmount * 1e18);

        operator.approveToken(collateral, address(pool), mintAmount);
        operator.approveToken(collateral, address(positionManager), mintAmount);
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT(address minter, address _pool) private returns (uint256 tokenId) {
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(minter, _pool);

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
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(tokenId, recipient, _pool, _amount, _price);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient, _amount, _price);

        vm.prank(increaseLiquidityParams.recipient);
        positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    function decreaseLiquidity(
        uint256 tokenId,
        address recipient,
        address _pool,
        uint256 _price,
        uint256 _lpTokensToRemove
    ) private returns (uint256 collateralTokensToBeRemoved, uint256 quoteTokensToBeRemoved) {
        (collateralTokensToBeRemoved, quoteTokensToBeRemoved) = pool.getLPTokenExchangeValue(
            _lpTokensToRemove,
            _price
        );

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager
            .DecreaseLiquidityParams(tokenId, recipient, _pool, _price, _lpTokensToRemove);

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(
            recipient,
            collateralTokensToBeRemoved,
            quoteTokensToBeRemoved,
            _price
        );

        // decrease liquidity and check change in balances
        vm.prank(recipient);
        positionManager.decreaseLiquidity(decreaseLiquidityParams);
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(
            uint160(uint256(keccak256(abi.encodePacked(nonce, blockhash(block.number)))))
        );
        nonce++;
    }

    // -------------------- Tests --------------------

    // @notice: Tests base NFT minting functionality
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
        (, address owner, ) = positionManager.positions(tokenId);
        uint256 lpTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, alice);
        assert(lpTokens == 0);
    }

    // @notice: Tests attachment of a created position to an already existing NFT
    // @notice: LP tokens are checked to verify ownership of position
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
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager
            .MemorializePositionsParams(tokenId, testAddress, address(pool), prices);

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);

        vm.prank(testAddress);
        positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLPTokens = positionManager.getLPTokens(tokenId, priceOne);

        assert(positionAtPriceOneLPTokens > 0);

        // check lp tokens at non added to price
        uint256 positionAtWrongPriceLPTokens = positionManager.getLPTokens(tokenId, 4000000 * 1e18);

        assert(positionAtWrongPriceLPTokens == 0);
    }

    // TODO: implement test case where multiple users mints multiple NFTs to multiple pools
    function testMintMultiple() public {}

    // @notice: Tests a contract minting an NFT
    function testMintToContract() public {
        UserWithQuoteToken lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);

        // check that contract can successfully receive the NFT
        vm.expectEmit(true, true, true, true);
        emit Mint(address(lender), address(pool), 1);

        mintNFT(address(lender), address(pool));
    }

    // @notice: Tests minting an NFT, increasing liquidity at two different prices
    function testIncreaseLiquidity() public {
        // generate a new address
        address testAddress = generateAddress();

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;
        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // check newly minted position with no liquidity added
        (, address originalPositionOwner, ) = positionManager.positions(tokenId);
        uint256 originalLPTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens == 0);

        // add initial liquidity
        increaseLiquidity(tokenId, testAddress, address(pool), mintAmount / 4, mintPrice);

        // check liquidity was added successfully
        (, address updatedPositionOwner, ) = positionManager.positions(tokenId);
        uint256 updatedLPTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(pool.totalQuoteToken(), Maths.wadToRad(mintAmount) / 4);
        assertEq(updatedPositionOwner, testAddress);
        assert(updatedLPTokens != 0);

        // Add liquidity to the same price again
        increaseLiquidity(tokenId, testAddress, address(pool), mintAmount / 4, mintPrice);

        uint256 positionUpdatedTwiceTokens = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(pool.totalQuoteToken(), Maths.wadToRad(mintAmount) / 2);
        assert(positionUpdatedTwiceTokens > updatedLPTokens);

        // add liquidity to a different price, for same owner and tokenId
        uint256 newPrice = 50_159.593888626183666006 * 1e18;
        increaseLiquidity(tokenId, testAddress, address(pool), mintAmount / 2, newPrice);

        assertEq(pool.totalQuoteToken(), Maths.wadToRad(mintAmount));
    }

    // @notice: Tests minting an NFT and failing to increase
    // @notice: liquidity for invalid recipient
    // @notice: recipient reverts:
    // @notice:     attempts to increase liquidity when not permited
    function testIncreaseLiquidityPermissions() public {
        address recipient = generateAddress();
        address externalCaller = generateAddress();

        uint256 tokenId = mintNFT(recipient, address(pool));

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1000 * 10**18;
        mintAndApproveQuoteTokens(recipient, mintAmount, approveBig);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(tokenId, recipient, address(pool), mintAmount / 4, mintPrice);

        // should revert if called by a non-recipient address
        vm.prank(externalCaller);
        vm.expectRevert("ajna/not-approved");

        positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    // @notice: Tests minting an NFT, increasing liquidity and decreasing liquidity
    function testDecreaseLiquidityNoDebt() public {
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;

        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(pool), mintAmount, mintPrice);

        // find number of lp tokens received
        uint256 originalLPTokens = positionManager.getLPTokens(tokenId, mintPrice); // RAY
        assertEq(originalLPTokens, 10_000 * 1e27);

        // remove 1/4 of the LP tokens
        uint256 lpTokensToRemove = Maths.rayToWad(originalLPTokens / 4); // WAD
        assertEq(lpTokensToRemove, 2_500 * 1e18);

        // decrease liquidity
        (, uint256 quoteTokensRemoved) = decreaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintPrice,
            lpTokensToRemove
        );

        // check quote token removed
        assertEq(pool.totalQuoteToken(), Maths.wadToRad(mintAmount) - quoteTokensRemoved);

        // check lp tokens matches expectations
        (, address updatedPositionOwner, ) = positionManager.positions(tokenId);
        uint256 updatedLPTokens = positionManager.getLPTokens(tokenId, mintPrice);
        assert(updatedLPTokens < originalLPTokens);

        // TODO: check balance of collateral and quote
    }

    // @notice: Tests minting an NFT, increasing liquidity, borrowing,
    // @notice: purchasing then decreasing liquidity
    function testDecreaseLiquidityWithDebt() public {
        // generate a new address and set test params
        address testLender = generateAddress();
        uint256 testBucketPrice = 10_016.501589292607751220 * 10**18;
        uint256 mintAmount = 50000 * 1e18;

        mintAndApproveQuoteTokens(testLender, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testLender, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(pool), mintAmount, testBucketPrice);

        // check position info
        uint256 originalLPTokens = positionManager.getLPTokens(tokenId, testBucketPrice);

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint = 5000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);

        testBorrower.addCollateral(pool, collateralToMint);

        testBorrower.borrow(pool, 2_500 * 1e18, testBucketPrice);
        assertEq(pool.lup(), testBucketPrice);
        assertEq(pool.hdp(), testBucketPrice);
        assertEq(pool.totalDebt(), 2_500 * 1e45);

        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50000 * 1e18);

        testBidder.purchaseBid(pool, 1 * 1e18, testBucketPrice);

        // identify number of lp tokens to exchange for quote and collateral accrued
        uint256 lpTokensToRemove = originalLPTokens / 4;
        decreaseLiquidity(tokenId, testLender, address(pool), testBucketPrice, lpTokensToRemove);

        // TODO: check quote and collateral vs expectations
        // assertEq(pool.totalQuoteToken(), mintAmount - quoteTokensRemoved);

        uint256 updatedLPTokens = positionManager.getLPTokens(tokenId, testBucketPrice);

        assertTrue(updatedLPTokens < originalLPTokens);
    }

    // @notice: Tests minting an NFT, transfering NFT, increasing liquidity
    // @notice: checks that old owner cannot increase liquidity
    // @notice: old owner reverts:
    // @notice:    attempts to increase liquidity without permission
    function testNFTTransfer() public {
        // generate addresses and set test params
        address testMinter = generateAddress();
        address testReceiver = generateAddress();
        uint256 testBucketPrice = 10_016.501589292607751220 * 10**18;

        uint256 tokenId = mintNFT(testMinter, address(pool));

        // check owner
        (, address originalOwner, ) = positionManager.positions(tokenId);
        assertEq(originalOwner, testMinter);

        // approve and transfer NFT to different address
        vm.prank(testMinter);
        positionManager.approve(address(this), tokenId);
        positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check owner
        (, address newOwner, ) = positionManager.positions(tokenId);
        assertEq(newOwner, testReceiver);
        assert(newOwner != originalOwner);

        // check new owner can increaseLiquidity
        uint256 mintAmount = 50000 * 1e18;
        mintAndApproveQuoteTokens(newOwner, mintAmount, approveBig);

        increaseLiquidity(tokenId, newOwner, address(pool), mintAmount, testBucketPrice);

        // check previous owner can no longer modify the NFT
        uint256 nextMintAmount = 50000 * 1e18;
        mintAndApproveQuoteTokens(originalOwner, nextMintAmount, approveBig);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(
                tokenId,
                originalOwner,
                address(pool),
                mintAmount / 4,
                testBucketPrice
            );

        vm.expectRevert("ajna/not-approved");
        positionManager.increaseLiquidity(increaseLiquidityParams);

        // check new owner can decreaseLiquidity
        uint256 lpTokensToAttempt = positionManager.getLPTokens(tokenId, testBucketPrice);

        decreaseLiquidity(tokenId, newOwner, address(pool), testBucketPrice, lpTokensToAttempt);
    }

    // @notice: Tests NFT position can & can't be burned
    // @notice: based on liquidity attached to it
    // @notice: owner reverts:
    // @notice:    attempts to burn NFT with liquidity
    function testBurn() public {
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 1_004.989662429170775094 * 10**18;

        mintAndApproveQuoteTokens(testAddress, mintAmount, approveBig);

        uint256 tokenId = mintNFT(testAddress, address(pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(pool), mintAmount, mintPrice);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(
            tokenId,
            testAddress,
            mintPrice
        );

        // should revert if liquidity not removed
        vm.expectRevert("ajna/liquidity-not-removed");
        vm.prank(testAddress);
        positionManager.burn(burnParams);

        // remove all lp tokens
        uint256 lpTokensToRemove = positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(lpTokensToRemove, 10_000 * 10**27);

        // decrease liquidity
        (, uint256 quoteTokensRemoved) = decreaseLiquidity(
            tokenId,
            testAddress,
            address(pool),
            mintPrice,
            lpTokensToRemove
        );
        assertEq(pool.totalQuoteToken(), Maths.wadToRad(mintAmount) - quoteTokensRemoved);

        // should emit Burn
        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        // burn and check state changes
        vm.prank(testAddress);
        positionManager.burn(burnParams);

        (, address burntPositionOwner, ) = positionManager.positions(tokenId);

        assertEq(burntPositionOwner, 0x0000000000000000000000000000000000000000);
    }

    function testGetPositionValueInQuoteTokens() public {}
}
