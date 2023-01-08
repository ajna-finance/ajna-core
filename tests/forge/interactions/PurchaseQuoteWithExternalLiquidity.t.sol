// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@std/Test.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';

import "./BalancerUniswapExample.sol";

contract PurchaseQuoteWithExternalLiquidityTest is Test {
    address constant WETH     = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC     = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AJNA     = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    uint24  constant POOL_FEE = 3000;

    IWETH  private weth = IWETH(WETH);
    IERC20 private usdc = IERC20(USDC);

    ERC20Pool internal _ajnaPool;
    address   internal _lender;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _ajnaPool = ERC20Pool(new ERC20PoolFactory(AJNA).deployPool(WETH, USDC, 0.05 * 10**18));
        _lender   = makeAddr("lender");

        deal(USDC, _lender, 120_000 * 1e6);
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(5_000 * 1e18, 500);
        vm.stopPrank();
    }

    function testPurchaseWithFlashLoan() external {
        BalancerUniswapPurchaser purchaseContract = new BalancerUniswapPurchaser();
        assertEq(0, weth.balanceOf(address(this)));
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        uint256[] memory amounts = new uint256[](2);
        amounts[1] = 1 * 1e18; // take flash loan of 1 WETH

        bytes memory data = abi.encode(
            BalancerUniswapPurchaser.PurchaseData({
                ajnaPool:    address(_ajnaPool),
                bucketIndex: 500,
                amount:      1 * 1e18
            })
        );
        purchaseContract.purchase(tokens, amounts, data);
        assertGt(weth.balanceOf(address(this)), 1e18); // could vary
    }

}
