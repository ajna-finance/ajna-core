// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { Buckets } from "../base/Buckets.sol";

import { IPool } from "../interfaces/IPool.sol";

import { Maths }   from "../libraries/Maths.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

contract ERC20PoolCollateralTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;
    UserWithCollateral internal _bidder;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);  

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _bidder     = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();
        _lender1    = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 200 * 1e18);
        _collateral.mint(address(_bidder), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 200 * 1e18);
        _bidder.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
    With 1 lender and 1 borrower test adding collateral.
    1) repay and removeCollateral
    2) borrower reverts from attempt to withdraw collateral when all collateral is encumbered
    */
    function testAddRemoveCollateral() external {
        // should revert if trying to remove collateral when no available
        vm.expectRevert(
            abi.encodeWithSelector(IPool.AmountExceedsAvailableCollateral.selector, 0)
        );
        _borrower.removeCollateral(_pool, 10 * 1e18);
        // lender deposits 20_000 DAI in 5 buckets each
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p5007);

        // check initial pool state
        uint256 poolEncumbered    = _pool.getEncumberedCollateral(_pool.totalDebt());
        uint256 collateralization = _pool.getPoolCollateralization();
        uint256 targetUtilization = _pool.getPoolTargetUtilization();
        uint256 actualUtilization = _pool.getPoolActualUtilization();
        assertEq(poolEncumbered,    0);
        assertEq(collateralization, Maths.ONE_WAD);

        // test deposit collateral
        assertEq(_collateral.balanceOf(address(_borrower)), 100 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),     0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 70 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_borrower), 70 * 1e18);
        _borrower.addCollateral(_pool, 70 * 1e18);

        // check balances
        assertEq(_collateral.balanceOf(address(_borrower)), 30 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),     70 * 1e18);
        assertEq(_pool.totalCollateral(),                   70 * 1e18);

        // check borrower
        (, , uint256 deposited, uint256 borrowerEncumbered, uint256 borrowerCollateralization, ,)
            = _pool.getBorrowerInfo(address(_borrower));
        assertEq(deposited,                 70 * 1e18);
        assertEq(borrowerEncumbered,        0);
        assertEq(borrowerCollateralization, Maths.ONE_WAD);

        // get loan of 20_000 DAI, recheck borrower
        _borrower.borrow(_pool, 20_000 * 1e18, 2500 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(deposited,                        70 * 1e18);
        assertEq(borrowerEncumbered,               3.993893827662208276 * 1e18);
        assertEq(borrowerCollateralization,        17.526755347168030152 * 1e18);
        assertEq(_pool.getPoolCollateralization(), borrowerCollateralization);

        // check pool state after loan
        poolEncumbered    = _pool.getEncumberedCollateral(_pool.totalDebt());
        targetUtilization = _pool.getPoolTargetUtilization();
        actualUtilization = _pool.getPoolActualUtilization();
        assertEq(poolEncumbered,    borrowerEncumbered);
        assertGt(actualUtilization, targetUtilization);

        // add some collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_borrower), address(_pool), 30 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(address(_borrower), 30 * 1e18);
        _borrower.addCollateral(_pool, 30 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(deposited,          100 * 1e18);
        assertEq(borrowerEncumbered, 3.993893827662208276 * 1e18);
        // ensure collateralization increased and target utilization decreased
        assertLt(collateralization, _pool.getPoolCollateralization());
        assertGt(targetUtilization, _pool.getPoolTargetUtilization());
        collateralization = _pool.getPoolCollateralization();
        targetUtilization = _pool.getPoolTargetUtilization();

        // should revert if trying to remove all collateral deposited
        vm.expectRevert(
            abi.encodeWithSelector(
                IPool.AmountExceedsAvailableCollateral.selector,
                99.999999996006106172 * 1e18
            )
        );
        _borrower.removeCollateral(_pool, 100 * 1e18);

        // remove some collateral
        _borrower.removeCollateral(_pool, 20 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(deposited,                 80 * 1e18);
        assertEq(borrowerEncumbered,        3.993893827662208276 * 1e18);
        assertEq(borrowerCollateralization, 20.030577539620605889 * 1e18);

        assertEq(_pool.getPoolCollateralization(), borrowerCollateralization);
        // ensure collateralization decreased and target utilization increased
        assertGt(collateralization, _pool.getPoolCollateralization());
        assertLt(targetUtilization, _pool.getPoolTargetUtilization());

        collateralization = _pool.getPoolCollateralization();
        actualUtilization = _pool.getPoolActualUtilization();
        targetUtilization = _pool.getPoolTargetUtilization();

        // borrower repays part of the loan
        _quote.mint(address(_borrower), 5_000 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 5_000 * 1e18);
        _borrower.repay(_pool, 5_000 * 1e18);
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(deposited,                 80 * 1e18);
        assertEq(borrowerEncumbered,        2.995420370746656207 * 1e18);
        assertEq(borrowerCollateralization, 26.707436719494141185 * 1e18);

        assertEq(_pool.getPoolCollateralization(), borrowerCollateralization);
        // collateralization should increase, decreasing target utilization
        assertLt(collateralization, _pool.getPoolCollateralization());
        assertGt(actualUtilization, _pool.getPoolActualUtilization());
        assertGt(targetUtilization, _pool.getPoolTargetUtilization());

        actualUtilization = _pool.getPoolActualUtilization();
        targetUtilization = _pool.getPoolTargetUtilization();

        // borrower pays back entire loan and accumulated debt
        _quote.mint(address(_borrower), 15_001 * 1e18);
        _borrower.approveToken(_quote, address(_pool), 15_001 * 1e18);
        _borrower.repay(_pool, 15_001 * 1e18);
        // since collateralization dropped to 100%, target utilization should increase
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertGt(actualUtilization,                _pool.getPoolActualUtilization());
        assertLt(targetUtilization,                _pool.getPoolTargetUtilization());

        actualUtilization = _pool.getPoolActualUtilization();
        targetUtilization = _pool.getPoolTargetUtilization();

        // remove remaining collateral
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_borrower), 80 * 1e18);
        vm.expectEmit(true, false, false, true);
        emit RemoveCollateral(address(_borrower), 80 * 1e18);
        _borrower.removeCollateral(_pool, 80 * 1e18);
        assertEq(_pool.getPoolCollateralization(), Maths.ONE_WAD);
        assertEq(actualUtilization,                _pool.getPoolActualUtilization());
        assertEq(targetUtilization,                _pool.getPoolTargetUtilization());

        // check borrower balances
        (, , deposited, borrowerEncumbered, borrowerCollateralization, , ) = _pool.getBorrowerInfo(
            address(_borrower)
        );
        assertEq(deposited,                 0);
        assertEq(borrowerEncumbered,        0);
        assertEq(borrowerCollateralization, Maths.ONE_WAD);

        assertEq(_collateral.balanceOf(address(_borrower)), 100 * 1e18);
        // // check pool balances
        poolEncumbered = _pool.getEncumberedCollateral(_pool.totalDebt());
        assertEq(poolEncumbered,                   borrowerEncumbered);
        assertEq(_pool.getPoolCollateralization(), borrowerCollateralization);
        assertEq(_pool.getPoolTargetUtilization(), Maths.ONE_WAD);
        assertEq(_pool.getPoolActualUtilization(), 0);
        assertEq(_pool.totalCollateral(),          0);

        assertEq(_collateral.balanceOf(address(_pool)), 0);
    }

    // @notice: With 2 lenders, 1 borrower and 1 bidder tests adding quote token, adding collateral
    // @notice: and borrowing. purchaseBid is made then collateral is claimed and quote token is removed
    // @notice: lender1 reverts:
    // @notice:     attempts to claim from invalidPrice
    // @notice:     attempts to claim more than LP balance allows
    // @notice: lender reverts:
    // @notice:     attempts to claim from bucket with no claimable collateral
    function testClaimCollateral() external {
        uint256 priceHigh = _p4000;
        uint256 priceMed  = _p3010;
        uint256 priceLow  = _p1004;
        // should fail if invalid price
        vm.expectRevert(IPool.InvalidPrice.selector);
        _lender.claimCollateral(_pool, address(_lender), 10_000 * 1e18, 4_000 * 1e18);

        // should revert if no lp tokens in bucket
        vm.expectRevert(IPool.NoClaimToBucket.selector);
        _lender.claimCollateral(_pool, address(_lender), 1 * 1e18, priceHigh);

        // lender deposit DAI in 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 3_000 * 1e18, priceHigh);
        _lender.addQuoteToken(_pool, address(_lender), 4_000 * 1e18, priceMed);
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, priceLow);

        _lender1.addQuoteToken(_pool, address(_lender1), 3_000 * 1e18, priceHigh);

        // check LP balance for lender
        assertEq(_pool.lpBalance(address(_lender), priceHigh),  3_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), priceMed),   4_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), priceLow),   5_000 * 1e27);

        // check LP balance for lender1
        assertEq(_pool.lpBalance(address(_lender1), priceHigh), 3_000 * 1e27);

        // should revert when claiming collateral if no purchase bid was done on bucket
        vm.expectRevert(abi.encodeWithSelector(Buckets.ClaimExceedsCollateral.selector, 0));

        _lender.claimCollateral(_pool, address(_lender), 1 * 1e18, priceHigh);

        // borrower takes a loan of 4000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 4_000 * 1e18, 3_000 * 1e18);
        assertEq(_pool.lup(), priceHigh);

        // check 4_000.927678580567537368 bucket balance before purchase Bid
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _pool.bucketAt(_p4000);
        assertEq(deposit,          2_000 * 1e18);
        assertEq(debt,             4_000 * 1e18);
        assertEq(lpOutstanding,    6_000 * 1e27);
        assertEq(bucketCollateral, 0);

        // bidder purchases some of the top bucket
        _bidder.purchaseBid(_pool, 1_500 * 1e18, priceHigh);

        // check 4_000.927678580567537368 bucket collateral after purchase Bid
        (, , , , , , , bucketCollateral) = _pool.bucketAt(priceHigh);
        assertEq(bucketCollateral, 0.374913050298415730 * 1e18);

        // check balances
        assertEq(_collateral.balanceOf(address(_lender)),     0);
        assertEq(_pool.lpBalance(address(_lender), priceMed), 4_000 * 1e27);
        assertEq(_collateral.balanceOf(address(_bidder)),     99.625086949701584270 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)),       100.374913050298415730 * 1e18);
        assertEq(_quote.balanceOf(address(_lender)),          188_000 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),            9_500 * 1e18);
        assertEq(_pool.totalCollateral(),                     100 * 1e18);

        _lender1.removeQuoteToken(_pool, address(_lender1), 2_000 * 1e18, priceHigh);

        // should revert if claiming larger amount of collateral than LP balance allows
        vm.expectRevert(
            abi.encodeWithSelector(Buckets.InsufficientLpBalance.selector, 1_000.000000000000000015333334000 * 1e27)
        );
        _lender1.claimCollateral(_pool, address(_lender1), 0.3 * 1e18, priceHigh);

        // lender claims entire 0.37491305029841573 collateral from price bucket
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), address(_lender), 0.37491305029841573 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit ClaimCollateral(
            address(_lender),
            priceHigh,
            0.37491305029841573 * 1e18,
            1_500.000000000000000034500001000 * 1e27
        );
        _lender.claimCollateral(_pool, address(_lender), 0.37491305029841573 * 1e18, priceHigh);

        // check 4_000.927678580567537368 bucket balance after collateral claimed
        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p4000);
        assertEq(deposit,          0);
        assertEq(debt,             2_500 * 1e18);
        assertEq(lpOutstanding,    2_499.999999999999999980833333000 * 1e27);
        assertEq(bucketCollateral, 0);

        // claimer lp tokens for pool should be diminished
        assertEq(_pool.lpBalance(address(_lender), priceMed), 4_000.000000000000000000 * 1e27);
        // claimer collateral balance should increase with claimed amount
        assertEq(_collateral.balanceOf(address(_lender)),     0.374913050298415730 * 1e18);
        // claimer quote token balance should stay the same
        assertEq(_quote.balanceOf(address(_lender)),    188_000 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);
        assertEq(_pool.totalCollateral(),               100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      7_500 * 1e18);
    }

    // @notice: with 1 lender and 2 borrowers tests addQuoteToken, addCollateral, borrow
    // @notice: liquidate and then all collateral is claimed
    function testLiquidateClaimAllCollateral() public {
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p10016);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p9020);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p8002);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p100);

        // borrowers deposit collateral
        _borrower.addCollateral(_pool, 2 * 1e18);
        _borrower2.addCollateral(_pool, 200 * 1e18);

        // first borrower takes a loan of 12_000 DAI, pushing lup to 8_002.824356287850613262
        _borrower.borrow(_pool, 12_000 * 1e18, 8_000 * 1e18);

        // 2nd borrower takes a loan of 1_000 DAI, pushing lup to 100.332368143282009890
        _borrower2.borrow(_pool, 1_000 * 1e18, 100 * 1e18);

        // liquidate borrower
        _lender.liquidate(_pool, address(_borrower));

        // check HPB updated accordingly
        assertEq(_pool.hpb(), _p100);

        // check buckets debt and collateral after liquidation
        (
            ,
            uint256 up,
            uint256 down,
            uint256 deposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _pool.bucketAt(_p10016);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    10_000 * 1e27);
        assertEq(bucketCollateral, 1.198023071531052613 * 1e18);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p9020);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    1_000 * 1e27);
        assertEq(bucketCollateral, 0.221718140844638971 * 1e18);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p8002);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    1_000 * 1e27);
        assertEq(bucketCollateral, 0.124955885007559370 * 1e18);

        // claim all collateral from bucket 8_002.824356287850613262
        _lender.claimCollateral(_pool, address(_lender), 0.124955885007559370 * 1e18, _p8002);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p8002);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
        // check that the bucket was deactivated
        (, up, down, , , , , ) = _pool.bucketAt(_p8002);
        assertEq(up,   0);
        assertEq(down, 0);
        (, up, down, , , , , ) = _pool.bucketAt(_p9020);
        assertEq(up,   _p10016);
        assertEq(down, _p100);
        (, up, down, , , , , ) = _pool.bucketAt(_p100);
        assertEq(up,   _p9020);
        assertEq(down, 0);

        assertEq(_pool.lpBalance(address(_lender), _p8002), 0);

        // claim all collateral from bucket 9_020.461710444470171420
        _lender.claimCollateral(_pool, address(_lender), 0.221718140844638971 * 1e18, _p9020);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p9020);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
        // check that the bucket was deactivated
        (, up, down, , , , , ) = _pool.bucketAt(_p9020);
        assertEq(up,   0);
        assertEq(down, 0);
        (, up, down, , , , , ) = _pool.bucketAt(_p10016);
        assertEq(up,   _p10016);
        assertEq(down, _p100);
        (, up, down, , , , , ) = _pool.bucketAt(_p100);
        assertEq(up,   _p10016);
        assertEq(down, 0);

        assertEq(_pool.lpBalance(address(_lender), _p9020), 0);

        (uint256 col, uint256 quoteVal) = _pool.getLPTokenExchangeValue(
            _pool.getLPTokenBalance(address(_lender), 10_016.501589292607751220 * 1e18),
            10_016.501589292607751220 * 1e18
        );
        assertEq(col,      1.198023071531052613 * 1e18);
        assertEq(quoteVal, 0);

        // claim all collateral from bucket 10_016.501589292607751220
        _lender.claimCollateral(_pool, address(_lender), 1.198023071531052613 * 1e18, _p10016);

        (, , , deposit, debt, , lpOutstanding, bucketCollateral) = _pool.bucketAt(_p10016);
        assertEq(debt,             0);
        assertEq(deposit,          0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
        // check that the bucket was deactivated
        (, up, down, , , , , ) = _pool.bucketAt(_p10016);
        assertEq(up,   0);
        assertEq(down, 0);
        (, up, down, , , , , ) = _pool.bucketAt(_p100);
        assertEq(up,   _p100);
        assertEq(down, 0);

        assertEq(_pool.lpBalance(address(_lender), _p10016), 0);
    }

}
