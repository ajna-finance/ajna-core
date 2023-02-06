// SPDX-License-Identifier: UNLICENSED

import { BaseInvariants }            from "../invariants/BaseInvariants.t.sol";

pragma solidity 0.8.14;


contract RegressionTest is BaseInvariants { 

    function setUp() public override { 
        super.setUp();

    }

    function test_regression_invariantUnderflow_1() external {
        _basicPoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000);
        // check invariants hold true
        invariant_Lps();
    }

}