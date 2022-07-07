// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { CollateralToken, NFTCollateralToken, QuoteToken } from "./utils/Tokens.sol";
import { DSTestPlus }                                      from "./utils/DSTestPlus.sol";

import { UserWithCollateral, UserWithNFTCollateral, UserWithQuoteToken, UserWithQuoteTokenInNFTPool } from "./utils/Users.sol";

import { Maths } from "../libraries/Maths.sol";

import { ERC20Pool }         from "../erc20/ERC20Pool.sol";
import { ERC20PoolFactory}   from "../erc20/ERC20PoolFactory.sol";
import { ERC721Pool }        from "../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../erc721/ERC721PoolFactory.sol";

import { PositionManager } from "../base/PositionManager.sol";

import { IPositionManager } from "../base/interfaces/IPositionManager.sol";

contract PositionManagerTest is DSTestPlus {

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

        address poolAddress = _factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool = ERC20Pool(poolAddress);
    }

    /*************************/
    /*** Utility Functions ***/
    /*************************/

    function mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) private {
        _quote.mint(operator_, mintAmount_);

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

        vm.prank(recipient_);
        _positionManager.increaseLiquidity(increaseLiquidityParams);
    }

    // TODO: remove the return value and calc this exchange value separately
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

    // -------------------- Tests --------------------

    /**
     *  @notice Tests base NFT minting functionality.
     */
    function testMint() external {
        uint256 mintAmount  = 50 * 1e18;
        uint256 mintPrice   = _p1004;
        address testAddress = generateAddress();

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        // test emitted Mint event
        vm.expectEmit(true, true, true, true);
        emit Mint(testAddress, address(_pool), 1);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        require(tokenId != 0, "tokenId nonce not incremented");

        // check position info
        (, address owner, ) = _positionManager.positions(tokenId);
        uint256 lpTokens    = _positionManager.getLPTokens(tokenId, mintPrice);

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
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        // call pool contract directly to add quote tokens
        uint256 priceOne   = _p4000;
        uint256 priceTwo   = _p3010;
        uint256 priceThree = _p1004;

        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, priceOne);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, priceTwo);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, priceThree);

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // construct memorialize params struct
        uint256[] memory prices = new uint256[](3);
        prices[0] = priceOne;
        prices[1] = priceTwo;
        prices[2] = priceThree;
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testAddress, address(_pool), prices
        );

        // should revert if access hasn't been granted to transfer LP tokens
        vm.expectRevert("P:TLT:NOT_OWNER");
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // set position ownership should revert if not called by owner
        vm.expectRevert("P:ANPO:NOT_OWNER");
        _pool.approveNewPositionOwner(testAddress, address(_positionManager));

        // allow position manager to take ownership of the position
        vm.prank(testAddress);
        _pool.approveNewPositionOwner(testAddress, address(_positionManager));

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), prices, 9_000 * 1e27);
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

    /**
     *  @notice Tests attachment of multiple previously created position to already existing NFTs.
     *          LP tokens are checked to verify ownership of position.
     */
    function testMemorializeMultiple() external {
        address testLender1 = generateAddress();
        address testLender2 = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;

        mintAndApproveQuoteTokens(testLender1, mintAmount);
        mintAndApproveQuoteTokens(testLender2, mintAmount);

        // call pool contract directly to add quote tokens
        uint256 priceOne   = _p4000;
        uint256 priceTwo   = _p3010;
        uint256 priceThree = _p1004;
        uint256 priceFour  = _p1_05;

        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, priceOne);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, priceTwo);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, priceThree);

        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, priceOne);
        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, priceFour);

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = mintNFT(testLender1, address(_pool));
        uint256 tokenId2 = mintNFT(testLender2, address(_pool));

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(testLender1, priceOne),   3_000 * 1e27);
        assertEq(_pool.lpBalance(testLender1, priceTwo),   3_000 * 1e27);
        assertEq(_pool.lpBalance(testLender1, priceThree), 3_000 * 1e27);

        assertEq(_pool.lpBalance(testLender2, priceOne),  3_000 * 1e27);
        assertEq(_pool.lpBalance(testLender2, priceFour), 3_000 * 1e27);

        assertEq(_pool.lpBalance(address(_positionManager), priceOne),   0);
        assertEq(_pool.lpBalance(address(_positionManager), priceTwo),   0);
        assertEq(_pool.lpBalance(address(_positionManager), priceThree), 0);
        assertEq(_pool.lpBalance(address(_positionManager), priceFour),  0);

        assertEq(_positionManager.getLPTokens(tokenId1, priceOne),   0);
        assertEq(_positionManager.getLPTokens(tokenId1, priceTwo),   0);
        assertEq(_positionManager.getLPTokens(tokenId1, priceThree), 0);

        assertEq(_positionManager.getLPTokens(tokenId2, priceOne),   0);
        assertEq(_positionManager.getLPTokens(tokenId2, priceFour),  0);

        assertEq(_pool.totalQuoteToken(), 15_000 * 1e18);

        // construct memorialize lender 1 params struct
        uint256[] memory prices = new uint256[](3);
        prices[0] = priceOne;
        prices[1] = priceTwo;
        prices[2] = priceThree;
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId1, testLender1, address(_pool), prices
        );

        // should revert if access hasn't been granted to transfer LP tokens
        vm.expectRevert("P:TLT:NOT_OWNER");
        vm.prank(testLender1);
        _positionManager.memorializePositions(memorializeParams);

        // set position ownership should revert if not called by owner
        vm.expectRevert("P:ANPO:NOT_OWNER");
        _pool.approveNewPositionOwner(testLender1, address(_positionManager));

        // allow position manager to take ownership of lender 1's position
        vm.prank(testLender1);
        _pool.approveNewPositionOwner(testLender1, address(_positionManager));

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender1, address(_positionManager), prices, 9_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1);
        vm.prank(testLender1);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(testLender1, priceOne),   0);
        assertEq(_pool.lpBalance(testLender1, priceTwo),   0);
        assertEq(_pool.lpBalance(testLender1, priceThree), 0);

        assertEq(_pool.lpBalance(address(_positionManager), priceOne),   3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceTwo),   3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceThree), 3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceFour),  0);

        assertEq(_positionManager.getLPTokens(tokenId1, priceOne),   3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, priceTwo),   3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, priceThree), 3_000 * 1e27);

        assertEq(_pool.totalQuoteToken(), 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        vm.prank(testLender2);
        _pool.approveNewPositionOwner(testLender2, address(_positionManager));

        // memorialize lender 2 quote tokens into minted NFT
        prices = new uint256[](2);
        prices[0] = priceOne;
        prices[1] = priceFour;
        memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId2, testLender2, address(_pool), prices
        );

        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender2, address(_positionManager), prices, 6_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender2, tokenId2);
        vm.prank(testLender2);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(testLender2, priceOne),  0);
        assertEq(_pool.lpBalance(testLender2, priceFour), 0);

        assertEq(_pool.lpBalance(address(_positionManager), priceOne),   6_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceTwo),   3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceThree), 3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_positionManager), priceFour),  3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId1, priceOne),   3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, priceTwo),   3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, priceThree), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId2, priceOne),   3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, priceFour),  3_000 * 1e27);

        assertEq(_pool.totalQuoteToken(), 15_000 * 1e18);
    }

    function testMemorializeMultipleAndModifyLiquidity() external {

    }


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
        uint256 testerQuoteBalance = _quote.balanceOf(testAddress);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintPrice);

        // check initial pool balance
        uint256 postAddPoolQuote = _pool.totalQuoteToken();
        assertEq(_pool.hpb(), mintPrice);

        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - mintAmount);
        assertEq(_pool.totalQuoteToken(), mintAmount);

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // find number of lp tokens received
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintPrice); // RAY
        assertEq(originalLPTokens, 10_000 * 1e27);

        // remove 1/4 of the LP tokens
        uint256 lpTokensToRemove = originalLPTokens / 4;
        assertEq(lpTokensToRemove, 2_500 * 1e27);

        // decrease liquidity
        (, uint256 quoteTokensRemoved) = decreaseLiquidity(tokenId, testAddress, address(_pool), mintPrice, lpTokensToRemove);

        // check quote token removed
        assertEq(_pool.totalQuoteToken(), mintAmount - quoteTokensRemoved);
        assertGt(postAddPoolQuote, _pool.totalQuoteToken());
        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - _pool.totalQuoteToken());

        // check lp tokens matches expectations
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintPrice);
        assertLt(updatedLPTokens, originalLPTokens);
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     */
    function testDecreaseLiquidityWithDebt() external {
        // generate a new address and set test params
        address testLender      = generateAddress();
        uint256 mintAmount      = 50_000 * 1e18;

        mintAndApproveQuoteTokens(testLender, mintAmount);

        uint256 tokenId = mintNFT(testLender, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(_pool), mintAmount, _p10016);

        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, _p10016);
        uint256 postAddPoolQuote = _pool.totalQuoteToken();

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint        = 5000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);

        // add collateral and borrow against it
        testBorrower.addCollateral(_pool, collateralToMint);
        testBorrower.borrow(_pool, 2_500 * 1e18, _p10016);

        // check pool state
        assertEq(_pool.lup(),       _p10016);
        assertEq(_pool.hpb(),       _p10016);
        assertEq(_pool.totalDebt(), 2_500.000961538461538462 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)), collateralToMint);
        assertEq(_collateral.balanceOf(testLender),     0);
        assertEq(_quote.balanceOf(testLender),          0);
        assertEq(_quote.balanceOf(address(_pool)),      mintAmount - 2_500 * 1e18);

        // bidder purchases quote tokens with newly minted collateral
        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50_000 * 1e18);
        testBidder.purchaseBid(_pool, 1 * 1e18, _p10016);

        // lender removes a portion of their provided liquidity
        uint256 lpTokensToRemove = originalLPTokens / 4;
        (uint256 collateralTokensToBeRemoved, ) = _pool.getLPTokenExchangeValue(lpTokensToRemove, _p10016);

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testLender, address(_pool), _p10016, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit ClaimCollateral(address(_positionManager), _p10016, 0.000024958813990230 * 1e18, 0.249999995192305152765920139 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testLender, _p10016, 0.000024958813990230 * 1e18, 12_487.250490144230769231 * 1e18);
        vm.prank(testLender);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check token balances
        assertGt(postAddPoolQuote, _pool.totalQuoteToken());

        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, _p10016);
        assertTrue(updatedLPTokens < originalLPTokens);

        assertEq(_collateral.balanceOf(testLender),                collateralTokensToBeRemoved);
        assertLt(_collateral.balanceOf(testLender),                collateralToMint);
        assertEq(_collateral.balanceOf(address(_positionManager)), 0);

        assertEq(_quote.balanceOf(testLender),                12_487.250490144230769231 * 1e18);
        assertEq(_quote.balanceOf(address(_positionManager)), 0);
        assertEq(_quote.balanceOf(address(_pool)),            35_011.749509855769230769 * 1e18);

    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity in an NFT Pool.
     *          Lender reverts when attempting to interact with a pool the tokenId wasn't minted in
     */
    function testDecreaseLiquidityWithDebtNFTPool() external {
        // deploy NFT pool and user contracts
        NFTCollateralToken _erc721Collateral  = new NFTCollateralToken();
        ERC721PoolFactory _erc721Factory      = new ERC721PoolFactory();
        address _NFTCollectionPoolAddress     = _erc721Factory.deployPool(address(_erc721Collateral), address(_quote), 0.05 * 10**18);
        ERC721Pool _NFTCollectionPool         = ERC721Pool(_NFTCollectionPoolAddress);

        UserWithQuoteTokenInNFTPool testLender = new UserWithQuoteTokenInNFTPool();
        UserWithNFTCollateral testBorrower     = new UserWithNFTCollateral();
        UserWithNFTCollateral testBidder       = new UserWithNFTCollateral();

        // mint test tokens
        _quote.mint(address(testBidder), 600_000 * 1e18);
        _quote.mint(address(testLender), 600_000 * 1e18);

        _erc721Collateral.mint(address(testBorrower), 60);
        _erc721Collateral.mint(address(testBidder), 5);

        // run token approvals for NFT Collection Pool
        testLender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        testLender.approveToken(_quote, address(_positionManager), 200_000 * 1e18);
        testBidder.approveToken(_erc721Collateral, _NFTCollectionPoolAddress, 63);
        testBidder.approveToken(_erc721Collateral, _NFTCollectionPoolAddress, 65);
        testBorrower.approveToken(_erc721Collateral, _NFTCollectionPoolAddress, 1);
        testBorrower.approveToken(_erc721Collateral, _NFTCollectionPoolAddress, 3);
        testBorrower.approveToken(_erc721Collateral, _NFTCollectionPoolAddress, 5);

        // mint position NFT
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(address(testLender), _NFTCollectionPoolAddress);
        vm.prank(mintParams.recipient);
        uint256 tokenId = _positionManager.mint(mintParams);

        // should revert if adding liquidity to the wrong pool
        vm.expectRevert("PM:W_POOL");
        vm.prank(address(testLender));
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, address(testLender), address(_pool), 80_000 * 1e18, _p10016
        );
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // add liquidity that can later be decreased
        vm.prank(address(testLender));
        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(address(testLender), _p10016, 50_000 * 1e18);
        increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, address(testLender), _NFTCollectionPoolAddress, 50_000 * 1e18, _p10016
        );
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        assertEq(_quote.balanceOf(address(_positionManager)),          0);
        assertEq(_quote.balanceOf(address(_NFTCollectionPoolAddress)), 50_000 * 1e18);

        // borrower adds initial collateral to the pool to borrow against
        uint256[] memory collateralToAdd = new uint256[](3);
        collateralToAdd[0] = 1;
        collateralToAdd[1] = 3;
        collateralToAdd[2] = 5;
        vm.prank((address(testBorrower)));
        testBorrower.addCollateralMultiple(_NFTCollectionPool, collateralToAdd);

        // borrow against the pool
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(testBorrower), _p10016, 30_000 * 1e18);
        testBorrower.borrow(_NFTCollectionPool, 30_000 * 1e18, _p10016);

        // purchase bid from the pool
        uint256[] memory tokensToBuy = new uint256[](2);
        tokensToBuy[0] = 63;
        tokensToBuy[1] = 65;
        vm.expectEmit(true, true, false, true);
        emit PurchaseWithNFTs(address(testBidder), _p10016, 20_000 * 1e18, tokensToBuy);
        vm.prank((address(testBidder)));
        testBidder.purchaseBid(_NFTCollectionPool, 20_000 * 1e18, _p10016, tokensToBuy);

        // add additional quote tokens to enable claiming
        vm.prank(address(testBidder));
        _quote.approve(address(_NFTCollectionPool), type(uint256).max);
        vm.prank(address(testBidder));
        _NFTCollectionPool.addQuoteToken(50_000 * 1e18, _p10016);

        // decrease liquidity via the NFT specific method
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 63;
        tokenIdsToRemove[1] = 65;
        IPositionManager.DecreaseLiquidityNFTParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityNFTParams(
            tokenId, address(testLender), _NFTCollectionPoolAddress, _p10016, _positionManager.getLPTokens(tokenId, _p10016), tokenIdsToRemove
        );

        uint256[] memory claimedTokens = new uint256[](1);
        claimedTokens[0] = 63;
        vm.expectEmit(true, true, false, true);
        emit ClaimNFTCollateral(address(_positionManager), _p10016, claimedTokens, 10009.894230256636224099811892602 * 1e27);
        vm.expectEmit(true, true, false, true);
        emit DecreaseLiquidityNFT(address(testLender), _p10016, claimedTokens, 39_973.184583540486612233 * 1e18);
        vm.prank((address(testLender)));
        _positionManager.decreaseLiquidityNFT(decreaseLiquidityParams);

        // check pool state
        assertEq(_NFTCollectionPool.lup(), _p10016);
        assertEq(_NFTCollectionPool.hpb(), _p10016);

        // check colateral balances
        assertEq(_NFTCollectionPool.getCollateralDeposited().length,       4);
        assertEq(_NFTCollectionPool.getCollateralDeposited()[0],           1);
        assertEq(_NFTCollectionPool.getCollateralDeposited()[1],           3);
        assertEq(_NFTCollectionPool.getCollateralDeposited()[2],           5);

        assertEq(_erc721Collateral.balanceOf(address(_NFTCollectionPool)), 4);
        assertEq(_erc721Collateral.balanceOf(address(_positionManager)),   0);
        assertEq(_erc721Collateral.balanceOf(address(testLender)),         1);

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
        uint256 mintAmount = 50_000 * 1e18;
        mintAndApproveQuoteTokens(newOwner, mintAmount);

        increaseLiquidity(tokenId, newOwner, address(_pool), mintAmount, testBucketPrice);

        // check previous owner can no longer modify the NFT
        uint256 nextMintAmount = 50_000 * 1e18;
        mintAndApproveQuoteTokens(originalOwner, nextMintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, originalOwner, address(_pool), mintAmount / 4, testBucketPrice
        );

        vm.expectRevert("PM:NO_AUTH");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // check new owner can decreaseLiquidity
        uint256 lpTokensToAttempt = _positionManager.getLPTokens(tokenId, testBucketPrice);

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, newOwner, address(_pool), testBucketPrice, lpTokensToAttempt
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(newOwner, testBucketPrice, 0, 49_950 * 1e18);
        vm.prank(newOwner);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);
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

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testAddress, mintPrice, address(_pool));

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
