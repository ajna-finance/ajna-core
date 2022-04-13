// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, CollateralTokenWith6Decimals, QuoteToken, QuoteTokenWith6Decimals} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolPrecisionTest is DSTestPlus {
    uint256 internal constant BUCKET_PRICE = 2000.221618840727700609 * 1e18;

    ERC20Pool internal pool;
    uint256 internal quotePoolPrecision = 10**45;
    uint256 internal collateralPoolPrecision = 10**27;
    CollateralToken internal collateral;
    uint256 internal collateralPrecision;
    QuoteToken internal quote;
    uint256 internal quotePrecision;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;
    UserWithCollateral internal bidder;

    function setUp() public virtual {
        collateralPrecision = 10**18;
        quotePrecision = 10**18;

        collateral = new CollateralToken();
        quote = new QuoteToken();

        init();
    }

    function init() internal {
        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * collateralPrecision);
        borrower.approveToken(
            collateral,
            address(pool),
            100 * collateralPrecision
        );

        bidder = new UserWithCollateral();
        collateral.mint(address(bidder), 100 * collateralPrecision);
        bidder.approveToken(
            collateral,
            address(pool),
            100 * collateralPrecision
        );

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * quotePrecision);
        lender.approveToken(quote, address(pool), 200_000 * quotePrecision);
        borrower.approveToken(quote, address(pool), 10_000 * quotePrecision);
    }

    function testPrecision() public virtual {
        assertEq(
            collateral.balanceOf(address(borrower)),
            100 * collateralPrecision
        );
        assertEq(quote.balanceOf(address(lender)), 200_000 * quotePrecision);

        // deposit 20_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(lender), address(pool), 20_000 * quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(
            address(lender),
            BUCKET_PRICE,
            20_000 * quotePoolPrecision,
            0
        );
        lender.addQuoteToken(
            pool,
            address(lender),
            20_000 * 1e18,
            BUCKET_PRICE
        );
        // check balances
        assertEq(pool.totalQuoteToken(), 20_000 * quotePoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 20_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 180_000 * quotePrecision);

        // remove 10_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 10_000 * quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(
            address(lender),
            BUCKET_PRICE,
            10_000 * quotePoolPrecision,
            0
        );
        lender.removeQuoteToken(
            pool,
            address(lender),
            10_000 * 1e18,
            BUCKET_PRICE
        );
        // check balances
        assertEq(pool.totalQuoteToken(), 10_000 * quotePoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 10_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);

        // borrow 10_000 quote token with 6 decimal precision
        borrower.addCollateral(pool, 100 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(borrower),
            10_000 * quotePrecision
        );
        vm.expectEmit(true, true, false, true);
        emit Borrow(
            address(borrower),
            2_000.221618840727700609 * 1e18,
            10_000 * quotePoolPrecision
        );
        borrower.borrow(pool, 10_000 * 1e18, 2_000 * 1e18);
        // check balances
        assertEq(pool.totalQuoteToken(), 0);
        assertEq(pool.totalDebt(), 10_000 * quotePoolPrecision);
        assertEq(pool.totalCollateral(), 100 * collateralPoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 0);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);
        assertEq(quote.balanceOf(address(borrower)), 10_000 * quotePrecision);
        assertEq(
            collateral.balanceOf(address(pool)),
            100 * collateralPrecision
        );
        assertEq(collateral.balanceOf(address(borrower)), 0);

        // repay 5_000 quote token with 6 decimal precision
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(borrower), address(pool), 5_000 * quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Repay(
            address(borrower),
            2_000.221618840727700609 * 1e18,
            5_000 * quotePoolPrecision
        );
        borrower.repay(pool, 5_000 * 1e18);
        // check balances
        assertEq(pool.totalQuoteToken(), 5_000 * quotePoolPrecision);
        assertEq(pool.totalDebt(), 5_000 * quotePoolPrecision);
        assertEq(pool.totalCollateral(), 100 * collateralPoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 5_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);
        assertEq(quote.balanceOf(address(borrower)), 5_000 * quotePrecision);
        assertEq(
            collateral.balanceOf(address(pool)),
            100 * collateralPrecision
        );
        assertEq(collateral.balanceOf(address(borrower)), 0);

        // purchase bid of 1_000 quote tokens
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(bidder), 1_000 * quotePrecision);
        vm.expectEmit(true, true, false, true);
        emit Purchase(
            address(bidder),
            BUCKET_PRICE,
            1_000 * quotePoolPrecision,
            0.499944601428501671562842199 * 10**27
        );
        bidder.purchaseBid(pool, 1_000 * 1e18, BUCKET_PRICE);
        // check balances
        assertEq(pool.totalQuoteToken(), 4_000 * quotePoolPrecision);
        assertEq(pool.totalDebt(), 5_000 * quotePoolPrecision);
        assertEq(pool.totalCollateral(), 100 * collateralPoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 4_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);
        assertEq(quote.balanceOf(address(borrower)), 5_000 * quotePrecision);
        assertEq(quote.balanceOf(address(bidder)), 1_000 * quotePrecision);

        assertCollateralBalancesAfterBid();

        // claim collateral
        assertClaimCollateral();
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(lender),
            BUCKET_PRICE,
            0.499944601428501671000000000 * 10**27,
            999.999999999999998874190864576 * 10**27
        );
        lender.claimCollateral(
            pool,
            address(lender),
            0.499944601428501671 * 1e18,
            BUCKET_PRICE
        );
        // // check balances
        assertEq(pool.totalQuoteToken(), 4_000 * quotePoolPrecision);
        assertEq(pool.totalDebt(), 5_000 * quotePoolPrecision);
        assertEq(pool.totalCollateral(), 100 * collateralPoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 4_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);
        assertEq(quote.balanceOf(address(borrower)), 5_000 * quotePrecision);
        assertEq(quote.balanceOf(address(bidder)), 1_000 * quotePrecision);

        assertCollateralBalancesAfterClaim();

        // remove collateral
        assertRemoveCollateral();
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateral(
            address(borrower),
            0.499944601428501671000000000 * 10**27
        );
        borrower.removeCollateral(pool, 0.499944601428501671 * 1e18);
        assertEq(
            pool.totalCollateral(),
            99.500055398571498329000000000 * 10**27
        );
        // check balances
        assertEq(pool.totalQuoteToken(), 4_000 * quotePoolPrecision);
        assertEq(pool.totalDebt(), 5_000 * quotePoolPrecision);
        assertEq(quote.balanceOf(address(pool)), 4_000 * quotePrecision);
        assertEq(quote.balanceOf(address(lender)), 190_000 * quotePrecision);
        assertEq(quote.balanceOf(address(borrower)), 5_000 * quotePrecision);
        assertEq(quote.balanceOf(address(bidder)), 1_000 * quotePrecision);

        assertCollateralBalancesAfterRemove();
    }

    function assertClaimCollateral() public virtual {
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(lender),
            0.499944601428501671 * 10**18
        );
    }

    function assertRemoveCollateral() public virtual {
        vm.expectEmit(true, true, false, true);
        emit Transfer(
            address(pool),
            address(borrower),
            0.499944601428501671 * 10**18
        );
    }

    function assertCollateralBalancesAfterBid() public virtual {
        assertEq(
            collateral.balanceOf(address(pool)),
            100.499944601428501671 * 10**18
        );
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.500055398571498329 * 10**18
        );
    }

    function assertCollateralBalancesAfterClaim() public virtual {
        assertEq(
            collateral.balanceOf(address(pool)),
            100 * collateralPrecision
        );
        assertEq(
            collateral.balanceOf(address(lender)),
            0.499944601428501671 * 10**18
        );
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.500055398571498329 * 10**18
        );
    }

    function assertCollateralBalancesAfterRemove() public virtual {
        assertEq(
            collateral.balanceOf(address(pool)),
            99.500055398571498329 * 10**18
        );
        assertEq(
            collateral.balanceOf(address(lender)),
            0.499944601428501671 * 10**18
        );
        assertEq(
            collateral.balanceOf(address(borrower)),
            0.499944601428501671 * 10**18
        );
        assertEq(
            collateral.balanceOf(address(bidder)),
            99.500055398571498329 * 10**18
        );
    }
}

contract QuoteTokenWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {
    function setUp() public override {
        collateralPrecision = 10**18;
        quotePrecision = 10**6;

        collateral = new CollateralToken();
        quote = new QuoteTokenWith6Decimals();

        init();
    }
}

contract CollateralWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {
    function setUp() public override {
        collateralPrecision = 10**6;
        quotePrecision = 10**18;

        collateral = new CollateralTokenWith6Decimals();
        quote = new QuoteToken();

        init();
    }

    function assertClaimCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 0.499944 * 10**6);
    }

    function assertRemoveCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 0.499944 * 10**6);
    }

    function assertCollateralBalancesAfterBid() public override {
        assertEq(collateral.balanceOf(address(pool)), 100.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterClaim() public override {
        assertEq(
            collateral.balanceOf(address(pool)),
            100 * collateralPrecision
        );
        assertEq(collateral.balanceOf(address(lender)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterRemove() public override {
        assertEq(collateral.balanceOf(address(pool)), 99.500056 * 10**6);
        assertEq(collateral.balanceOf(address(lender)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }
}

contract CollateralAndQuoteWith6DecimalPrecisionTest is ERC20PoolPrecisionTest {
    function setUp() public override {
        collateralPrecision = 10**6;
        quotePrecision = 10**6;

        collateral = new CollateralTokenWith6Decimals();
        quote = new QuoteTokenWith6Decimals();

        init();
    }

    function assertClaimCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(lender), 0.499944 * 10**6);
    }

    function assertRemoveCollateral() public override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pool), address(borrower), 0.499944 * 10**6);
    }

    function assertCollateralBalancesAfterBid() public override {
        assertEq(collateral.balanceOf(address(pool)), 100.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterClaim() public override {
        assertEq(
            collateral.balanceOf(address(pool)),
            100 * collateralPrecision
        );
        assertEq(collateral.balanceOf(address(lender)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }

    function assertCollateralBalancesAfterRemove() public override {
        assertEq(collateral.balanceOf(address(pool)), 99.500056 * 10**6);
        assertEq(collateral.balanceOf(address(lender)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(borrower)), 0.499944 * 10**6);
        assertEq(collateral.balanceOf(address(bidder)), 99.500056 * 10**6);
    }
}
