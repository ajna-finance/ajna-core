// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import "@std/Test.sol";
import "@std/console.sol";

import { ERC20Pool }        from 'src/erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/erc20/ERC20PoolFactory.sol';

import 'src/base/PoolInfoUtils.sol';
import "./BalancerUniswapExample.sol";
import "./UniswapTakeExample.sol";

contract TakeWithExternalLiquidityTest is Test {
    address constant WETH     = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC     = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint24  constant POOL_FEE = 3000;

    IWETH  private weth = IWETH(WETH);
    IERC20 private usdc = IERC20(USDC);

    ERC20Pool internal _ajnaPool;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        // 0x81fA6B9325b869eF7C70218A869e1b63d06A6328
        _ajnaPool = ERC20Pool(new ERC20PoolFactory().deployPool(WETH, USDC, 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        deal(USDC, _lender, 120_000 * 1e18);
        deal(USDC, _lender1, 120_000 * 1e18);

        deal(WETH, _borrower,  4 * 1e18);
        deal(WETH, _borrower2, 1_000 * 1e18);
        deal(WETH, _lender1,  4 * 1e18);

        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(2_000 * 1e18, 3696);
        _ajnaPool.addQuoteToken(5_000 * 1e18, 3698);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704);
        vm.stopPrank();

        vm.startPrank(_borrower);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.pledgeCollateral(_borrower, 2 * 1e18);
        _ajnaPool.borrow(19.25 * 1e18, 3696);
        vm.stopPrank();

        vm.startPrank(_borrower2);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.pledgeCollateral(_borrower2, 1_000 * 1e18);
        _ajnaPool.borrow(7_980 * 1e18, 3700);
        vm.stopPrank();

        skip(100 days);
        vm.prank(_lender);
        _ajnaPool.kick(_borrower);
        skip(6 hours);
    }

    function testTakeWithFlashLoan() external {
        BalancerUniswapTaker taker = new BalancerUniswapTaker();

        // assert USDC balance before take
        console.log("USDC starting balance", usdc.balanceOf(address(this)));
        assertEq(0, usdc.balanceOf(address(this)));
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 100 * 1e6;

        bytes memory data = abi.encode(
            BalancerUniswapTaker.TakeData({
                taker:     address(this),
                ajnaPool:  address(_ajnaPool),
                borrower:  _borrower,
                maxAmount: 10 * 1e18
            })
        );
        taker.take(tokens, amounts, data);

        console.log("USDC ending balance", usdc.balanceOf(address(this)));
        assertGt(usdc.balanceOf(address(this)), 1000); // could vary
    }

    function testTakeWithAtomicSwap() external {
        // assert no USDC balance before take
        address taker = makeAddr("taker");  // 0x93646Ca7a11660aF7d74e9B08ef0aA99D1a69D81
        vm.makePersistent(taker);
        changePrank(taker);

        ISwapRouter router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        uint256 maxTakeAmount = 10 * 1e18;
        weth.approve(address(router), maxTakeAmount);
        usdc.approve(address(_ajnaPool), 100_000 * 1e18);

        assertLt(_getAuctionPrice(_borrower), 1000 * 1e18);

        // assemble calldata to swap WETH for USDC on Uniswap 
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: USDC,
                fee: POOL_FEE,
                recipient: taker,
                deadline: block.timestamp,
                amountIn: 2 * 1e18,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        // https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter#exactinputsingleparams
        bytes memory swapCalldata = abi.encodeWithSignature("exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))", 
            params.tokenIn, 
            params.tokenOut, 
            params.fee,
            params.recipient,
            params.deadline,
            params.amountIn,
            params.amountOutMinimum,
            params.sqrtPriceLimitX96);

        if (true) {   // practice swap
            deal(WETH, taker,  2 * 1e18);
            uint256 usdcBalanceBefore = usdc.balanceOf(taker);

            (bool success, ) = address(router).call(swapCalldata);
            assertEq(success, true);

            uint256 usdcBalanceAfter = usdc.balanceOf(taker);
            assertGt(usdcBalanceAfter, usdcBalanceBefore);
        } else {
            // TODO: Need to pass uniswap address as callee somehow
            _ajnaPool.take(_borrower, maxTakeAmount, swapCalldata);
        }
    }

    function testTakeFromContractWithAtomicSwap() external {
        UniswapTakeExample taker = new UniswapTakeExample();
        changePrank(address(taker));

        uint256 takeAmount = 2 * 1e18;  // CAUTION: must be <= amount of collateral available
        taker.approveToken(weth);
        weth.approve(address(taker), takeAmount);
        usdc.approve(address(_ajnaPool), type(uint256).max);

        bytes memory swapCalldata = abi.encodeWithSignature("swap(address,uint256)", 
            address(_ajnaPool),
            takeAmount);

        _ajnaPool.take(_borrower, takeAmount, swapCalldata);
    }

    function _getAuctionPrice(address borrower) internal view returns (uint256) {
        (, , uint256 kickTime, uint256 kickMomp, , ) = _ajnaPool.auctionInfo(borrower);
        return PoolUtils.auctionPrice(kickMomp, kickTime);
    }

}
