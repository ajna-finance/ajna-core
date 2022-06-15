// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";
import { PositionManager }  from "../PositionManager.sol";

import { IPositionManager } from "../interfaces/IPositionManager.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract MulticallTest is DSTestPlus {

    address          internal _poolAddress;
    CollateralToken  internal _collateral;
    ERC20Pool        internal _pool;
    PositionManager  internal _positionManager;
    QuoteToken       internal _quote;

    function setUp() external {
        _collateral      = new CollateralToken();
        _quote           = new QuoteToken();
        _poolAddress     = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool            = ERC20Pool(_poolAddress);
        _positionManager = new PositionManager();
    }

    function mintAndApproveQuoteTokens(address operator, uint256 mintAmount) private {
        _quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator);
        _quote.approve(address(_positionManager), type(uint256).max);
    }

    /**
     *  @notice Use multicall to aggregate memorializePosition and increaseLiquidity method calls into one tx.
     */
    function testMulticallMemorializeIncreaseLiquidity() external {
        address testAddress = generateAddress();
        uint256 mintAmount  = 10000 * 1e18;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        // add quote tokens to several buckets
        uint256 priceOne   = _p4000;
        uint256 priceTwo   = _p3010;
        uint256 priceThree = _p1004;
        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceOne);
        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceTwo);
        _pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceThree);

        // mint an NFT capable of representing the positions
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(testAddress, address(_pool));
        uint256 tokenId = _positionManager.mint(mintParams);

        // Prepare to memorialize the extant positions with the just minted NFT
        uint256[] memory pricesToMemorialize = new uint256[](3);
        pricesToMemorialize[0] = priceOne;
        pricesToMemorialize[1] = priceTwo;
        pricesToMemorialize[2] = priceThree;

        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager.MemorializePositionsParams(
            tokenId, testAddress, address(_pool), pricesToMemorialize
        );

        // Prepare to add quotte tokens to a new price bucket and associate with NFT
        uint256 additionalAmount           = 1000 * 1e18;
        uint256 newPriceToAddQuoteTokensTo = _p5007;
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, testAddress, address(_pool), additionalAmount, newPriceToAddQuoteTokensTo
        );

        bytes[] memory callsToExecute = new bytes[](2);

        // https://ethereum.stackexchange.com/questions/65980/passing-struct-as-an-argument-in-call
        callsToExecute[0] = abi.encodeWithSignature(
            "memorializePositions((uint256,address,address,uint256[]))",
            memorializeParams
        );
        callsToExecute[1] = abi.encodeWithSignature(
            "increaseLiquidity((uint256,address,address,uint256,uint256))",
            increaseLiquidityParams
        );

        uint256 lpTokensAtNewPrice = _positionManager.getLPTokens(tokenId, newPriceToAddQuoteTokensTo);
        assertEq(lpTokensAtNewPrice, 0);

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(testAddress, newPriceToAddQuoteTokensTo, additionalAmount);

        vm.prank(testAddress);
        _positionManager.multicall(callsToExecute);

        lpTokensAtNewPrice = _positionManager.getLPTokens(tokenId, newPriceToAddQuoteTokensTo);
        assertGt(lpTokensAtNewPrice, 0);
    }

    /**
     *  @notice Attempt two different multicalls that should revert and verify the revert reason is captured and returned properly.
     */
    function testMulticallRevertString() public {
        address recipient      = generateAddress();
        address externalCaller = generateAddress();

        // mint an NFT
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(recipient, address(_pool));
        uint256 tokenId = _positionManager.mint(mintParams);

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice  = _p5007;
        mintAndApproveQuoteTokens(recipient, mintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager.IncreaseLiquidityParams(
            tokenId, recipient, address(_pool), mintAmount, mintPrice
        );

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(tokenId, recipient, mintPrice);

        bytes[] memory callsToExecute = new bytes[](2);

        // https://ethereum.stackexchange.com/questions/65980/passing-struct-as-an-argument-in-call
        callsToExecute[0] = abi.encodeWithSignature(
            "increaseLiquidity((uint256,address,address,uint256,uint256))",
            increaseLiquidityParams
        );
        callsToExecute[1] = abi.encodeWithSignature("burn((uint256,address,uint256))", burnParams);

        // attempt to modify the NFT from an unapproved EOA
        vm.prank(externalCaller);
        vm.expectRevert("PM:NO_AUTH");
        _positionManager.multicall(callsToExecute);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient, mintPrice, mintAmount);

        // attempt to increase liquidity and then burn the NFT without decreasing liquidity
        vm.prank(recipient);
        vm.expectRevert("PM:B:LIQ_NOT_REMOVED");
        _positionManager.multicall(callsToExecute);

        // TODO: add case for custom error string -> figure out how to induce such a revert
    }

}
