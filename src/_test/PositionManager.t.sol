// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

import { Maths } from "../libraries/Maths.sol";

import { ERC20Pool }       from "../ERC20Pool.sol";
import { ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import { PositionManager } from "../PositionManager.sol";

import { IPositionManager } from "../interfaces/IPositionManager.sol";

contract PositionManagerTest is DSTestPlus {

    // UserWithQuoteToken internal alice;
    address internal _alice = 0x02B9219F667d91fBe64F8f77F691dE3D1000F223;

    // nonce for generating random addresses
    uint16 internal _nonce;

    CollateralToken  internal _collateral;
    ERC20Pool        internal _pool;
    ERC20PoolFactory internal _factory;
    PositionManager  internal _positionManager;
    QuoteToken       internal _quote;

    function setUp() public {
        _collateral      = new CollateralToken();
        _quote           = new QuoteToken();
        _factory         = new ERC20PoolFactory();
        _positionManager = new PositionManager();

        address poolAddress = _factory.deployPool(address(_collateral), address(_quote));
        _pool = ERC20Pool(poolAddress);

        // TODO: move logic to internal methods
        _quote.mint(_alice, 30000000000 * 1e18);
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) private {
        _quote.mint(operator_, mintAmount_ * 1e18);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_positionManager), type(uint256).max);

    }

    function mintAndApproveCollateralTokens(UserWithCollateral operator_, uint256 mintAmount_)private{
        _collateral.mint(address(operator_), mintAmount_ * 1e18);

        operator_.approveToken(_collateral, address(_pool),            mintAmount_);
        operator_.approveToken(_collateral, address(_positionManager), mintAmount_);
    }

    /**
     *  @dev Abstract away NFT Minting logic for use by multiple tests.
     */
    function mintNFT(address minter_, address pool_) private returns (uint256 tokenId) {
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(minter_, pool_);

        vm.prank(mintParams.recipient);
        return _positionManager.mint(mintParams);
    }

    function increaseLiquidity(
        uint256 tokenId_, address recipient_, address pool_, uint256 amount_, uint256 price_
    ) private {
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId_, recipient_, pool_, amount_, price_
        );

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient_, price_, amount_);

        vm.prank(increaseLiquidityParams.recipient);
        _positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    function decreaseLiquidity(
        uint256 tokenId_, address recipient_, address pool_, uint256 price_, uint256 lpTokensToRemove_
    ) private returns (uint256 collateralTokensToBeRemoved, uint256 quoteTokensToBeRemoved) {
        (collateralTokensToBeRemoved, quoteTokensToBeRemoved) = _pool.getLPTokenExchangeValue(lpTokensToRemove_, price_);

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId_, recipient_, pool_, price_, lpTokensToRemove_
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(recipient_, price_, collateralTokensToBeRemoved, quoteTokensToBeRemoved);

        // decrease liquidity and check change in balances
        vm.prank(recipient_);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(uint160(uint256(keccak256(abi.encodePacked(_nonce, blockhash(block.number))))));
        _nonce++;
    }

    // -------------------- Tests --------------------

    /**
     *  @notice Tests base NFT minting functionality.
     */
    function testMint() external {
        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice  = _p1004;

        mintAndApproveQuoteTokens(_alice, mintAmount);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(_alice, address(_pool), 1);

        uint256 tokenId = mintNFT(_alice, address(_pool));

        require(tokenId != 0, "tokenId nonce not incremented");

        // check position info
        (, address owner, ) = _positionManager.positions(tokenId);
        uint256 lpTokens    = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(owner, _alice);
        assert(lpTokens == 0);
    }

    /**
     *  @notice Tests attachment of a created position to an already existing NFT.
     *          LP tokens are checked to verify ownership of position.
     */
    function testMemorializePositions() external {
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256 priceOne   = _p4000;
        uint256 priceTwo   = _p3010;
        uint256 priceThree = _p1004;

        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceOne);
        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceTwo);
        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceThree);

        uint256[] memory prices = new uint256[](3);

        prices[0] = priceOne;
        prices[1] = priceTwo;
        prices[2] = priceThree;

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // memorialize quote tokens into minted NFT
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testAddress, address(_pool), prices
        );

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);

        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLPTokens = _positionManager.getLPTokens(tokenId, priceOne);

        assert(positionAtPriceOneLPTokens > 0);

        // check lp tokens at non added to price
        uint256 positionAtWrongPriceLPTokens = _positionManager.getLPTokens(tokenId, 4000000 * 1e18);

        assert(positionAtWrongPriceLPTokens == 0);
    }

    // TODO: implement test case where multiple users mints multiple NFTs to multiple pools
    function testMintMultiple() external {}

    /**
     *  @notice Tests a contract minting an NFT.
     */
    function testMintToContract() external {
        UserWithQuoteToken lender = new UserWithQuoteToken();
        _quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(_quote, address(_pool), 200_000 * 1e18);

        // check that contract can successfully receive the NFT
        vm.expectEmit(true, true, true, true);
        emit Mint(address(lender), address(_pool), 1);

        mintNFT(address(lender), address(_pool));
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity at two different prices.
     */
    function testIncreaseLiquidity() external {
        // generate a new address
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;
        uint256 mintPrice   = _p1004;
        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // check newly minted position with no liquidity added
        (, address originalPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens == 0);

        // add initial liquidity
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintPrice);

        // check liquidity was added successfully
        (, address updatedPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(_pool.totalQuoteToken(), mintAmount / 4);
        assertEq(updatedPositionOwner,   testAddress);
        assert(updatedLPTokens != 0);

        // Add liquidity to the same price again
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintPrice);

        uint256 positionUpdatedTwiceTokens = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(_pool.totalQuoteToken(), mintAmount / 2);
        assert(positionUpdatedTwiceTokens > updatedLPTokens);

        // add liquidity to a different price, for same owner and tokenId
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 2, _p50159);

        assertEq(_pool.totalQuoteToken(), mintAmount);
    }

    /**
     *  @notice Tests minting an NFT and failing to increase liquidity for invalid recipient.
     *          Recipient reverts: attempts to increase liquidity when not permited.
     */
    function testIncreaseLiquidityPermissions() external {
        address recipient      = generateAddress();
        address externalCaller = generateAddress();
        uint256 tokenId        = mintNFT(recipient, address(_pool));
        uint256 mintAmount     = 10000 * 1e18;
        uint256 mintPrice      = 1000 * 10**18;

        mintAndApproveQuoteTokens(recipient, mintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, recipient, address(_pool), mintAmount / 4, mintPrice
        );

        // should revert if called by a non-recipient address
        vm.prank(externalCaller);
        vm.expectRevert("PM:NO_AUTH");

        _positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity and decreasing liquidity.
     */
    function testDecreaseLiquidityNoDebt() external {
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount  = 10_000 * 1e18;
        uint256 mintPrice   = _p1004;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintPrice);

        // find number of lp tokens received
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintPrice); // RAY
        assertEq(originalLPTokens, 10_000 * 1e27);

        // remove 1/4 of the LP tokens
        uint256 lpTokensToRemove = Maths.rayToWad(originalLPTokens / 4); // WAD
        assertEq(lpTokensToRemove, 2_500 * 1e18);

        // decrease liquidity
        (, uint256 quoteTokensRemoved) = decreaseLiquidity(tokenId, testAddress, address(_pool), mintPrice, lpTokensToRemove);

        // check quote token removed
        assertEq(_pool.totalQuoteToken(), mintAmount - quoteTokensRemoved);

        // check lp tokens matches expectations
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintPrice);
        assert(updatedLPTokens < originalLPTokens);

        // TODO: check balance of collateral and quote
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     */
    function testDecreaseLiquidityWithDebt() external {
        // generate a new address and set test params
        address testLender      = generateAddress();
        uint256 testBucketPrice = _p10016;
        uint256 mintAmount      = 50000 * 1e18;

        mintAndApproveQuoteTokens(testLender, mintAmount);

        uint256 tokenId = mintNFT(testLender, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(_pool), mintAmount, testBucketPrice);

        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, testBucketPrice);

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint        = 5000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);

        testBorrower.addCollateral(_pool, collateralToMint);

        testBorrower.borrow(_pool, 2_500 * 1e18, testBucketPrice);
        assertEq(_pool.lup(),       testBucketPrice);
        assertEq(_pool.hpb(),       testBucketPrice);
        assertEq(_pool.totalDebt(), 2_500.000961538461538462 * 1e18);

        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50000 * 1e18);

        testBidder.purchaseBid(_pool, 1 * 1e18, testBucketPrice);

        // identify number of lp tokens to exchange for quote and collateral accrued
        uint256 lpTokensToRemove = originalLPTokens / 4;
        decreaseLiquidity(tokenId, testLender, address(_pool), testBucketPrice, lpTokensToRemove);

        // TODO: check quote and collateral vs expectations
        // assertEq(pool.totalQuoteToken(), mintAmount - quoteTokensRemoved);

        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, testBucketPrice);

        assertTrue(updatedLPTokens < originalLPTokens);
    }

    /**
     *  @notice Tests minting an NFT, transfering NFT, increasing liquidity.
     *          Checks that old owner cannot increase liquidity.
     *          Old owner reverts: attempts to increase liquidity without permission.
     */
    function testNFTTransfer() external {
        // generate addresses and set test params
        address testMinter      = generateAddress();
        address testReceiver    = generateAddress();
        uint256 testBucketPrice = _p10016;
        uint256 tokenId         = mintNFT(testMinter, address(_pool));

        // check owner
        (, address originalOwner, ) = _positionManager.positions(tokenId);
        assertEq(originalOwner, testMinter);

        // approve and transfer NFT to different address
        vm.prank(testMinter);
        _positionManager.approve(address(this), tokenId);
        _positionManager.safeTransferFrom(testMinter, testReceiver, tokenId);

        // check owner
        (, address newOwner, ) = _positionManager.positions(tokenId);
        assertEq(newOwner, testReceiver);
        assert(newOwner != originalOwner);

        // check new owner can increaseLiquidity
        uint256 mintAmount = 50000 * 1e18;
        mintAndApproveQuoteTokens(newOwner, mintAmount);

        increaseLiquidity(tokenId, newOwner, address(_pool), mintAmount, testBucketPrice);

        // check previous owner can no longer modify the NFT
        uint256 nextMintAmount = 50000 * 1e18;
        mintAndApproveQuoteTokens(originalOwner, nextMintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, originalOwner, address(_pool), mintAmount / 4, testBucketPrice
        );

        vm.expectRevert("PM:NO_AUTH");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // check new owner can decreaseLiquidity
        uint256 lpTokensToAttempt = _positionManager.getLPTokens(tokenId, testBucketPrice);

        decreaseLiquidity(tokenId, newOwner, address(_pool), testBucketPrice, lpTokensToAttempt);
    }

    /**
     *  @notice Tests NFT position can & can't be burned based on liquidity attached to it.
     *          Checks that old owner cannot increase liquidity.
     *          Owner reverts: attempts to burn NFT with liquidity.
     */
    function testBurn() external {
        // generate a new address and set test params
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;
        uint256 mintPrice   = _p1004;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintPrice);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testAddress, mintPrice);

        // should revert if liquidity not removed
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        // remove all lp tokens
        uint256 lpTokensToRemove = _positionManager.getLPTokens(tokenId, mintPrice);

        assertEq(lpTokensToRemove, 10_000 * 10**27);

        // decrease liquidity
        (, uint256 quoteTokensRemoved) = decreaseLiquidity(tokenId, testAddress, address(_pool), mintPrice, lpTokensToRemove);
        assertEq(_pool.totalQuoteToken(), mintAmount - quoteTokensRemoved);

        // should emit Burn
        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        // burn and check state changes
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        (, address burntPositionOwner, ) = _positionManager.positions(tokenId);

        assertEq(burntPositionOwner, 0x0000000000000000000000000000000000000000);
    }

    function testGetPositionValueInQuoteTokens() external {}

}
