// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import './Interfaces.sol';
import 'src/interfaces/pool/commons/IPoolLiquidationActions.sol';
import 'src/interfaces/pool/erc20/IERC20Taker.sol';

contract UniswapTakeExample is IERC20Taker {
    ISwapRouter constant          router   = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24      constant          UNISWAP_FEE = 3000;
    address     private immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function approveToken(IERC20 token) public {
        token.approve(address(router), type(uint256).max);
    }

    function atomicSwapCallback(
        uint256        collateralAmount, 
        uint256        quoteAmountDue,
        bytes calldata data
    ) external {
        // swap collateral for quote token using Uniswap
        address ajnaPoolAddress = abi.decode(data, (address));
        swap(ajnaPoolAddress, collateralAmount);

        // confirm the swap produced enough quote token for the take
        IERC20 quoteToken = IERC20(IAjnaPool(ajnaPoolAddress).quoteTokenAddress());
        assert(quoteToken.balanceOf(address(this)) > quoteAmountDue);
    }

    function swap(address ajnaPoolAddress, uint256 maxAmount) internal {
        IAjnaPool ajnaPool = IAjnaPool(ajnaPoolAddress);
        address collateralAddress = ajnaPool.collateralAddress();
        address quoteTokenAddress = ajnaPool.quoteTokenAddress();

        // assemble parameters to swap WETH for USDC on Uniswap 
        // https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter#exactinputsingleparams
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: collateralAddress,
                tokenOut: quoteTokenAddress,
                fee: UNISWAP_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: maxAmount,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        // execute the swap
        router.exactInputSingle(params);
    }
}
