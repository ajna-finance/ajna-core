// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.14;

import "@std/console.sol";

import './Interfaces.sol';

contract BalancerUniswapTaker {
    error NotBalancer();
    error NotOwner();

    address constant balancerAddress = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    ISwapRouter constant router      = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 constant POOL_FEE         = 3000;

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

    function take(address[] calldata tokens, uint256[] calldata amounts, bytes memory takeData) public payable {
        if (msg.sender != owner) revert NotOwner();

        IBalancer(balancerAddress).flashLoan(
            address(this),
            tokens,
            amounts,
            takeData
        );
    }

    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata feeAmounts,
        bytes calldata userData
    ) public payable {
        if (msg.sender != balancerAddress) revert NotBalancer();

        // received USDC flash loan from Balancer
        uint256 loanAmount = amounts[0];
        uint256 totalFunds = address(this).balance + loanAmount;
        console.log("USDC balance after Balancer loan", tokens[0].balanceOf(address(this)));
        console.log("WETH balance after Balancer loan", tokens[1].balanceOf(address(this)));

        TakeData memory decoded = abi.decode(userData, (TakeData));
        tokens[0].approve(decoded.ajnaPool, totalFunds);

        // take auction from Ajna pool, give USDC, receive WETH
        IAjnaPool(decoded.ajnaPool).take(decoded.borrower, decoded.maxAmount, new bytes(0));
        console.log("USDC balance after Ajna take", tokens[0].balanceOf(address(this)));
        console.log("WETH balance after Ajna take", tokens[1].balanceOf(address(this)));

        // swap WETH to USDC on Uniswap
        tokens[1].approve(address(router), tokens[1].balanceOf(address(this)));

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(tokens[1]),
                tokenOut: address(tokens[0]),
                fee: POOL_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: tokens[1].balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(params);
        console.log("USDC balance after Uniswap swap", tokens[0].balanceOf(address(this)));
        console.log("WETH balance after Uniswap swap", tokens[1].balanceOf(address(this)));

        // Repay USDC flash loan
        tokens[0].transfer(balancerAddress, loanAmount);
        // transfer remaining to taker
        tokens[0].transfer(decoded.taker, tokens[0].balanceOf(address(this)));
    }

    receive() external payable {}
}
