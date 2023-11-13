// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@std/Test.sol";
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { IPoolErrors }      from 'src/interfaces/pool/commons/IPoolErrors.sol';

import 'src/PoolInfoUtils.sol';

import "./BalancerUniswapExample.sol";
import "./UniswapTakeExample.sol";

contract ERC20TakeWithExternalLiquidityTest is Test {
    // pool events
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);

    address constant WETH     = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC     = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AJNA     = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    uint24  constant POOL_FEE = 3000;

    IWETH  private weth = IWETH(WETH);
    IERC20 private usdc = IERC20(USDC);

    ERC20Pool internal _ajnaPool;
    PoolInfoUtils internal _poolUtils;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        // create an Ajna pool
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _ajnaPool = ERC20Pool(new ERC20PoolFactory(AJNA).deployPool(WETH, USDC, 0.05 * 10**18));
        _poolUtils   = new PoolInfoUtils();

        // create lenders and borrowers
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        // fund lenders with quote token
        deal(USDC, _lender, 120_000 * 1e18);
        deal(USDC, _lender1, 120_000 * 1e18);

        // fund borrowers with collateral
        deal(WETH, _borrower,  4 * 1e18);
        deal(WETH, _borrower2, 1_000 * 1e18);
        deal(WETH, _lender1,  4 * 1e18);

        // add liquidity to the Ajna pool
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(2_000 * 1e18, 3696, type(uint256).max, false);
        _ajnaPool.addQuoteToken(5_000 * 1e18, 3698, type(uint256).max, false);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700, type(uint256).max, false);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702, type(uint256).max, false);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704, type(uint256).max, false);
        vm.stopPrank();

    }

    function testRemoveQuoteDust() external {
 
        (
            uint256 price_,
            uint256 quoteTokens_,
            uint256 collateral_,
            uint256 bucketLP_,
            uint256 scale_,
            uint256 exchangeRate_
        ) = _poolUtils.bucketInfo(address(_ajnaPool), 3696);

        assertEq(bucketLP_, 2_000 * 1e18);
        assertEq(quoteTokens_, 2_000 * 1e18);

        // call reverts as lender is attempting to leave dust amount in bucket -> 1
        vm.startPrank(_lender);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        _ajnaPool.removeQuoteToken(1_999.999999999999999999 * 1e18, 3696);
        vm.stopPrank();

        vm.startPrank(_lender);
        _ajnaPool.removeQuoteToken(1_999.999999 * 1e18, 3696);
        vm.stopPrank();

        (
            ,
            quoteTokens_,
            ,
            bucketLP_,
            ,
            
        ) = _poolUtils.bucketInfo(address(_ajnaPool), 3696);

        assertEq(bucketLP_, 0.000001000000000000 * 1e18);
        assertEq(quoteTokens_, 0.000001000000000000  * 1e18);
    }

    function testMoveQuoteDust() external {
 
        (
            uint256 price_,
            uint256 quoteTokens_,
            uint256 collateral_,
            uint256 bucketLP_,
            uint256 scale_,
            uint256 exchangeRate_
        ) = _poolUtils.bucketInfo(address(_ajnaPool), 3696);

        assertEq(bucketLP_, 2_000 * 1e18);
        assertEq(quoteTokens_, 2_000 * 1e18);

        // call reverts as lender is attempting to leave dust amount in bucket -> 1
        vm.startPrank(_lender);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        _ajnaPool.moveQuoteToken(1_999.999999999999999999 * 1e18, 3696, 3698, type(uint256).max, false);
        vm.stopPrank();

        vm.startPrank(_lender);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        _ajnaPool.moveQuoteToken(1, 3696, 3701, type(uint256).max, false);
        vm.stopPrank();

        vm.startPrank(_lender);
        _ajnaPool.moveQuoteToken(0.000001 * 1e18, 3696, 3701, type(uint256).max, false);
        vm.stopPrank();

        (
            ,
            quoteTokens_,
            ,
            bucketLP_,
            ,
            
        ) = _poolUtils.bucketInfo(address(_ajnaPool), 3701);

        assertEq(bucketLP_, 0.000001000000000000 * 1e18);
        assertEq(quoteTokens_, 0.000001000000000000  * 1e18);
    }

}
