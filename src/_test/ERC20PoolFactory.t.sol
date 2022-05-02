// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { DSTestPlus } from "./utils/DSTestPlus.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../ERC20Pool.sol";
import "../ERC20PoolFactory.sol";

contract PoolFactoryTest is DSTestPlus {
    ERC20PoolFactory internal _factory;
    ERC20           internal _collateral;
    ERC20           internal _quote;
    uint256         internal _count;

    function setUp() external {
        _factory    = new ERC20PoolFactory();
        _collateral = new ERC20("Collateral", "C");
        _quote      = new ERC20("Quote", "Q");
    }

    // @notice: Tests pool deployment
    function testDeployPool() external {
        ERC20Pool pool = _factory.deployPool(address(_collateral), address(_quote));

        assertEq(address(_collateral),  address(pool.collateral()));
        assertEq(address(_quote),       address(pool.quoteToken()));
    }

    // @notice: Tests revert if actor attempts to deploy ETH pool
    function testDeployPoolEther() external {
        vm.expectRevert(ERC20PoolFactory.WethOnly.selector);
        _factory.deployPool(address(_collateral), address(0));

        vm.expectRevert(ERC20PoolFactory.WethOnly.selector);
        _factory.deployPool(address(0), address(_collateral));
    }

    // @notice: Tests revert if actor attempts to deploy the same pair
    function testDeployPoolTwice() external {
        _factory.deployPool(address(_collateral), address(_quote));
        vm.expectRevert(ERC20PoolFactory.PoolAlreadyExists.selector);
        _factory.deployPool(address(_collateral), address(_quote));
    }
}
