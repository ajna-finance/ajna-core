// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { IPoolErrors }      from 'src/interfaces/pool/commons/IPoolErrors.sol';
import { IPoolFactory }     from 'src/interfaces/pool/IPoolFactory.sol';

contract ERC20PoolFactoryTest is ERC20HelperContract {
    address immutable poolAddress = 0xeCAF6d240E0AdcaD5FfE4306b7D4301Df130bC02;

    function setUp() external {
        // deploy new pool factory for factory tests
        _poolFactory = new ERC20PoolFactory(_ajna);
    }

    function testInstantiateERC20FactoryWithZeroAddress() external {
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        new ERC20PoolFactory(address(0));
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
        
        // check tracking of deployed pools
        assertEq(_poolFactory.getDeployedPoolsList().length, 0);
    }

    function testDeployERC20PoolMultipleTimes() external {
        address poolOne = _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

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
        address poolTwo = _poolFactory.deployPool(address(_collateral), address(_collateral), 0.05 * 10**18);
        assertFalse(poolOne == poolTwo);

        // check tracking of deployed pools
        assertEq(_poolFactory.getDeployedPoolsList().length, 2);
        assertEq(_poolFactory.getNumberOfDeployedPools(),    2);
        assertEq(_poolFactory.getDeployedPoolsList()[0],     poolOne);
        assertEq(_poolFactory.deployedPoolsList(0),          poolOne);
        assertEq(_poolFactory.getDeployedPoolsList()[1],     poolTwo);
        assertEq(_poolFactory.deployedPoolsList(1),          poolTwo);
    }

    function testDeployERC20Pool() external {
        skip(333);

        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.poolType(),           0);
        assertEq(pool.collateralAddress(),  address(_collateral));
        assertEq(pool.collateralScale(),    10 ** 0);
        assertEq(pool.quoteTokenAddress(),  address(_quote));
        assertEq(pool.quoteTokenScale(),    10 ** 0);

        (uint256 interestRate, uint256 interestRateUpdate) = pool.interestRateInfo();
        assertEq(interestRate,       0.0543 * 10**18);
        assertEq(interestRateUpdate, _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);

        // check tracking of deployed pools
        assertEq(_poolFactory.getDeployedPoolsList().length, 1);
        assertEq(_poolFactory.getNumberOfDeployedPools(),    1);
        assertEq(_poolFactory.getDeployedPoolsList()[0],     poolAddress);
        assertEq(_poolFactory.deployedPoolsList(0),          poolAddress);
    }

    function testDeployERC20CompDaiPool() external {
        skip(333);

        address compAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address daiAddress  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(compAddress, daiAddress, 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.poolType(),           0);
        assertEq(pool.collateralAddress(),  compAddress);
        assertEq(pool.collateralScale(),    10 ** 0);
        assertEq(pool.quoteTokenAddress(),  daiAddress);
        assertEq(pool.quoteTokenScale(),    10 ** 0);

        (uint256 interestRate, uint256 interestRateUpdate) = pool.interestRateInfo();
        assertEq(interestRate,       0.0543 * 10**18);
        assertEq(interestRateUpdate, _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);
    }

    function testDeployERC20WbtcDaiPool() external {
        skip(333);

        address wbtcAddress = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address daiAddress  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(wbtcAddress, daiAddress, 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.poolType(),           0);
        assertEq(pool.collateralAddress(),  wbtcAddress);
        assertEq(pool.collateralScale(),    10 ** 10);         // WBTC has precision of 8, so 10 ** (18 - 8) = 10 ** 10
        assertEq(pool.quoteTokenAddress(),  daiAddress);
        assertEq(pool.quoteTokenScale(),    10 ** 0);          // DAI has precision of 18, so 10 ** (18 - 18) = 10 ** 0

        (uint256 interestRate, uint256 interestRateUpdate) = pool.interestRateInfo();
        assertEq(interestRate,       0.0543 * 10**18);
        assertEq(interestRateUpdate, _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);
    }

    function testDeployERC20WbtcUsdcPool() external {
        skip(333);

        address wbtcAddress = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(wbtcAddress, usdcAddress, 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.poolType(),           0);
        assertEq(pool.collateralAddress(),  wbtcAddress);
        assertEq(pool.collateralScale(),    10 ** 10);         // WBTC has precision of 8, so 10 ** (18 - 8) = 10 ** 10
        assertEq(pool.quoteTokenAddress(),  usdcAddress);
        assertEq(pool.quoteTokenScale(),    10 ** 12);         // USDC has precision of 6, so 10 ** (18 - 6) = 10 ** 12

        (uint256 interestRate, uint256 interestRateUpdate) = pool.interestRateInfo();
        assertEq(interestRate,       0.0543 * 10**18);
        assertEq(interestRateUpdate, _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);
    }

    function testDeployERC20CompUsdcPool() external {
        skip(333);

        address compAddress = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
        address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(compAddress, usdcAddress, 0.0543 * 10**18));

        assertEq(address(pool),             poolAddress);
        assertEq(pool.poolType(),           0);
        assertEq(pool.collateralAddress(),  compAddress);
        assertEq(pool.collateralScale(),    10 ** 0);
        assertEq(pool.quoteTokenAddress(),  usdcAddress);
        assertEq(pool.quoteTokenScale(),    10 ** 12);

        (uint256 interestRate, uint256 interestRateUpdate) = pool.interestRateInfo();
        assertEq(interestRate,       0.0543 * 10**18);
        assertEq(interestRateUpdate, _startTime + 333);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = pool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime + 333);
    }

    function testPoolAlreadyInitialized() external {
        vm.expectEmit(true, true, false, true);
        emit PoolCreated(poolAddress);
        address pool = _poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);

        vm.expectRevert(IPoolErrors.AlreadyInitialized.selector);
        ERC20Pool(pool).initialize(0.05 * 10**18);
    }

}
