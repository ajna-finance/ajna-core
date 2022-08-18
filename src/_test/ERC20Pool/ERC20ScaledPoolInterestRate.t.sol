// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                  from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC20ScaledInterestRateTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _pool        = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("_lender1");

        deal(address(_collateral), _borrower,  10_000 * 1e18);
        deal(address(_collateral), _borrower2, 200 * 1e18);

        deal(address(_quote), _lender,  200_000 * 1e18);
        deal(address(_quote), _lender1, 200_000 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 10_000 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 10_000 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender1);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    function testScaledPoolInterestRateIncreaseDecrease() external {
        assertEq(_pool.interestRate(),       0.05 * 1e18);
        assertEq(_pool.interestRateUpdate(), 0);

        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(20_000 * 1e18, 2551);
        _pool.addQuoteToken(20_000 * 1e18, 2552);
        _pool.addQuoteToken(50_000 * 1e18, 3900);
        _pool.addQuoteToken(10_000 * 1e18, 4200);
        skip(864000);

        assertEq(_pool.interestRate(),       0.05 * 1e18);
        assertEq(_pool.interestRateUpdate(), 0);

        changePrank(_borrower);
        _pool.pledgeCollateral(100 * 1e18, address(0), address(0));
        _pool.borrow(46_000 * 1e18, 4300, address(0), address(0));

        assertEq(_pool.htp(), 460.442307692307692520 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.poolSize(),     110_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 46_044.230769230769252000 * 1e18);
        assertEq(_pool.lenderDebt(),   46_000 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 200 * 1e18);
        _pool.repay(46_200 * 1e18, address(0), address(0));

        skip(864000);

        // enforce rate update - decrease
        changePrank(_lender);
        _pool.addQuoteToken(100 * 1e18, 5);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.poolSize(),     110_162.490615980593600000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);
        assertEq(_pool.lenderDebt(),   0);

        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(col,         100 * 1e18);
        assertEq(inflator,    1.001507985182860621 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18); // FIXME here it should decrease
        assertEq(_pool.interestRateUpdate(), 864000);
    }

    function testPendingInflator() external {
        // add liquidity
        changePrank(_lender);
        _pool.addQuoteToken(10_000 * 1e18, 2550);
        _pool.addQuoteToken(10_000 * 1e18, 2552);
        _pool.addQuoteToken(10_000 * 1e18, 4200);
        skip(3600);

        // draw debt
        changePrank(_borrower);
        _pool.pledgeCollateral(50 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 4300, address(0), address(0));
        assertEq(_pool.inflatorSnapshot(), 1.0 * 1e18);
        assertEq(_pool.pendingInflator(), 1.000005707778845707 * 1e18);
        vm.warp(block.timestamp+3600);

        // ensure pendingInflator increases as time passes
        assertEq(_pool.inflatorSnapshot(), 1.0 * 1e18);
        assertEq(_pool.pendingInflator(), 1.000011415590270154 * 1e18);
    }

    // TODO: add test related to pool utilization changes

}
