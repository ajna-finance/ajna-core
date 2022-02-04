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

    function setUp() public {
        factory = new ERC20PoolFactory();
        collateral = new ERC20("Collateral", "C");
        quote = new ERC20("Quote", "Q");
    }

    function testDeploy() public {
        ERC20PerpPool pool = factory.deployPool(collateral, quote);

        assertEq(address(collateral), address(pool.collateralToken()));
        assertEq(address(quote), address(pool.quoteToken()));
    }

    function testFailDeploySamePoolTwice() public {
        factory.deployPool(collateral, quote);
        factory.deployPool(collateral, quote);
    }

    function testPredictDeployedAddress() public {
        address predictedAddress = factory.calculatePoolAddress(collateral, quote);

        assert(false == factory.isPoolDeployed(ERC20PerpPool(predictedAddress)));

        ERC20PerpPool pool = factory.deployPool(collateral, quote);

        assertEq(address(pool), predictedAddress);
        assert(true == factory.isPoolDeployed(ERC20PerpPool(predictedAddress)));
    }
}
