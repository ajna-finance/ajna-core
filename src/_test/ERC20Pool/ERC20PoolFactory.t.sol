// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../base/PoolDeployer.sol';

contract ERC20PoolFactoryTest is ERC20HelperContract {
    ERC20PoolFactory internal _poolFactory;

    function setUp() external {
        _poolFactory = new ERC20PoolFactory();
    }

    function testDeployERC20PoolWithZeroAddress() external {
        // should revert if trying to deploy with zero address as collateral
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _poolFactory.deployPool(address(0), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _poolFactory.deployPool(address(_collateral), address(0), 0.05 * 10**18);
    }

    function testDeployERC20PoolWithInvalidRate() external {
        // should revert if trying to deploy with interest rate lower than accepted
        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _poolFactory.deployPool(address(_collateral), address(_quote), 10**18);

        // should revert if trying to deploy with interest rate higher than accepted
        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _poolFactory.deployPool(address(_collateral), address(_quote), 2 * 10**18);
    }

    function testDeployERC20PoolMultipleTimes() external {
        _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy same pool one more time
        vm.expectRevert(PoolDeployer.PoolAlreadyExists.selector);
        _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // should deploy different pool
        _poolFactory.deployPool(address(_collateral), address(_collateral), 0.05 * 10**18);
    }

    function testDeployERC20Pool() external {
        skip(333);

        address poolAddress = 0x8b233290C5458EdF1a03e2303Abc8aDCB52d5286;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.0543 * 10**18));

        assertEq(address(pool),                     poolAddress);
        assertEq(address(pool.collateral()),        address(_collateral));
        assertEq(pool.collateralScale(),            1);
        assertEq(address(pool.quoteToken()),        address(_quote));
        assertEq(pool.quoteTokenScale(),            1);
        assertEq(pool.inflatorSnapshot(),           10**18);
        assertEq(pool.lastInflatorSnapshotUpdate(), _startTime + 333);
        assertEq(pool.interestRate(),               0.0543 * 10**18);
        assertEq(pool.interestRateUpdate(),         _startTime + 333);
        assertEq(pool.minFee(),                     0.0005 * 10**18);
    }

}
