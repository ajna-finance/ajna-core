// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { SettleERC20PoolInvariants } from "../../invariants/ERC20Pool/SettleERC20PoolInvariants.t.sol";

contract RegressionTestSettleERC20Pool is SettleERC20PoolInvariants { 

    function setUp() public override {
        // failures reproduced with default number of active buckets
        vm.setEnv("NO_OF_BUCKETS", "3");
        super.setUp();
    }

    /**
        Test was failing because SettleERC20PoolHandler was not catching expected pool errors when repaying from a third party.
     */
    function test_regression_settle_then_repay() external {
        _settleERC20PoolHandler.settleDebt(3113042312187095938847976769131078147978133970801631984161493412007580, 71508422573531484609164655, 55359934378837189558162829458006585270105);
        /* Commented below call as repayDebt is not allowed if borrower is kicked and removed the handler from SettleERC20PoolInvariants. */
        // _settleERC20PoolHandler.repayDebtByThirdParty(1333, 3439, 3116, 2819);
        invariant_quote();
    }
}