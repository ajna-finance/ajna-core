// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

interface IAjnaPool {
    function take(
        address borrower,
        uint256 maxAmount,
        bytes memory swapCalldata
    ) external;
}

interface IBalancer {
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut);
}

interface IERC20 {
    function approve(address, uint256) external;

    function balanceOf(address) external returns (uint256);

    function transfer(address, uint256) external;
}

interface IWETH is IERC20 {
    function deposit(uint256) external;

    function withdraw(uint256) external;
}
