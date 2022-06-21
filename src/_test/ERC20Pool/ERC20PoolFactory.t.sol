// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { PoolDeployer } from "../../base/PoolDeployer.sol";

import { IPoolFactory } from "../../base/interfaces/IPoolFactory.sol";

import { DSTestPlus } from "../utils/DSTestPlus.sol";

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
        address poolAddress = _factory.deployPool(address(_collateral), address(_quote), 0.1 * 10**18);
        ERC20Pool pool = ERC20Pool(poolAddress);

        assertEq(address(pool.collateral()), address(_collateral));
        assertEq(address(pool.quoteToken()), address(_quote));
        assertEq(pool.interestRate(),        0.1 * 10**18);
    }

    /**
     *  @notice Tests revert if actor attempts to deploy ETH pool.
     */
    function testDeployPoolEther() external {
        vm.expectRevert("PF:DP:ZERO_ADDR");
        _factory.deployPool(address(_collateral), address(0), 0.05 * 10**18);

        vm.expectRevert("PF:DP:ZERO_ADDR");
        _factory.deployPool(address(0), address(_collateral), 0.05 * 10**18);
    }

    /**
     *  @notice Tests revert if actor attempts to deploy the same pair.
     */
    function testDeployPoolTwice() external {
        _factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        vm.expectRevert("PF:DP:POOL_EXISTS");
        _factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
    }

    /**
     *  @notice Tests revert if interest rate not between 1% and 10%.
     */
    function testDeployPoolInvalidRate() external {
        vm.expectRevert("PF:DP:INVALID_RATE");
        _factory.deployPool(address(_collateral), address(_quote), 0.11 * 10**18);

        vm.expectRevert("PF:DP:INVALID_RATE");
        _factory.deployPool(address(_collateral), address(_quote), 0.009 * 10**18);
    }

}
