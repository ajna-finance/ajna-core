// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { Token } from '../utils/Tokens.sol';

import 'src/interfaces/pool/IERC3156FlashBorrower.sol';
import 'src/libraries/internal/Maths.sol';

contract FlashloanBorrower is IERC3156FlashBorrower {
    bool    public   callbackInvoked = false;
    address internal strategy;
    bytes   internal strategyCallData;
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address strategy_, bytes memory strategyCallData_) {
        strategy         = strategy_;
        strategyCallData = strategyCallData_;
    }

    function onFlashLoan(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes32 result_) {
        callbackInvoked = true;
        (bool success, ) = strategy.call(strategyCallData);
        if (success) result_ = CALLBACK_SUCCESS;
    }
}

// Example of some defi strategy which produces a fixed return
contract SomeDefiStrategy {
    Token public token;

    constructor(Token token_) {
        token = token_;
    }

    function makeMoney(uint256 amount_) external {
        // step 1: take deposit from caller
        token.transferFrom(msg.sender, address(this), amount_);
        // step 2: earn 3.5% reward
        uint256 reward = Maths.wmul(0.035 * 1e18, amount_);
        // step 3: profit
        token.transfer(msg.sender, amount_ + reward);
    }
}