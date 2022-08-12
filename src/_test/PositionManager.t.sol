// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { CollateralToken, NFTCollateralToken, QuoteToken } from "./utils/Tokens.sol";
import { DSTestPlus }                                      from "./utils/DSTestPlus.sol";

import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

import { Maths } from "../libraries/Maths.sol";

import { ERC20Pool }       from "../erc20/ERC20Pool.sol";
import { ERC20PoolFactory} from "../erc20/ERC20PoolFactory.sol";

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
        _pool            = ERC20Pool(_factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
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
        _collateral.mint(address(operator_), mintAmount_);

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
        uint256 tokenId_, address recipient_, address pool_, uint256 amount_, uint256 index_, uint256 price_
    ) private {
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId_, recipient_, pool_, amount_, index_
        );

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient_, price_, amount_);

        vm.prank(recipient_);
        _positionManager.increaseLiquidity(increaseLiquidityParams);
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
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        uint256[] memory prices = new uint256[](3);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;

        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[1]);
        vm.prank(testAddress);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        // mint an NFT to later memorialize existing positions into
        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // construct memorialize params struct
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testAddress, indexes
        );

        // should revert if access hasn't been granted to transfer LP tokens
        vm.expectRevert("S:TLT:NOT_OWNER");
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // allow position manager to take ownership of the position
        vm.prank(testAddress);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testAddress, address(_positionManager), prices, 9_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);
        vm.prank(testAddress);
        _positionManager.memorializePositions(memorializeParams);

        // check memorialization success
        uint256 positionAtPriceOneLPTokens = _positionManager.getLPTokens(tokenId, indexes[0]);

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
        uint256[] memory indexes = new uint256[](4);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;
        indexes[3] = 2553;

        uint256[] memory prices = new uint256[](4);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;
        prices[3] = _p2966;

        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[1]);
        vm.prank(testLender1);
        _pool.addQuoteToken(3_000 * 1e18, indexes[2]);

        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, indexes[0]);
        vm.prank(testLender2);
        _pool.addQuoteToken(3_000 * 1e18, indexes[3]);

        // mint NFTs to later memorialize existing positions into
        uint256 tokenId1 = mintNFT(testLender1, address(_pool));
        uint256 tokenId2 = mintNFT(testLender2, address(_pool));

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(indexes[0], testLender1), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], testLender1), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], testLender1), 3_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], testLender2), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[3], testLender2), 3_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 0);
        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 0);
        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 0);
        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[1], tokenId1), 0);
        assertEq(_positionManager.getLPTokens(indexes[2], tokenId1), 0);

        assertEq(_positionManager.getLPTokens(indexes[0], tokenId2), 0);
        assertEq(_positionManager.getLPTokens(indexes[3], tokenId2), 0);

        assertEq(_pool.treeSum(), 15_000 * 1e18);

        // construct memorialize lender 1 params struct
        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId1, testLender1, indexes
        );

        // allow position manager to take ownership of lender 1's position
        vm.prank(testLender1);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize lender 1 quote tokens into minted NFT
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender1, address(_positionManager), prices, 9_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender1, tokenId1);
        vm.prank(testLender1);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(indexes[0], testLender1), 0);
        assertEq(_pool.lpBalance(indexes[1], testLender1), 0);
        assertEq(_pool.lpBalance(indexes[2], testLender1), 0);

        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_positionManager)), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_positionManager)), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[3], address(_positionManager)), 0);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_pool.treeSum(), 15_000 * 1e18);

        // allow position manager to take ownership of lender 2's position
        vm.prank(testLender2);
        _pool.approveNewPositionOwner(address(_positionManager));

        // memorialize lender 2 quote tokens into minted NFT
        uint256[] memory newIndexes = new uint256[](2);
        newIndexes[0] = 2550;
        newIndexes[1] = 2553;

        prices = new uint256[](2);
        prices[0] = _p3010;
        prices[1] = _p2966;
        memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId2, testLender2, newIndexes
        );

        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(testLender2, address(_positionManager), prices, 6_000 * 1e27);
        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testLender2, tokenId2);
        vm.prank(testLender2);
        _positionManager.memorializePositions(memorializeParams);

        // check lender, position manager,  and pool state
        assertEq(_pool.lpBalance(indexes[0], testLender2), 0);
        assertEq(_pool.lpBalance(indexes[3], testLender2), 0);

        assertEq(_pool.lpBalance(indexes[0], address(_positionManager)), 6_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_positionManager)), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_positionManager)), 3_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[3], address(_positionManager)), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId1, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[1]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId1, indexes[2]), 3_000 * 1e27);

        assertEq(_positionManager.getLPTokens(tokenId2, indexes[0]), 3_000 * 1e27);
        assertEq(_positionManager.getLPTokens(tokenId2, indexes[3]), 3_000 * 1e27);

        assertEq(_pool.treeSum(), 15_000 * 1e18);
    }

    function testMemorializeMultipleAndModifyLiquidity() external {
        // TODO implement
    }

    /**
     *  @notice Tests a contract minting an NFT.
     */
    function testMintToContract() external {
        // TODO to be reviewed
        address lender = generateAddress();
        _quote.mint(address(lender), 200_000 * 1e18);

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
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;
        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // check newly minted position with no liquidity added
        (, address originalPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(originalPositionOwner, testAddress);
        assert(originalLPTokens == 0);

        // add no liquidity
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, testAddress, address(_pool), 0, mintIndex
        );

        vm.prank(testAddress);
        vm.expectRevert("PM:IL:NO_LP_TOKENS");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // add initial liquidity
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintIndex, mintPrice);

        // check liquidity was added successfully
        (, address updatedPositionOwner, ) = _positionManager.positions(tokenId);
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(_pool.treeSum(), mintAmount / 4);
        assertEq(updatedPositionOwner, testAddress);
        assert(updatedLPTokens != 0);

        // Add liquidity to the same price again
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintIndex, mintPrice);

        uint256 positionUpdatedTwiceTokens = _positionManager.getLPTokens(tokenId, mintIndex);

        assertEq(_pool.treeSum(), mintAmount / 2);
        assert(positionUpdatedTwiceTokens > updatedLPTokens);

        // add liquidity to a different price, for same owner and tokenId
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 2, 2551, _p2995);

        assertEq(_pool.treeSum(), mintAmount);
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
        uint256 mintIndex      = 2550;

        mintAndApproveQuoteTokens(recipient, mintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, recipient, address(_pool), mintAmount / 4, mintIndex
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
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        mintAndApproveQuoteTokens(testAddress, mintAmount);
        uint256 testerQuoteBalance = _quote.balanceOf(testAddress);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintIndex, mintPrice);

        // check initial pool balance
        uint256 postAddPoolQuote = _pool.treeSum();

        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - mintAmount);
        assertEq(_pool.treeSum(), mintAmount);

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // find number of lp tokens received
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex); // RAY
        assertEq(originalLPTokens, 10_000 * 1e27);

        // remove 1/4 of the LP tokens
        uint256 lpTokensToRemove = originalLPTokens / 4;
        assertEq(lpTokensToRemove, 2_500 * 1e27);

        assertEq(_pool.treeSum(), 10_000 * 1e18);

        // decrease liquidity
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testAddress, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testAddress, mintPrice, 0, 2_500 * 1e18);

        // decrease liquidity and check change in balances
        vm.prank(testAddress);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check quote token removed
        assertEq(_pool.treeSum(), 7_500 * 1e18);
        assertGt(postAddPoolQuote, _pool.treeSum());
        assertEq(_quote.balanceOf(testAddress), testerQuoteBalance - _pool.treeSum());

        // check lp tokens matches expectations
        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);
        assertLt(updatedLPTokens, originalLPTokens);
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity.
     */
    function testDecreaseLiquidityWithDebtRedeemCollateralAndQuoteTokens() external {
        address testLender  = generateAddress();
        address testLender2 = generateAddress();
        uint256 mintAmount  = 50_000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        mintAndApproveQuoteTokens(testLender, mintAmount);
        mintAndApproveQuoteTokens(testLender2, mintAmount);

        uint256 tokenId = mintNFT(testLender, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(_pool), mintAmount, mintIndex, _p3010);

        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);
        assertEq(originalLPTokens, 50_000 * 1e27);
        uint256 postAddPoolQuote = _pool.treeSum();
        assertEq(postAddPoolQuote, 50_000 * 1e18);

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint        = 5_000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);
        assertEq(_collateral.balanceOf(address(testBorrower)), 5_000 * 1e18);

        // add collateral and borrow against it
        testBorrower.pledgeCollateral(_pool, collateralToMint, address(0), address(0));
        testBorrower.borrow(_pool, 25_000 * 1e18, 3000, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            0);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            0);
        assertEq(_quote.balanceOf(address(_pool)),        25_000 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        // bidder add less collateral to bucket than lender can redeem.
        // Lender will redeem all collateral from bucket and rest of LP tokens as quote tokens
        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50_000 * 1e18);
        testBidder.addCollateral(_pool, 1 * 1e18, mintIndex);

        // add additional quote tokens to enable reallocation decrease liquidity
        vm.prank(address(testLender2));
        _pool.addQuoteToken(40_000 * 1e18, mintIndex);

        // lender removes their provided liquidity
        uint256 lpTokensToRemove = originalLPTokens;

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testLender, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testLender, mintPrice, 1 * 1e18, 46_989.107977802118442155 * 1e18);
        vm.prank(testLender);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      43_010.892022197881557845 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            1 * 1e18);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            46_989.107977802118442155 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        18_010.892022197881557845 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, _p10016);
        assertEq(updatedLPTokens, 0);
    }

    function testDecreaseLiquidityWithDebtRedeemCollateralOnly() external {
        address testLender  = generateAddress();
        address testLender2 = generateAddress();
        uint256 mintAmount  = 50_000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        mintAndApproveQuoteTokens(testLender, mintAmount);
        mintAndApproveQuoteTokens(testLender2, mintAmount);

        uint256 tokenId = mintNFT(testLender, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(_pool), mintAmount, mintIndex, _p3010);

        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);
        assertEq(originalLPTokens, 50_000 * 1e27);
        uint256 postAddPoolQuote = _pool.treeSum();
        assertEq(postAddPoolQuote, 50_000 * 1e18);

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint        = 5_000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);
        assertEq(_collateral.balanceOf(address(testBorrower)), 5_000 * 1e18);

        // add collateral and borrow against it
        testBorrower.pledgeCollateral(_pool, collateralToMint, address(0), address(0));
        testBorrower.borrow(_pool, 25_000 * 1e18, 3000, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            0);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            0);
        assertEq(_quote.balanceOf(address(_pool)),        25_000 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        // bidder add more collateral to bucket than lender can redeem.
        // Lender will redeem all LPs as collateral
        UserWithCollateral testBidder = new UserWithCollateral();
        mintAndApproveCollateralTokens(testBidder, 50_000 * 1e18);
        testBidder.addCollateral(_pool, 100 * 1e18, mintIndex);

        // add additional quote tokens to enable reallocation decrease liquidity
        vm.prank(address(testLender2));
        _pool.addQuoteToken(40_000 * 1e18, mintIndex);

        // lender removes their provided liquidity
        uint256 lpTokensToRemove = originalLPTokens;

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testLender, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testLender, mintPrice, 16.606374334042426440 * 1e18, 0);
        vm.prank(testLender);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      90_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_083.393625665957573560 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            16.606374334042426440 * 1e18);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            0);
        assertEq(_quote.balanceOf(address(_pool)),        65_000 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, _p10016);
        assertEq(updatedLPTokens, 0);
    }

    function testDecreaseLiquidityWithDebtRedeemQuoteTokensOnly() external {
        address testLender  = generateAddress();
        address testLender2 = generateAddress();
        uint256 mintAmount  = 50_000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        mintAndApproveQuoteTokens(testLender, mintAmount);
        mintAndApproveQuoteTokens(testLender2, mintAmount);

        uint256 tokenId = mintNFT(testLender, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testLender, address(_pool), mintAmount, mintIndex, _p3010);

        // check position info
        uint256 originalLPTokens = _positionManager.getLPTokens(tokenId, mintIndex);
        assertEq(originalLPTokens, 50_000 * 1e27);
        uint256 postAddPoolQuote = _pool.treeSum();
        assertEq(postAddPoolQuote, 50_000 * 1e18);

        // Borrow against the pool
        UserWithCollateral testBorrower = new UserWithCollateral();
        uint256 collateralToMint        = 5_000 * 1e18;
        mintAndApproveCollateralTokens(testBorrower, collateralToMint);
        assertEq(_collateral.balanceOf(address(testBorrower)), 5_000 * 1e18);

        // add collateral and borrow against it
        testBorrower.pledgeCollateral(_pool, collateralToMint, address(0), address(0));
        testBorrower.borrow(_pool, 25_000 * 1e18, 3000, address(0), address(0));

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      50_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            0);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            0);
        assertEq(_quote.balanceOf(address(_pool)),        25_000 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        // add additional quote tokens to enable reallocation decrease liquidity
        vm.prank(address(testLender2));
        _pool.addQuoteToken(40_000 * 1e18, mintIndex);

        // lender removes their provided liquidity
        uint256 lpTokensToRemove = originalLPTokens;

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testLender, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testLender, mintPrice, 0, 50_000 * 1e18);
        vm.prank(testLender);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);

        // check pool state
        assertEq(_pool.htp(), 5.004807692307692310 * 1e18);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.treeSum(),      40_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 25_024.038461538461550000 * 1e18);
        assertEq(_pool.lenderDebt(),   25_000 * 1e18);

        // check token balances
        assertEq(_collateral.balanceOf(address(_pool)),        5_000 * 1e18);
        assertEq(_collateral.balanceOf(testLender),            0 * 1e18);
        assertEq(_collateral.balanceOf(address(testBorrower)), 0);

        assertEq(_quote.balanceOf(testLender),            50_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),        15_000 * 1e18);
        assertEq(_quote.balanceOf(address(testBorrower)), 25_000 * 1e18);

        uint256 updatedLPTokens = _positionManager.getLPTokens(tokenId, _p10016);
        assertEq(updatedLPTokens, 0);
    }

    /**
     *  @notice Tests minting an NFT, increasing liquidity, borrowing, purchasing then decreasing liquidity in an NFT Pool.
     *          Lender reverts when attempting to interact with a pool the tokenId wasn't minted in
     */
    function testDecreaseLiquidityWithDebtNFTPool() external {
        // TODO implement when ERC721 pool backported
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
        uint256 testIndexPrice  = 2550;
        uint256 testBucketPrice = _p3010;
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

        increaseLiquidity(tokenId, newOwner, address(_pool), mintAmount, testIndexPrice, testBucketPrice);

        // check previous owner can no longer modify the NFT
        uint256 nextMintAmount = 50_000 * 1e18;
        mintAndApproveQuoteTokens(originalOwner, nextMintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, originalOwner, address(_pool), mintAmount / 4, testIndexPrice
        );

        vm.expectRevert("PM:NO_AUTH");
        _positionManager.increaseLiquidity(increaseLiquidityParams);

        // check new owner can decreaseLiquidity
        uint256 lpTokensToAttempt = _positionManager.getLPTokens(tokenId, testIndexPrice);
        assertEq(lpTokensToAttempt, 50_000 * 1e27);

        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, newOwner, address(_pool), testIndexPrice, lpTokensToAttempt
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(newOwner, testBucketPrice, 0, 50_000 * 1e18); //
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
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add liquidity that can later be decreased
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount, mintIndex, mintPrice);

        // skip > 24h to avoid deposit removal penalty
        skip(3600 * 24 + 1);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, testAddress, mintIndex, address(_pool));

        // should revert if liquidity not removed
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        // remove all lp tokens
        uint256 lpTokensToRemove = _positionManager.getLPTokens(tokenId, mintIndex);
        assertEq(lpTokensToRemove, 10_000 * 10**27);
        assertEq(_pool.treeSum(), 10_000 * 1e18);

        // decrease liquidity
        IPositionManager.DecreaseLiquidityParams memory decreaseLiquidityParams = IPositionManager.DecreaseLiquidityParams(
            tokenId, testAddress, address(_pool), mintIndex, lpTokensToRemove
        );

        vm.expectEmit(true, true, true, true);
        emit DecreaseLiquidity(testAddress, mintPrice, 0, 10_000 * 1e18);

        // decrease liquidity and check change in balances
        vm.prank(testAddress);
        _positionManager.decreaseLiquidity(decreaseLiquidityParams);
        assertEq(_pool.treeSum(), 0);

        // should emit Burn
        vm.expectEmit(true, true, true, true);
        emit Burn(testAddress, mintPrice);

        // burn and check state changes
        vm.prank(testAddress);
        _positionManager.burn(burnParams);

        (, address burntPositionOwner, ) = _positionManager.positions(tokenId);

        assertEq(burntPositionOwner, 0x0000000000000000000000000000000000000000);
    }

    function testMoveLiquidity() external {
        // generate a new address
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;
        uint256 mintIndex   = 2550;
        uint256 mintPrice   = _p3010;
        uint256 moveIndex   = 2551;
        mintAndApproveQuoteTokens(testAddress, mintAmount);

        uint256 tokenId = mintNFT(testAddress, address(_pool));

        // add initial liquidity
        increaseLiquidity(tokenId, testAddress, address(_pool), mintAmount / 4, mintIndex, mintPrice);

        // check pool state
        assertEq(_pool.lpBalance(mintIndex, testAddress),               0);
        assertGt(_pool.lpBalance(mintIndex, address(_positionManager)), 0);
        assertEq(_pool.lpBalance(moveIndex, address(_positionManager)),      0);

        // construct move liquidity params
        IPositionManager.MoveLiquidityParams memory moveLiquidityParams = IPositionManager.MoveLiquidityParams(
            testAddress, tokenId, mintIndex, moveIndex
        );

        // move liquidity
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress, tokenId);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check pool state
        assertEq(_pool.lpBalance(mintIndex, testAddress),               0);
        assertEq(_pool.lpBalance(mintIndex, address(_positionManager)), 0);
        assertGt(_pool.lpBalance(moveIndex, address(_positionManager)), 0);
    }
}