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
        _assertDeployWith0xAddressRevert(
            {
                poolFactory:  address(_poolFactory),
                collateral:   address(0),
                quote:        address(_quote),
                interestRate: 0.05 * 10**18
            }
        );

        // should revert if trying to deploy with zero address as quote token
        _assertDeployWith0xAddressRevert(
            {
                poolFactory:  address(_poolFactory),
                collateral:   address(_collateral),
                quote:        address(0),
                interestRate: 0.05 * 10**18
            }
        );
    }

    function testDeployERC20PoolWithInvalidRate() external {
        // should revert if trying to deploy with interest rate lower than accepted
        _assertDeployWithInvalidRateRevert(
            {
                poolFactory:  address(_poolFactory),
                collateral:   address(_collateral),
                quote:        address(_quote),
                interestRate: 10**18
            }
        );

        // should revert if trying to deploy with interest rate higher than accepted
        _assertDeployWithInvalidRateRevert(
            {
                poolFactory:  address(_poolFactory),
                collateral:   address(_collateral),
                quote:        address(_quote),
                interestRate: 2 * 10**18
            }
        );
    }

    function testDeployERC20PoolMultipleTimes() external {
        _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy same pool one more time
        _assertDeployMultipleTimesRevert(
            {
                poolFactory:  address(_poolFactory),
                collateral:   address(_collateral),
                quote:        address(_quote),
                interestRate: 0.05 * 10**18
            }
        );

        // should deploy different pool
        _poolFactory.deployPool(address(_collateral), address(_collateral), 0.05 * 10**18);
    }

    function testDeployERC20Pool() external {
        skip(333);

        address poolAddress = 0x88c0A0F7B9f2D204C16409CF01d85D8BF1231f18;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.collateralAddress(),  address(_collateral));
        assertEq(pool.collateralScale(),    1);
        assertEq(pool.quoteTokenAddress(),  address(_quote));
        assertEq(pool.quoteTokenScale(),    1);
        assertEq(pool.interestRate(),       0.0543 * 10**18);
        assertEq(pool.interestRateUpdate(), _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);
    }

}
