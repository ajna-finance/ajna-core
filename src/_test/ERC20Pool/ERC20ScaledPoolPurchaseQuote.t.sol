// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20ScaledPurchaseQuoteTokenTest is ERC20HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower = makeAddr("borrower");
        _bidder   = makeAddr("bidder");
        _lender   = makeAddr("lender");
        _lender1  = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,   100 * 1e18);
        _mintCollateralAndApproveTokens(_bidder,     100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    /**
     *  @notice 1 lender, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuote() external {
        // test setup
        uint256 testIndex = 2550;

        // lender adds initial quote to pool
        Liquidity[] memory amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: testIndex, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // bidder deposits collateral into a bucket
        uint256 collateralToPurchaseWith = 4 * 1e18;
        _addCollateral(
            AddCollateralSpecs({
                from:   _bidder,
                amount: collateralToPurchaseWith,
                index:  testIndex
            })
        );

        // check bucket state and LPs
        BucketState[] memory bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: testIndex, LPs: 22_043.56808879152623138 * 1e27, collateral: collateralToPurchaseWith});
        _assertBuckets(bucketStates);
        BucketLP[] memory lps = new BucketLP[](1);
        lps[0] = BucketLP({index: testIndex, balance: 10_000 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        lps[0] = BucketLP({index: testIndex, balance: 12_043.56808879152623138 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _bidder,
                bucketLPs: lps
            })
        );

        (, uint256 availableCollateral) = _pool.buckets(testIndex);
        assertEq(availableCollateral, collateralToPurchaseWith);

        // bidder uses their LP to purchase all quote token in the bucket
        _removeLiquidity(
            RemoveLiquiditySpecs({
                from:     _bidder,
                index:    testIndex,
                amount:   10_000 * 1e18,
                penalty:  0,
                newLup:   _lup(),
                lpRedeem: 10_000 * 1e27
            })
        );
        assertEq(_quote.balanceOf(_bidder), 10_000 * 1e18);

        // check bucket state
        bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: testIndex, LPs: 12_043.56808879152623138 * 1e27, collateral: collateralToPurchaseWith});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](1);
        lps[0] = BucketLP({index: testIndex, balance: 10_000 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        lps[0] = BucketLP({index: testIndex, balance: 2_043.56808879152623138 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _bidder,
                bucketLPs: lps
            })
        );
        // check pool state and balances
        assertEq(_collateral.balanceOf(_lender), 0);
        assertEq(_collateral.balanceOf(address(_pool)),   collateralToPurchaseWith);
        assertGe(_collateral.balanceOf(address(_pool)), availableCollateral);
        assertEq(_quote.balanceOf(address(_pool)),        0);

        // lender exchanges their LP for collateral
        _removeAllCollateral(
            RemoveCollateralSpecs({
                from: _lender,
                amount: 3.321274866808485288 * 1e18,
                index: testIndex,
                lpRedeem: 10_000 * 1e27
            })
        );
        bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: testIndex, LPs: 2_043.56808879152623138 * 1e27, collateral: 0.678725133191514712 * 1e18});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](1);
        lps[0] = BucketLP({index: testIndex, balance: 0, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        lps[0] = BucketLP({index: testIndex, balance: 2_043.56808879152623138 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _bidder,
                bucketLPs: lps
            })
        );
        assertEq(_collateral.balanceOf(_lender), 3.321274866808485288 * 1e18);

        // bidder removes their _collateral
        _removeAllCollateral(
            RemoveCollateralSpecs({
                from: _bidder,
                amount: 0.678725133191514712 * 1e18,
                index: testIndex,
                lpRedeem: 2_043.56808879152623138 * 1e27
            })
        );
        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // check bucket state
        bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: testIndex, LPs: 0, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](1);
        lps[0] = BucketLP({index: testIndex, balance: 0, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        lps[0] = BucketLP({index: testIndex, balance: 0, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _bidder,
                bucketLPs: lps
            })
        );
    }

    /**
     *  @notice 2 lenders, 1 borrower, 1 bidder tests purchasing quote token with collateral.
     */
    function testPurchaseQuoteWithDebt() external {
        uint256 p2550 = 3_010.892022197881557845 * 1e18;

        // lenders add liquidity
        Liquidity[] memory amounts = new Liquidity[](3);
        amounts[0] = Liquidity({amount:  6_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount:  5_000 * 1e18, index: 2552, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 4_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 5_000 * 1e18, index: 2552, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender1,
                amounts: amounts
            })
        );
        skip(3600);

        // borrower draws debt
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 100 * 1e18,
                borrowAmount: 15_000 * 1e18,
                indexLimit:   3000,
                price:        _indexToPrice(2551)
            })
        );

        skip(86400);

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      15_000 * 1e18);

        // bidder purchases all quote from the highest bucket
        uint256 amountToPurchase = 10_100 * 1e18;
        assertGt(_quote.balanceOf(address(_pool)), amountToPurchase);
        uint256 amountWithInterest = 10_000.629204559150150000 * 1e18;
        // adding extra collateral to account for interest accumulation
        uint256 collateralToPurchaseWith = Maths.wmul(Maths.wdiv(amountToPurchase, p2550), 1.01 * 1e18);
        assertEq(collateralToPurchaseWith, 3.388032491631335842 * 1e18);

        // bidder purchases all quote from the highest bucket
        _addCollateral(
            AddCollateralSpecs({
                from:   _bidder,
                amount: collateralToPurchaseWith,
                index:  2550
            })
        );

        _removeAllLiquidity(
            RemoveAllLiquiditySpecs({
                from:     _bidder,
                index:    2550,
                amount:   amountWithInterest,
                newLup:   _indexToPrice(2552),
                lpRedeem: 10_000 * 1e27
            })
        );

        // bidder withdraws unused collateral
        uint256 expectedCollateral = 0.066548648694011883 * 1e18;
        _removeAllCollateral(
            RemoveCollateralSpecs({
                from:     _bidder,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 200.344335561364860742236645388 * 1e27
            })
        );
        BucketLP[] memory lps = new BucketLP[](1);
        lps[0] = BucketLP({index: 2550, balance: 0 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _bidder,
                bucketLPs: lps
            })
        );

        skip(7200);

        // lender exchanges their LP for collateral
        expectedCollateral = 1.992890305762394375 * 1e18;
        _removeAllCollateral(
            RemoveCollateralSpecs({
                from:     _lender,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 6_000 * 1e27
            })
        );
        lps[0] = BucketLP({index: 2550, balance: 0 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );

        skip(3600);

        // lender1 exchanges their LP for collateral
        expectedCollateral = 1.328593537174929584 * 1e18;
        _removeAllCollateral(
            RemoveCollateralSpecs({
                from:     _lender1,
                amount:   expectedCollateral,
                index:    2550,
                lpRedeem: 4_000 * 1e27
            })
        );
        lps[0] = BucketLP({index: 2550, balance: 0 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender1,
                bucketLPs: lps
            })
        );

        // check pool balances
        assertEq(_collateral.balanceOf(address(_pool)), 100 * 1e18);

        // check bucket state
        BucketState[] memory bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: 2550, LPs: 0, collateral: 0});
        _assertBuckets(bucketStates);
    }
}
