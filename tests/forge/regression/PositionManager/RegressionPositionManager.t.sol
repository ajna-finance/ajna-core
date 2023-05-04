// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { PositionsInvariants } from "../../invariants/PositionsAndRewards/PositionsInvariants.t.sol";

contract RegressionPositionManager is PositionsInvariants { 

    function setUp() public override { 
        super.setUp();
    }
    
    function test_regression_evm_revert_1() external {
        _positionsHandler.memorializePositions(265065747026302585864021010218, 462486804883131506688620136159543, 43470270713791727776, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
    }

    function test_regression_evm_revert_2() external {
        _positionsHandler.burn(3492, 4670, 248, 9615);
    }
}