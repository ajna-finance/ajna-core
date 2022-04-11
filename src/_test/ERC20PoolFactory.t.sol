// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../ERC20Pool.sol";
import "../ERC20PoolFactory.sol";

contract PoolFactoryTest is DSTestPlus {
    ERC20PoolFactory internal factory;
    ERC20 internal collateral;
    ERC20 internal quote;
    uint256 internal count;

    function setUp() public {
        factory = new ERC20PoolFactory();
        collateral = new ERC20("Collateral", "C");
        quote = new ERC20("Quote", "Q");
    }

    function testDeployPool() public {
        ERC20Pool pool = factory.deployPool(collateral, quote);

        assertEq(address(collateral), address(pool.collateral()));
        assertEq(address(quote), address(pool.quoteToken()));
    }

    function testDeployPoolTwice() public {
        factory.deployPool(collateral, quote);
        vm.expectRevert(ERC20PoolFactory.PoolAlreadyExists.selector);
        factory.deployPool(collateral, quote);
    }
}
