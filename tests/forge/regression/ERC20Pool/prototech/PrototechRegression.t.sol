// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { BasicERC20PoolInvariants } from "../../../invariants/ERC20Pool/BasicERC20PoolInvariants.t.sol";

contract PrototechRegressionTestBasicWith10BucketsIndex6500Pool is BasicERC20PoolInvariants { 

    function setUp() public override {
        // failures reproduced with 10 active buckets
        vm.setEnv("NO_OF_BUCKETS", "10");
        vm.setEnv("BUCKET_INDEX_ERC20", "6500");
        super.setUp();
    }

    function test_regression_prototech_R7() external {
        _basicERC20PoolHandler.addCollateral(
            2,                               // actor index
            787978178697424804260644669040,  // amount to add, 787978178697.42480426064466904 * 10^18
            6502,                            // bucket index
            13838                            // skipped time
        );
        _basicERC20PoolHandler.transferLps(
            7,           // from actor index
            5,           // to actor index
            1672524930,  // lps to transfer
            6502,        // bucket index
            83798        // skipped time
        );
        _basicERC20PoolHandler.removeCollateral(
            5,      // actor index
            37232,  // amount to remove
            6502,   // bucket index
            46650   // skipped time
        );

        invariant_bucket();
    }
}