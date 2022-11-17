// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.14;

import './Interfaces.sol';

contract UniswapTakeExample {
    ISwapRouter constant router = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 constant POOL_FEE    = 3000;

    struct TakeData {
        address taker;
        address ajnaPool;
        address borrower;
        uint256 maxAmount;
    }
    address private immutable owner;

    constructor() public {
        owner = msg.sender;
    }

    function approveToken(IERC20 token) public {
        token.approve(address(router), type(uint256).max);
    }

    function swap(address ajnaPoolAddress, uint256 maxAmount) public  {
        IAjnaPool ajnaPool = IAjnaPool(ajnaPoolAddress);
        address collateralAddress = ajnaPool.collateralAddress();
        address quoteTokenAddress = ajnaPool.quoteTokenAddress();

        // assemble calldata to swap WETH for USDC on Uniswap 
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: collateralAddress,
                tokenOut: quoteTokenAddress,
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: maxAmount,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });

        // https://docs.uniswap.org/protocol/reference/periphery/interfaces/ISwapRouter#exactinputsingleparams
        router.exactInputSingle(params);
    }
}
