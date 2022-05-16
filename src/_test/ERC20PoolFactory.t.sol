// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { IPoolFactory } from "../interfaces/IPoolFactory.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

contract PoolFactoryTest is DSTestPlus {

    ERC20            internal _collateral;
    ERC20            internal _quote;
    ERC20PoolFactory internal _factory;

    uint256 internal _count;

    function setUp() external {
        _factory    = new ERC20PoolFactory();
        _collateral = new ERC20("Collateral", "C");
        _quote      = new ERC20("Quote", "Q");
    }

    /**
     *  @notice Tests pool deployment.
     */
    function testDeployPool() external {
        address poolAddress = _factory.deployPool(address(_collateral), address(_quote));
        ERC20Pool pool = ERC20Pool(poolAddress);

        assertEq(address(_collateral), address(pool.collateral()));
        assertEq(address(_quote),      address(pool.quoteToken()));
    }

    /**
     *  @notice Tests revert if actor attempts to deploy ETH pool.
     */
    function testDeployPoolEther() external {
        vm.expectRevert(IPoolFactory.WethOnly.selector);
        _factory.deployPool(address(_collateral), address(0));

        vm.expectRevert(IPoolFactory.WethOnly.selector);
        _factory.deployPool(address(0), address(_collateral));
    }

    /**
     *  @notice Tests revert if actor attempts to deploy the same pair.
     */
    function testDeployPoolTwice() external {
        _factory.deployPool(address(_collateral), address(_quote));
        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        _factory.deployPool(address(_collateral), address(_quote));
    }

}
