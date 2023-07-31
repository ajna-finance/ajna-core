// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { ERC721PoolPositionsInvariants } from "../../invariants/PositionsAndRewards/ERC721PoolPositionsInvariants.t.sol";

contract RegressionTestERC721PoolPositionsManager is ERC721PoolPositionsInvariants {

    function setUp() public override { 
        super.setUp();
    }

    // `NoAllowance()` revert was firing but wasn't tracked by positionManager handler class
    function test_regression_failure_no_allowance_err() external {
        _erc721positionHandler.moveLiquidity(2, 2726918499846956781196026606977128745, 4671573035498269269631531108867257349254074281251805650007376127, 136472940433983213576424627235038299016985732062067347200674016);
        _erc721positionHandler.memorializePositions(10365, 771, 8152, 3186);
    }
}