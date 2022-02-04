// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@ds-test/test.sol";
import {stdCheats} from "@std/stdlib.sol";
import "@std/Vm.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PerpPool} from "../ERC20PerpPool.sol";

contract UserWithCollateral {
    function approveAndDepositTokenAsCollateral(IERC20 token, ERC20PerpPool pool, uint256 amount) public {
        token.approve(address(pool), amount);
        pool.depositCollateral(amount);
    }
}

contract CollateralToken is ERC20 {
    constructor(address alice, address bob) ERC20("Collateral", "C") {
        _mint(alice, 100 ether);
        _mint(bob, 100 ether);
    }
}

contract ERC20PerpPoolTest is DSTest, stdCheats {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    ERC20PerpPool internal pool;
    ERC20 internal collateral;
    ERC20 internal quote;

    UserWithCollateral internal alice;
    UserWithCollateral internal bob;

    function setUp() public {
        alice = new UserWithCollateral();
        bob = new UserWithCollateral();
        collateral = new CollateralToken(address(alice), address(bob));
        
        quote = new ERC20("Quote", "Q");

        pool = new ERC20PerpPool(collateral, quote);
    }

    function testDeploy() public {
        assertEq(address(collateral), address(pool.collateralToken()));
        assertEq(address(quote), address(pool.quoteToken()));

        // TODO: Should them be also parameters to constructor
        assertEq(1 ether, pool.borrowerInflator());
        assertEq(0.05 ether, pool.previousRate());

        assertEq(block.timestamp, pool.lastBorrowerInflatorUpdate());
        assertEq(block.timestamp, pool.previousRateUpdate());
    }

    function testDepositCollateral() public {
        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 ether);

        uint256 aliceCollateral = pool.collateralBalances(address(alice));

        assertEq(aliceCollateral, 50 ether);

        // we're at the same block, borrower inflator should be same
        assertEq(pool.borrowerInflator(), 1 ether);
        assertEq(pool.borrowerInflatorPending(), 1 ether);
        
        vm.warp(block.timestamp + 1 minutes);

        // blocks mined but no tx to update borrower inflator
        assertEq(pool.borrowerInflator(), 1 ether);
        assertGt(pool.borrowerInflatorPending(), 1000000095000000000);

        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 ether);
        // borrower inflator updated with new deposit tx
        assertGt(pool.borrowerInflator(), 1 ether);
    }

}