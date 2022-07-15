// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateralInScaledPool, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";

contract ScaledInterestRateTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateralInScaledPool internal _borrower;
    UserWithCollateralInScaledPool internal _borrower2;
    UserWithQuoteTokenInScaledPool internal _lender;
    UserWithQuoteTokenInScaledPool internal _lender1;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ScaledPool(_poolAddress);

        _borrower   = new UserWithCollateralInScaledPool();
        _borrower2  = new UserWithCollateralInScaledPool();
        _lender     = new UserWithQuoteTokenInScaledPool();
        _lender1    = new UserWithQuoteTokenInScaledPool();

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

        _borrower.addCollateral(_pool, 100 * 1e18, address(0), address(0), 1);
        _borrower.borrow(_pool, 46_000 * 1e18, 4300, address(0), address(0), 1);

        assertEq(_pool.htp(), 460.442307692307692520 * 1e18);
        assertEq(_pool.lup(), 2_981.007422784467321543 * 1e18);

        assertEq(_pool.treeSum(),      110_000 * 1e18);
        assertEq(_pool.borrowerDebt(), 46_044.230769230769252000 * 1e18);
        assertEq(_pool.lenderDebt(),   46_000 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18);
        assertEq(_pool.interestRateUpdate(), 864000);

        // repay entire loan
        _quote.mint(address(_borrower), 200 * 1e18);
        _borrower.repay(_pool, 46_200 * 1e18, address(0), address(0), 1);

        // enforce rate update - decrease
        skip(864000);
        _lender.addQuoteToken(_pool, 100 * 1e18, 5);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        assertEq(_pool.treeSum(),      110_162.490615926716800000 * 1e18);
        assertEq(_pool.borrowerDebt(), 0);
        assertEq(_pool.lenderDebt(),   0);

        (uint256 debt, uint256 col, uint256 inflator) = _pool.borrowerInfo(address(_borrower));
        assertEq(debt,     0);
        assertEq(col,      100 * 1e18);
        assertEq(inflator, 1.001507985181560500 * 1e18);

        assertEq(_pool.interestRate(),       0.055 * 1e18); // FIXME here it should decrease
        assertEq(_pool.interestRateUpdate(), 864000);
    }

}
