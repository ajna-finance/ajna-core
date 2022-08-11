// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledInterestRateTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();
        _lender1    = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 10_000 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 10_000 * 1e18);
        _borrower.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _borrower2.approveToken(_collateral, address(_pool), 10_000 * 1e18);
        _borrower2.approveToken(_quote,      address(_pool), 200_000 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    function testScaledPoolInterestRateIncreaseDecrease() external {
        assertEq(_pool.interestRate(),       0.05 * 1e18);
        assertEq(_pool.interestRateUpdate(), 0);

        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 2551);
        _lender.addQuoteToken(_pool, 20_000 * 1e18, 2552);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 3900);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 4200);
        skip(864000);

        assertEq(_pool.interestRate(),       0.05 * 1e18);
        assertEq(_pool.interestRateUpdate(), 0);

        _borrower.pledgeCollateral(_pool, 100 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 46_000 * 1e18, 4300, address(0), address(0));

        assertEq(_pool.htp(), 460.442307692307692520 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.treeSum(),      110_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 46_044.230769230769252000 * 1e18);
        assertEq(_pool.lenderDebt(),   46_000 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // repay entire loan
        _quote.mint(address(_borrower), 200 * 1e18);
        _borrower.repay(_pool, 46_200 * 1e18, address(0), address(0));

        // enforce rate update - decrease
        skip(864000);
        _lender.addQuoteToken(_pool, 100 * 1e18, 5);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),      110_162.490615980593600000 * 1e18);
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
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 2552);
        _lender.addQuoteToken(_pool, 10_000 * 1e18, 4200);
        skip(3600);

        // draw debt
        _borrower.pledgeCollateral(_pool, 50 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 4300, address(0), address(0));
        assertEq(_pool.inflatorSnapshot(), 1.0 * 1e18);
        assertEq(_pool.pendingInflator(), 1.000005707778845707 * 1e18);
        vm.warp(block.timestamp+3600);

        // ensure pendingInflator increases as time passes
        assertEq(_pool.inflatorSnapshot(), 1.0 * 1e18);
        assertEq(_pool.pendingInflator(), 1.000011415590270154 * 1e18);
    }

    // TODO: add test related to pool utilization changes

}
