// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import "@ds-test/test.sol";
import {stdCheats} from "@std/stdlib.sol";
import "@std/Vm.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20PerpPool} from "../ERC20PerpPool.sol";

contract UserWithCollateral {
    function approveAndDepositTokenAsCollateral(
        IERC20 token,
        ERC20PerpPool pool,
        uint256 amount
    ) public {
        token.approve(address(pool), amount);
        pool.depositCollateral(amount);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }

    function depositCollteral(ERC20PerpPool pool, uint256 amount) public {
        pool.depositCollateral(amount);
    }

    function borrow(ERC20PerpPool pool, uint256 amount) public {
        pool.borrow(amount);
    }
}

contract UserWithQuoteToken {
    function depositQuoteToken(
        ERC20PerpPool pool,
        uint256 amount,
        uint256 price
    ) public {
        pool.depositQuoteToken(amount, price);
    }

    function approveToken(
        IERC20 token,
        address spender,
        uint256 amount
    ) public {
        token.approve(spender, amount);
    }
}

contract CollateralToken is ERC20 {
    constructor() ERC20("Collateral", "C") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract QuoteToken is ERC20 {
    constructor() ERC20("Quote", "Q") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract ERC20PerpPoolTest is DSTest, stdCheats {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    ERC20PerpPool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal alice;
    UserWithCollateral internal bob;

    function setUp() public {
        alice = new UserWithCollateral();
        bob = new UserWithCollateral();
        collateral = new CollateralToken();

        collateral.mint(address(alice), 100 * 1e18);
        collateral.mint(address(bob), 100 * 1e18);

        quote = new QuoteToken();

        pool = new ERC20PerpPool(collateral, quote);
    }

    function testDeploy() public {
        assertEq(address(collateral), address(pool.collateralToken()));
        assertEq(address(quote), address(pool.quoteToken()));

        // TODO: Should them be also parameters to constructor
        assertEq(1 * 1e18, pool.borrowerInflator());
        assertEq(0.05 * 1e18, pool.previousRate());

        assertEq(block.timestamp, pool.lastBorrowerInflatorUpdate());
        assertEq(block.timestamp, pool.previousRateUpdate());
    }

    function testDepositCollateral() public {
        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 * 1e18);

        uint256 aliceCollateral = pool.collateralBalances(address(alice));

        assertEq(aliceCollateral, 50 * 1e18);

        // we're at the same block, borrower inflator should be same
        assertEq(pool.borrowerInflator(), 1 * 1e18);
        assertEq(pool.borrowerInflatorPending(), 1 * 1e18);

        vm.warp(block.timestamp + 1 minutes);

        // blocks mined but no tx to update borrower inflator
        assertEq(pool.borrowerInflator(), 1 * 1e18);
        assertGt(pool.borrowerInflatorPending(), 1000000095000000000);

        alice.approveAndDepositTokenAsCollateral(collateral, pool, 50 * 1e18);
        // borrower inflator updated with new deposit tx
        assertGt(pool.borrowerInflator(), 1 * 1e18);
    }
}

contract ERC20PerpPoolPerformanceTest is DSTest, stdCheats {
    Vm public constant vm = Vm(HEVM_ADDRESS);

    ERC20PerpPool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral[] internal borrowers;
    UserWithQuoteToken[] internal lenders;

    uint256 internal constant MAX_USERS = 100;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        pool = new ERC20PerpPool(collateral, quote);

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithCollateral user = new UserWithCollateral();
            collateral.mint(address(user), 100_000 * 1e18);
            user.approveToken(collateral, address(pool), type(uint256).max);

            assertEq(
                collateral.allowance(address(user), address(pool)),
                type(uint256).max
            );
            borrowers.push(user);
        }

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithQuoteToken user = new UserWithQuoteToken();
            quote.mint(address(user), 100_000 * 1e18);
            user.approveToken(quote, address(pool), type(uint256).max);

            assertEq(
                quote.allowance(address(user), address(pool)),
                type(uint256).max
            );
            lenders.push(user);
        }
    }

    function test_5_borrowers() public {
        uint256 bucketPrice = pool.indexToPrice(7);

        _depositQuoteToken(lenders[0], 10_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[1], 5_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[2], 7_000 * 1e18, bucketPrice);
        _depositQuoteToken(lenders[3], 4_000 * 1e18, bucketPrice);

        (uint256 onDeposit, , , , ) = pool.bucketInfoForAddress(
            7,
            address(lenders[0])
        );

        assertEq(onDeposit, 26_000 * 1e18);

        _depositCollateral(borrowers[0], 10 * 1e18);
        _depositCollateral(borrowers[1], 3 * 1e18);
        _depositCollateral(borrowers[2], 5 * 1e18);
        _depositCollateral(borrowers[3], 2 * 1e18);
        _depositCollateral(borrowers[4], 4 * 1e18);

        _borrow(borrowers[0], 10_000 * 1e18);
        _borrow(borrowers[1], 1_000 * 1e18);
        _borrow(borrowers[2], 2_000 * 1e18);
        _borrow(borrowers[3], 1_000 * 1e18);
        _borrow(borrowers[4], 7_000 * 1e18);
    }

    function _depositQuoteToken(
        UserWithQuoteToken lender,
        uint256 amount,
        uint256 price
    ) internal {
        uint256 balance = quote.balanceOf(address(lender));
        assertGt(balance, amount);

        lender.depositQuoteToken(pool, amount, price);

        assertEq(balance - quote.balanceOf(address(lender)), amount);
        assertEq(pool.quoteBalances(address(lender)), amount);
    }

    function _depositCollateral(UserWithCollateral borrower, uint256 amount)
        internal
    {
        uint256 balance = collateral.balanceOf(address(borrower));
        assertGt(balance, amount);

        borrower.depositCollteral(pool, amount);

        assertEq(balance - collateral.balanceOf(address(borrower)), amount);
    }

    function _borrow(UserWithCollateral borrower, uint256 amount) internal {
        borrower.borrow(pool, amount);

        assertEq(quote.balanceOf(address(borrower)), amount);
    }
}
