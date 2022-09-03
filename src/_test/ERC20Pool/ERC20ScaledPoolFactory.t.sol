// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20ScaledPoolFactoryTest is ERC20HelperContract {
    ERC20PoolFactory internal _poolFactory;

    function setUp() external {
        _poolFactory = new ERC20PoolFactory();
    }

    function testDeployERC20PoolWithZeroAddress() external {
        // should revert if trying to deploy with zero address as collateral
        vm.expectRevert("PF:DP:ZERO_ADDR");
        _poolFactory.deployPool(address(0), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert("PF:DP:ZERO_ADDR");
        _poolFactory.deployPool(address(_collateral), address(0), 0.05 * 10**18);
    }

    function testDeployERC20PoolWithInvalidRate() external {
        // should revert if trying to deploy with interest rate lower than accepted
        vm.expectRevert("PF:DP:INVALID_RATE");
        _poolFactory.deployPool(address(_collateral), address(_quote), 10**18);

        // should revert if trying to deploy with interest rate higher than accepted
        vm.expectRevert("PF:DP:INVALID_RATE");
        _poolFactory.deployPool(address(_collateral), address(_quote), 2 * 10**18);
    }

    function testDeployERC20PoolMultipleTimes() external {
        _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy same pool one more time
        vm.expectRevert("PF:DP:POOL_EXISTS");
        _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // should deploy different pool
        _poolFactory.deployPool(address(_collateral), address(_collateral), 0.05 * 10**18);
    }

    function testDeployERC20Pool() external {
        skip(333);

        vm.expectEmit(true, true, false, true);
        emit PoolCreated(address(0x9FE92fe72Ae1Bc5f008C3f405606717d43Fc468D));
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.0543 * 10**18));

        assertEq(address(pool),                     address(0x9FE92fe72Ae1Bc5f008C3f405606717d43Fc468D));
        assertEq(address(pool.collateral()),        address(_collateral));
        assertEq(pool.collateralScale(),            1);
        assertEq(address(pool.quoteToken()),        address(_quote));
        assertEq(pool.quoteTokenScale(),            1);
        assertEq(pool.inflatorSnapshot(),           10**18);
        assertEq(pool.lastInflatorSnapshotUpdate(), 333);
        assertEq(pool.lenderInterestFactor(),       0.9 * 10**18);
        assertEq(pool.interestRate(),               0.0543 * 10**18);
        assertEq(pool.interestRateUpdate(),         333);
        assertEq(pool.minFee(),                     0.0005 * 10**18);
    }

}
