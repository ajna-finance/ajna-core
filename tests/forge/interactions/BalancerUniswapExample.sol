// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

import './Interfaces.sol';

contract BalancerUniswapTaker {
    error NotBalancer();
    error NotOwner();

    address constant balancerAddress = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    ISwapRouter constant router      = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 constant UNISWAP_FEE      = 3000;

    struct TakeData {
        address taker;
        address ajnaPool;
        address borrower;
        uint256 maxAmount;
    }
    address private immutable owner;

    constructor() {
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
        uint256[] calldata,
        bytes calldata userData
    ) public payable {
        if (msg.sender != balancerAddress) revert NotBalancer();

        // received USDC flash loan from Balancer
        uint256 loanAmount = amounts[0];
        uint256 totalFunds = address(this).balance + loanAmount;
        assert(tokens[0].balanceOf(address(this)) == 100000000);    // USDC balance after Balancer loan
        assert(tokens[1].balanceOf(address(this)) == 0);            // WETH balance after Balancer loan

        TakeData memory decoded = abi.decode(userData, (TakeData));
        tokens[0].approve(decoded.ajnaPool, totalFunds);

        // take auction from Ajna pool, give USDC, receive WETH
        IAjnaPool(decoded.ajnaPool).take(decoded.borrower, decoded.maxAmount, address(this), new bytes(0));
        uint256 usdcBalanceAfterTake = 85496538;
        assert(tokens[0].balanceOf(address(this)) == usdcBalanceAfterTake); // USDC balance after Ajna take
        assert(tokens[1].balanceOf(address(this)) == 2000000000000000000);  // WETH balance after Ajna take

        // swap WETH to USDC on Uniswap
        tokens[1].approve(address(router), tokens[1].balanceOf(address(this)));

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(tokens[1]),
                tokenOut: address(tokens[0]),
                fee: UNISWAP_FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: tokens[1].balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(params);
        assert(tokens[0].balanceOf(address(this)) > usdcBalanceAfterTake);  // USDC balance after Uniswap swap
        assert(tokens[1].balanceOf(address(this)) == 0);                    // WETH balance after Uniswap swap

        // Repay USDC flash loan
        tokens[0].transfer(balancerAddress, loanAmount);
        // transfer remaining to taker
        tokens[0].transfer(decoded.taker, tokens[0].balanceOf(address(this)));
    }

    receive() external payable {}
}

contract BalancerUniswapPurchaser {
    error NotBalancer();
    error NotOwner();

    address constant balancerAddress = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    struct PurchaseData {
        address ajnaPool;
        uint256 bucketIndex;
        uint256 amount;
    }
    address private immutable owner;

    constructor() {
        owner = msg.sender;
    }

    function purchase(address[] calldata tokens, uint256[] calldata amounts, bytes memory purchaseData) public payable {
        if (msg.sender != owner) revert NotOwner();

        IBalancer(balancerAddress).flashLoan(
            address(this),
            tokens,
            amounts,
            purchaseData
        );
    }

    function receiveFlashLoan(
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        uint256[] calldata,
        bytes calldata userData
    ) public payable {
        if (msg.sender != balancerAddress) revert NotBalancer();

        // received USDC flash loan from Balancer
        uint256 loanAmount = amounts[1];
        IERC20 quote       = tokens[0];
        IERC20 collateral  = tokens[1];
        assert(quote.balanceOf(address(this))      == 0);                   // USDC balance after Balancer loan
        assert(collateral.balanceOf(address(this)) == 1000000000000000000); // WETH balance after Balancer loan

        PurchaseData memory decoded = abi.decode(userData, (PurchaseData));
        // approve ajna pool to transfer flash loaned collateral
        collateral.approve(decoded.ajnaPool, loanAmount);
        // purchase USDC with 1 WETH from ajna
        uint256 lps             = IAjnaPool(decoded.ajnaPool).addCollateral(loanAmount, decoded.bucketIndex);
        (uint256 quoteAmount, ) = IAjnaPool(decoded.ajnaPool).removeQuoteToken(type(uint256).max, decoded.bucketIndex);
        assert(lps                                 == 83008350.10362729922336157 * 1e27);   // LPS in bucket
        assert(quoteAmount                         == 4995.19230769230769 * 1e18);          // Purchased quote amount
        assert(quote.balanceOf(address(this))      == 4995.192307 * 1e6); // USDC balance after Ajna purchase
        assert(collateral.balanceOf(address(this)) == 0);                 // WETH balance after Ajna purchase

        // swap USDC to WETH on Uniswap, approve router to spend USDC purchased from ajna
        quote.approve(address(router), quoteAmount);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(quote),
                tokenOut: address(collateral),
                fee: 3000,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: quote.balanceOf(address(this)),
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

        router.exactInputSingle(params);
        assert(quote.balanceOf(address(this))      == 0);    // USDC balance after Uniswap swap
        assert(collateral.balanceOf(address(this)) > 1e18);  // WETH balance after Uniswap swap

        // Repay WETH flash loan
        collateral.transfer(balancerAddress, loanAmount);
        // transfer remaining WETH to contract owner
        collateral.transfer(owner, collateral.balanceOf(address(this)));
    }

    receive() external payable {}
}
