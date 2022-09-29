// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

contract ERC20PoolQuoteTokenTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("bidder");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  200 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests adding quote token.
     *          Lender reverts:
     *              attempts to addQuoteToken at invalid price.
     */
    function testPoolDepositQuoteToken() external {
        assertEq(_hpb(), BucketMath.MIN_PRICE);

        // test 10_000 deposit at price of 3_010.892022197881557845
        Liquidity[] memory amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             10_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        BucketState[] memory bucketStates = new BucketState[](1);
        bucketStates[0] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        BucketLP[] memory lps = new BucketLP[](1);
        lps[0] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 10_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        190_000 * 1e18);

        // check bucket balance
        (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // test 20_000 deposit at price of 2_995.912459898389633881
        amounts[0] = Liquidity({amount: 20_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        bucketStates = new BucketState[](2);
        bucketStates[0] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[0] = BucketState({index: 2551, LPs: 20_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](2);
        lps[0] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2551, balance: 20_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender), 170_000 * 1e18);

        // test 40_000 deposit at price of 3_025.946482308870940904 DAI
        amounts[0] = Liquidity({amount: 40_000 * 1e18, index: 2549, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             70_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        bucketStates = new BucketState[](3);
        bucketStates[0] = BucketState({index: 2549, LPs: 40_000 * 1e27, collateral: 0});
        bucketStates[1] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[2] = BucketState({index: 2551, LPs: 20_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](3);
        lps[0] = BucketLP({index: 2549, balance: 40_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2551, balance: 20_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);
    }

    function testPoolRemoveQuoteToken() external {
        Liquidity[] memory amounts = new Liquidity[](3);
        amounts[0] = Liquidity({amount: 40_000 * 1e18, index: 2549, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 20_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             70_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        BucketState[] memory bucketStates = new BucketState[](3);
        bucketStates[0] = BucketState({index: 2549, LPs: 40_000 * 1e27, collateral: 0});
        bucketStates[1] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[2] = BucketState({index: 2551, LPs: 20_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        BucketLP[] memory lps = new BucketLP[](3);
        lps[0] = BucketLP({index: 2549, balance: 40_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2551, balance: 20_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 70_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        130_000 * 1e18);

        _removeLiquidity(
            RemoveLiquiditySpecs({
                from:     _lender,
                index:    2549,
                amount:   5_000 * 1e18,
                penalty:  0,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 5_000 * 1e27
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             65_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        bucketStates = new BucketState[](3);
        bucketStates[0] = BucketState({index: 2549, LPs: 35_000 * 1e27, collateral: 0});
        bucketStates[1] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[2] = BucketState({index: 2551, LPs: 20_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](3);
        lps[0] = BucketLP({index: 2549, balance: 35_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2551, balance: 20_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   65_000 * 1e18);
        assertEq(_quote.balanceOf(_lender), 135_000 * 1e18);

        _removeLiquidity(
            RemoveLiquiditySpecs({
                from:     _lender,
                index:    2549,
                amount:   35_000 * 1e18,
                penalty:  0,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 35_000 * 1e27
            })
        );
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                inflatorSnapshot:     1e18,
                pendingInflator:      1e18,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        bucketStates = new BucketState[](3);
        bucketStates[0] = BucketState({index: 2549, LPs: 0,             collateral: 0});
        bucketStates[1] = BucketState({index: 2550, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[2] = BucketState({index: 2551, LPs: 20_000 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](3);
        lps[0] = BucketLP({index: 2549, balance: 0,             time: _startTime});
        lps[1] = BucketLP({index: 2550, balance: 10_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2551, balance: 20_000 * 1e27, time: _startTime});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender), 170_000 * 1e18);
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available in bucket.
     */
    function testPoolRemoveQuoteTokenNotAvailable() external {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);
        // lender adds initial quote token
        Liquidity[] memory amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 4550, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 3_500_000 * 1e18,
                borrowAmount: 10_000 * 1e18,
                indexLimit:   4_551,
                price:        0.140143083210662942 * 1e18
            })
        );

        changePrank(_lender);
        vm.expectRevert(IPoolErrors.RemoveQuoteLUPBelowHTP.selector);
        _pool.removeAllQuoteToken(4550);
    }

    /**
     *  @notice 1 lender tests reverts in removeQuoteToken.
     *          Reverts:
     *              Attempts to remove more quote tokens than available from lpBalance.
     *              Attempts to remove quote token when doing so would drive lup below htp.
     */
    function testPoolRemoveQuoteTokenRequireChecks() external {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 3_500_000 * 1e18);
        // lender adds initial quote token
        Liquidity[] memory amounts = new Liquidity[](4);
        amounts[0] = Liquidity({amount: 40_000 * 1e18, index: 4549, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 4550, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 20_000 * 1e18, index: 4551, newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 30_000 * 1e18, index: 4990, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 3_500_000 * 1e18,
                borrowAmount: 70_000 * 1e18,
                indexLimit:   4551,
                price:        0.139445853940958153 * 1e18
            })
        );

        // ensure lender cannot withdraw from a bucket with no deposit
        changePrank(_lender1);
        // ensure lender with no LP cannot remove anything
        vm.expectRevert(IPoolErrors.RemoveQuoteNoClaim.selector);
        _pool.removeAllQuoteToken(4550);

        // should revert if insufficient quote token
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.RemoveQuoteInsufficientQuoteAvailable.selector);
        _pool.removeQuoteToken(20_000 * 1e18, 4550);

        // should revert if removing quote token from higher price buckets would drive lup below htp
        vm.expectRevert(IPoolErrors.RemoveQuoteLUPBelowHTP.selector);
        _pool.removeQuoteToken(20_000 * 1e18, 4551);

        // should revert if bucket has enough quote token, but lender has insufficient LP
        changePrank(_lender1);
        _pool.addQuoteToken(20_000 * 1e18, 4550);
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.RemoveQuoteInsufficientLPB.selector);
        _pool.removeQuoteToken(15_000 * 1e18, 4550);

        // should be able to removeQuoteToken if quote tokens haven't been encumbered by a borrower
        _removeLiquidity(
            RemoveLiquiditySpecs({
                from:     _lender,
                index:    4990,
                amount:   10_000 * 1e18,
                penalty:  0,
                newLup:   _indexToPrice(4551),
                lpRedeem: 10_000 * 1e27
            })
        );
    }

    function testPoolRemoveQuoteTokenWithDebt() external {
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_borrower) + 100 * 1e18);

        // lender adds initial quote token
        skip(1 minutes);  // prevent deposit from having a zero timestamp

        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 3_400 * 1e18, index: 1606, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 3_400 * 1e18, index: 1663, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        BucketState[] memory bucketStates = new BucketState[](2);
        bucketStates[0] = BucketState({index: 1606, LPs: 3_400 * 1e27, collateral: 0});
        bucketStates[1] = BucketState({index: 1663, LPs: 3_400 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        BucketLP[] memory lps = new BucketLP[](2);
        lps[0] = BucketLP({index: 1606, balance: 3_400 * 1e27, time: _startTime + 1 minutes});
        lps[1] = BucketLP({index: 1663, balance: 3_400 * 1e27, time: _startTime + 1 minutes});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        uint256 exchangeRateBefore = _exchangeRate(1606);

        skip(59 minutes);

        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        assertEq(exchangeRateBefore, _exchangeRate(1606));
        uint256 lenderBalanceBefore = _quote.balanceOf(_lender);

        // borrower takes a loan of 3000 quote token
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 100 * 1e18,
                borrowAmount: 3_000 * 1e18,
                indexLimit:   2_000,
                price:        333_777.824045947762079231 * 1e18
            })
        );

        skip(2 hours);
        lps[0] = BucketLP({index: 1606, balance: 3_400 * 1e27, time: _startTime + 1 minutes});
        lps[1] = BucketLP({index: 1663, balance: 3_400 * 1e27, time: _startTime + 1 minutes});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
        assertEq(exchangeRateBefore, _exchangeRate(1606));

        // lender makes a partial withdrawal, paying an early withdrawal penalty
        uint256 penalty = Maths.WAD - Maths.wdiv(_pool.interestRate(), PoolUtils.WAD_WEEKS_PER_YEAR);
        assertLt(penalty, Maths.WAD);
        uint256 expectedWithdrawal1 = Maths.wmul(1_700 * 1e18, penalty);
        _removeLiquidity(
            RemoveLiquiditySpecs({
                from:     _lender,
                index:    1606,
                amount:   1_700 * 1e18,
                penalty:  penalty,
                newLup:   _indexToPrice(1663),
                lpRedeem: 1_699.988732998890538932348791152 * 1e27
            })
        );

        // lender removes all quote token, including interest, from the bucket
        skip(1 days);
        assertGt(_indexToPrice(1606), _htp());
        uint256 expectedWithdrawal2 = 1_700.144368656943031197 * 1e18;
        _removeAllLiquidity(
            RemoveAllLiquiditySpecs({
                from:     _lender,
                index:    1606,
                amount:   expectedWithdrawal2,
                newLup:   _indexToPrice(1663),
                lpRedeem: 1_700.011267001109461067651208848 * 1e27
            })
        );
        assertEq(_quote.balanceOf(_lender), lenderBalanceBefore + expectedWithdrawal1 + expectedWithdrawal2);

        bucketStates = new BucketState[](2);
        bucketStates[0] = BucketState({index: 1606, LPs: 0, collateral: 0});
        bucketStates[1] = BucketState({index: 1663, LPs: 3_400 * 1e27, collateral: 0});
        _assertBuckets(bucketStates);
        lps = new BucketLP[](2);
        lps[0] = BucketLP({index: 1606, balance: 0, time: _startTime + 1 minutes});
        lps[1] = BucketLP({index: 1663, balance: 3_400 * 1e27, time: _startTime + 1 minutes});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
    }

    function testPoolMoveQuoteToken() external {
        Liquidity[] memory amounts = new Liquidity[](3);
        amounts[0] = Liquidity({amount: 40_000 * 1e18, index: 2549, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 20_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        BucketLP[] memory lps = new BucketLP[](2);
        lps[0] = BucketLP({index: 2549, balance: 40_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2552, balance: 0, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );

        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       5_000 * 1e18,
                fromIndex:    2549,
                toIndex:      2552,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 5_000 * 1e27,
                lpRedeemTo:   5_000 * 1e27
            })
        );

        lps[0] = BucketLP({index: 2549, balance: 35_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: 2552, balance: 5_000 * 1e27, time: 0});  // FIXME: This doesn't seem right
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );

        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       5_000 * 1e18,
                fromIndex:    2549,
                toIndex:      2540,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 5_000 * 1e27,
                lpRedeemTo:   5_000 * 1e27
            })
        );

        lps = new BucketLP[](3);
        lps[0] = BucketLP({index: 2540, balance: 5_000 * 1e27, time: 0});
        lps[1] = BucketLP({index: 2549, balance: 30_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2552, balance: 5_000 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );

        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       15_000 * 1e18,
                fromIndex:    2551,
                toIndex:      2777,
                newLup:       BucketMath.MAX_PRICE,
                lpRedeemFrom: 15_000 * 1e27,
                lpRedeemTo:   15_000 * 1e27
            })
        );

        lps = new BucketLP[](5);
        lps[0] = BucketLP({index: 2540, balance: 5_000 * 1e27, time: 0});
        lps[1] = BucketLP({index: 2549, balance: 30_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: 2551, balance: 5_000 * 1e27, time: _startTime});
        lps[3] = BucketLP({index: 2552, balance: 5_000 * 1e27, time: 0});
        lps[4] = BucketLP({index: 2777, balance: 15_000 * 1e27, time: 0});
        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );
    }

    /**
     *  @notice 1 lender, 1 bidder, 1 borrower tests reverts in moveQuoteToken.
     *          Reverts:
     *              Attempts to move quote token to the same price.
     *              Attempts to move quote token from bucket with available collateral.
     *              Attempts to move quote token when doing so would drive lup below htp.
     */
    function testPoolMoveQuoteTokenRequireChecks() external {
        // test setup
        _mintCollateralAndApproveTokens(_lender1, _collateral.balanceOf(_lender1) + 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, _collateral.balanceOf(_lender1) + 1_500_000 * 1e18);

        // lender adds initial quote token
        Liquidity[] memory amounts = new Liquidity[](4);
        amounts[0] = Liquidity({amount: 40_000 * 1e18, index: 4549, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 4550, newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 20_000 * 1e18, index: 4551, newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 30_000 * 1e18, index: 4651, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // should revert if moving quote token to the existing price
        vm.expectRevert(IPoolErrors.MoveQuoteToSamePrice.selector);
        _pool.moveQuoteToken(5_000 * 1e18, 4549, 4549);

        // borrow all available quote in the higher priced original 3 buckets, as well as some of the new lowest price bucket
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 1_500_000 * 1e18,
                borrowAmount: 60_000.1 * 1e18,
                indexLimit:   4651,
                price:        0.139445853940958153 * 1e18
            })
        );

        // should revert if movement would drive lup below htp
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.MoveQuoteLUPBelowHTP.selector);
        _pool.moveQuoteToken(40_000 * 1e18, 4549, 6000);

        // should be able to moveQuoteToken if properly specified
        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       10_000 * 1e18,
                fromIndex:    4549,
                toIndex:      4550,
                newLup:       _indexToPrice(4551),
                lpRedeemFrom: 10_000 * 1e27,
                lpRedeemTo:   10_000 * 1e27
            })
        );
    }

    function testMoveQuoteTokenWithDebt() external {
        // lender makes an initial deposit
        skip(1 hours);
        Liquidity[] memory amounts = new Liquidity[](1);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2873, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // borrower draws debt, establishing a pool threshold price
        skip(2 hours);
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 10 * 1e18,
                borrowAmount: 5_000 * 1e18,
                indexLimit:   3000,
                price:        601.252968524772188572 * 1e18
            })
        );

        uint256 ptp = Maths.wdiv(_pool.borrowerDebt(), 10 * 1e18);
        assertEq(ptp, 500.480769230769231 * 1e18);

        // lender moves some liquidity below the pool threshold price; penalty should be assessed
        skip(16 hours);
        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       2_500 * 1e18,
                fromIndex:    2873,
                toIndex:      2954,
                newLup:       _lup(),
                lpRedeemFrom: 2_499.880458897159855582175961109 * 1e27,
                lpRedeemTo:   2_497.596153846153845 * 1e27
            })
        );

        // another lender provides liquidity to prevent LUP from moving
        skip(1 hours);
        amounts[0] = Liquidity({amount: 1_000 * 1e18, index: 2873, newLup: 601.252968524772188572 * 1e18});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender1,
                amounts: amounts
            })
        );

        // lender moves more liquidity; no penalty assessed as sufficient time has passed
        skip(12 hours);
        _moveLiquidity(
            MoveLiquiditySpecs({
                from:         _lender,
                amount:       2_500 * 1e18,
                fromIndex:    2873,
                toIndex:      2954,
                newLup:       _lup(),
                lpRedeemFrom: 2_499.791307594218224136823992573 * 1e27,
                lpRedeemTo:   2_500.000000000000000000 * 1e27
            })
        );

        // after a week, another lender funds the pool
        skip(7 days);
        amounts[0] = Liquidity({amount: 9_000 * 1e18, index: 2873, newLup: 601.252968524772188572 * 1e18});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender1,
                amounts: amounts
            })
        );

        // lender removes all their quote, with interest
        skip(1 hours);
        _removeAllLiquidity(
            RemoveAllLiquiditySpecs({
                from:     _lender,
                index:    2873,
                amount:   5_004.057192447017367276 * 1e18,
                newLup:   601.252968524772188572 * 1e18,
                lpRedeem: 5_000.328233508621920281000046318 * 1e27
            })
        );
        _removeAllLiquidity(
            RemoveAllLiquiditySpecs({
                from:     _lender,
                index:    2954,
                amount:   4_997.596153846153845 * 1e18,
                newLup:   601.252968524772188572 * 1e18,
                lpRedeem: 4_997.596153846153845 * 1e27
            })
        );
        assertGt(_quote.balanceOf(_lender), 200_000 * 1e18);
    }
}
