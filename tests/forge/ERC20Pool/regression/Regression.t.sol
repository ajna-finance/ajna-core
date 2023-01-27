// SPDX-License-Identifier: UNLICENSED

import { BaseInvariants }            from "../invariants/BaseInvariants.t.sol";

pragma solidity 0.8.14;


contract RegressionTest is BaseInvariants { 

    function setUp() public override { 
        super.setUp();

    }

    function test_regression_invariantUnderflow_1() external {
        // _basicPoolHandler.addQuoteToken(0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 2590);
        _basicPoolHandler.drawDebt(16210, 5910);
    }



}