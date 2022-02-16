// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@ds-test/test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../ERC20PerpPool.sol";
import "../ERC20PoolFactory.sol";

contract PoolFactoryTest is DSTest {
    ERC20PoolFactory internal factory;
    ERC20 internal collateral;
    ERC20 internal quote;
    uint256 internal count;

    function setUp() public {
        factory = new ERC20PoolFactory();
        collateral = new ERC20("Collateral", "C");
        quote = new ERC20("Quote", "Q");
        count = 7000;
    }

    function testDeploy() public {
        ERC20PerpPool pool = factory.deployPool(collateral, quote, count);

        assertEq(address(collateral), address(pool.collateralToken()));
        assertEq(address(quote), address(pool.quoteToken()));
        assertEq(count, pool.count());
    }

    function testFailDeploySamePoolTwice() public {
        factory.deployPool(collateral, quote, count);
        factory.deployPool(collateral, quote, count);
    }

    function testPredictDeployedAddress() public {
        address predictedAddress = factory.calculatePoolAddress(
            collateral,
            quote,
            count
        );

        assert(
            false == factory.isPoolDeployed(ERC20PerpPool(predictedAddress))
        );

        ERC20PerpPool pool = factory.deployPool(collateral, quote, count);

        assertEq(address(pool), predictedAddress);
        assert(true == factory.isPoolDeployed(ERC20PerpPool(predictedAddress)));
    }
}
