// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { DSTestPlus }                                    from "./utils/DSTestPlus.sol";
import { CollateralToken, CollateralTokenWith6Decimals } from "./utils/Tokens.sol";
import { QuoteToken, QuoteTokenWith6Decimals }           from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken }        from "./utils/Users.sol";

contract ERC20PoolPrecisionTest is DSTestPlus {
    uint256 internal constant BUCKET_PRICE = 2000.221618840727700609 * 1e18;

    uint256 internal _quotePoolPrecision      = 10**45;
    uint256 internal _collateralPoolPrecision = 10**27;
    uint256 internal _collateralPrecision;
    uint256 internal _quotePrecision;

    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithQuoteToken internal _lender;
    UserWithCollateral internal _bidder;

    function setUp() external virtual {
        _collateralPrecision = 10**18;
        _quotePrecision      = 10**18;
        _collateral          = new CollateralToken();
        _quote               = new QuoteToken();

        init();
    }

    function init() internal {
        _pool     = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _borrower = new UserWithCollateral();
        _bidder   = new UserWithCollateral();
        _lender   = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * _collateralPrecision);
        _collateral.mint(address(_bidder), 100 * _collateralPrecision);
        _quote.mint(address(_lender), 200_000 * _quotePrecision);

        _borrower.approveToken(_collateral, address(_pool), 100 * _collateralPrecision);
        _bidder.approveToken(_collateral, address(_pool), 100 * _collateralPrecision);
        _lender.approveToken(_quote, address(_pool), 200_000 * _quotePrecision);
        _borrower.approveToken(_quote, address(_pool), 10_000 * _quotePrecision);
    }

    // @notice: 1 lender and 1 borrower tests adding quote token, removing quote token borrowing
    // @notice: removing quote token, borrowing and repaying
    // @notice: with 10^45 and 10^27 precision
    function testPrecision() external virtual {
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * _collateralPrecision);
        assertEq(_quote.balanceOf(address(_lender)),        200_000 * _quotePrecision);

        // deposit 20_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_lender), address(_pool), 20_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(address(_lender), BUCKET_PRICE, 20_000 * _quotePoolPrecision, 0);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, BUCKET_PRICE);

        // check balances
        assertEq(_pool.totalQuoteToken(),            20_000 * _quotePoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   20_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 180_000 * _quotePrecision);

        // remove 10_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 10_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(address(_lender), BUCKET_PRICE, 10_000 * _quotePoolPrecision, 0);
        _lender.removeQuoteToken(_pool, address(_lender), 10_000 * 1e18, BUCKET_PRICE);

        // check balances
        assertEq(_pool.totalQuoteToken(),            10_000 * _quotePoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),   10_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)), 190_000 * _quotePrecision);

        // borrow 10_000 quote token with 6 decimal precision
        _borrower.addCollateral(_pool, 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 10_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p2000, 10_000 * _quotePoolPrecision);
        _borrower.borrow(_pool, 10_000 * 1e18, 2_000 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                   0);
        assertEq(_pool.totalDebt(),                         10_000 * _quotePoolPrecision);
        assertEq(_pool.totalCollateral(),                   100 * _collateralPoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),          0);
        assertEq(_quote.balanceOf(address(_lender)),        190_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)),      10_000 * _quotePrecision);
        assertEq(_collateral.balanceOf(address(_pool)),     100 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);

        // repay 5_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 5_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Repay(address(_borrower), _p2000, 5_000 * _quotePoolPrecision);
        _borrower.repay(_pool, 5_000 * 1e18);

        // check balances
        assertEq(_pool.totalQuoteToken(),                   5_000 * _quotePoolPrecision);
        assertEq(_pool.totalDebt(),                         5_000 * _quotePoolPrecision);
        assertEq(_pool.totalCollateral(),                   100 * _collateralPoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),          5_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)),        190_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)),      5_000 * _quotePrecision);
        assertEq(_collateral.balanceOf(address(_pool)),     100 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);

        // purchase bid of 1_000 quote tokens
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_bidder), 1_000 * _quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(_bidder),
            BUCKET_PRICE,
            1_000 * _quotePoolPrecision,
            0.499944601428501671562842199 * 10**27
        );
        _bidder.purchaseBid(_pool, 1_000 * 1e18, BUCKET_PRICE);

        // check balances
        assertEq(_pool.totalQuoteToken(),              4_000 * _quotePoolPrecision);
        assertEq(_pool.totalDebt(),                    5_000 * _quotePoolPrecision);
        assertEq(_pool.totalCollateral(),              100 * _collateralPoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),     4_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)),   190_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 5_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_bidder)),   1_000 * _quotePrecision);

        assertCollateralBalancesAfterBid();

        // claim collateral
        assertClaimCollateral();
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(_lender),
            BUCKET_PRICE,
            0.499944601428501671000000000 * 10**27,
            999.999999999999998874190864576 * 10**27
        );
        _lender.claimCollateral(_pool, address(_lender), 0.499944601428501671 * 1e18, BUCKET_PRICE);

        // check balances
        assertEq(_pool.totalQuoteToken(),              4_000 * _quotePoolPrecision);
        assertEq(_pool.totalDebt(),                    5_000 * _quotePoolPrecision);
        assertEq(_pool.totalCollateral(),              100 * _collateralPoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),     4_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)),   190_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 5_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_bidder)),   1_000 * _quotePrecision);

        assertCollateralBalancesAfterClaim();

        // remove collateral
        assertRemoveCollateral();
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateral(address(_borrower), 0.499944601428501671000000000 * 10**27);
        _borrower.removeCollateral(_pool, 0.499944601428501671 * 1e18);
        assertEq(_pool.totalCollateral(), 99.500055398571498329 * 10**27);

        // check balances
        assertEq(_pool.totalQuoteToken(),              4_000 * _quotePoolPrecision);
        assertEq(_pool.totalDebt(),                    5_000 * _quotePoolPrecision);
        assertEq(_quote.balanceOf(address(_pool)),     4_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_lender)),   190_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_borrower)), 5_000 * _quotePrecision);
        assertEq(_quote.balanceOf(address(_bidder)),   1_000 * _quotePrecision);

        assertCollateralBalancesAfterRemove();
    }

    function assertClaimCollateral() public virtual {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 0.499944601428501671 * 10**18);
    }

    function assertRemoveCollateral() public virtual {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 0.499944601428501671 * 10**18);
    }

    function assertCollateralBalancesAfterBid() public virtual {
        assertEq(_collateral.balanceOf(address(_pool)),     100.499944601428501671 * 10**18);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500055398571498329 * 10**18);
    }

    function assertCollateralBalancesAfterClaim() public virtual {
        assertEq(_collateral.balanceOf(address(_pool)),     100 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944601428501671 * 10**18);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500055398571498329 * 10**18);
    }

    function assertCollateralBalancesAfterRemove() public virtual {
        assertEq(_collateral.balanceOf(address(_pool)),     99.500055398571498329 * 10**18);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944601428501671 * 10**18);
        assertEq(_collateral.balanceOf(address(_borrower)), 0.499944601428501671 * 10**18);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500055398571498329 * 10**18);
    }

}

contract QuoteTokenWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {

    function setUp() external override {
        _collateralPrecision = 10**18;
        _quotePrecision      = 10**6;
        _collateral          = new CollateralToken();
        _quote               = new QuoteTokenWith6Decimals();

        init();
    }

}

contract CollateralWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {

    function setUp() external override {
        _collateralPrecision = 10**6;
        _quotePrecision      = 10**18;
        _collateral          = new CollateralTokenWith6Decimals();
        _quote               = new QuoteToken();

        init();
    }

    function assertClaimCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 0.499944 * 10**6);
    }

    function assertRemoveCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 0.499944 * 10**6);
    }

    function assertCollateralBalancesAfterBid() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     100.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterClaim() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     100 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterRemove() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     99.500056 * 10**6);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

}

contract CollateralAndQuoteWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {
    function setUp() external override {
        _collateralPrecision = 10**6;
        _quotePrecision      = 10**6;
        _collateral          = new CollateralTokenWith6Decimals();
        _quote               = new QuoteTokenWith6Decimals();

        init();
    }

    function assertClaimCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 0.499944 * 10**6);
    }

    function assertRemoveCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 0.499944 * 10**6);
    }

    function assertCollateralBalancesAfterBid() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     100.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterClaim() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     100 * _collateralPrecision);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterRemove() public override {
        assertEq(_collateral.balanceOf(address(_pool)),     99.500056 * 10**6);
        assertEq(_collateral.balanceOf(address(_lender)),   0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_borrower)), 0.499944 * 10**6);
        assertEq(_collateral.balanceOf(address(_bidder)),   99.500056 * 10**6);
    }

}
