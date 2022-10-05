// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/interfaces/IERC20Pool.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolBorrowTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);
    }

    function testPoolBorrowAndRepay() external {
        uint256 highest = 2550;
        uint256 high    = 2551;
        uint256 med     = 2552;
        uint256 low     = 2553;
        uint256 lowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        Liquidity[] memory amounts = new Liquidity[](5);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: highest, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: high,    newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 10_000 * 1e18, index: med,     newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 10_000 * 1e18, index: low,     newLup: BucketMath.MAX_PRICE});
        amounts[4] = Liquidity({amount: 10_000 * 1e18, index: lowest,  newLup: BucketMath.MAX_PRICE});
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
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check balances before borrow
        assertEq(_quote.balanceOf(address(_pool)), 50_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 100 * 1e18,
                borrowAmount: 21_000 * 1e18,
                indexLimit:   3_000,
                price:        2_981.007422784467321543 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  210.201923076923077020 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                borrowerDebt:         21_020.192307692307702000 * 1e18,
                actualUtilization:    0.420403846153846154 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_102.0192307692307702 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 29_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        BucketLP[] memory lps = new BucketLP[](5);
        lps[0] = BucketLP({index: highest, balance: 10_000 * 1e27, time: _startTime});
        lps[1] = BucketLP({index: high,    balance: 10_000 * 1e27, time: _startTime});
        lps[2] = BucketLP({index: med,     balance: 10_000 * 1e27, time: _startTime});
        lps[3] = BucketLP({index: low,     balance: 10_000 * 1e27, time: _startTime});
        lps[4] = BucketLP({index: lowest,  balance: 10_000 * 1e27, time: _startTime});

        _assertLPs(
            LenderLPs({
                lender:    _lender,
                bucketLPs: lps
            })
        );

        // check buckets
        BucketState[] memory bucketStates = new BucketState[](5);
        bucketStates[0] = BucketState({index: highest, LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[1] = BucketState({index: high,    LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[2] = BucketState({index: med,     LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[3] = BucketState({index: low,     LPs: 10_000 * 1e27, collateral: 0});
        bucketStates[4] = BucketState({index: lowest,  LPs: 10_000 * 1e27, collateral: 0});

        _assertBuckets(bucketStates);

        // borrow 19_000 DAI
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 0,
                borrowAmount: 19_000 * 1e18,
                indexLimit:   3_500,
                price:        2_951.419442869698640451 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  400.384615384615384800 * 1e18,
                lup:                  2_951.419442869698640451 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 13.565832411651963522 * 1e18,
                borrowerDebt:         40_038.461538461538480000 * 1e18,
                actualUtilization:    0.800769230769230770 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        4_003.846153846153848 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 10_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // repay partial
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: 10_000 * 1e18,
                price:       2_966.176540084047110076 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  300.384615384615384800 * 1e18,
                lup:                  2_966.176540084047110076 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 10.126997207526425123 * 1e18,
                borrowerDebt:         30_038.461538461538480000 * 1e18,
                actualUtilization:    0.600769230769230770 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        3_003.846153846153848000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 20_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 40 * 1e18);
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: 30_038.461538461538480000 * 1e18,
                price:       BucketMath.MAX_PRICE
            })
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 50_038.461538461538480000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        // borrow 8_000 DAI
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 0,
                borrowAmount: 8_000 * 1e18,
                indexLimit:   3_500,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  80.076923076923076960 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 2.659574720267410143 * 1e18,
                borrowerDebt:         8_007.692307692307696000 * 1e18,
                actualUtilization:    0.160153846153846154 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        800.769230769230769600 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    function testPoolBorrowerInterestAccumulation() external {
        uint256 highest = 2550;
        uint256 high    = 2551;
        uint256 med     = 2552;
        uint256 low     = 2553;
        uint256 lowest  = 2554;

        // lender deposits 10000 DAI in 5 buckets each
        Liquidity[] memory amounts = new Liquidity[](5);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: highest, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: high,    newLup: BucketMath.MAX_PRICE});
        amounts[2] = Liquidity({amount: 10_000 * 1e18, index: med,     newLup: BucketMath.MAX_PRICE});
        amounts[3] = Liquidity({amount: 10_000 * 1e18, index: low,     newLup: BucketMath.MAX_PRICE});
        amounts[4] = Liquidity({amount: 10_000 * 1e18, index: lowest,  newLup: BucketMath.MAX_PRICE});
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
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        skip(10 days);
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 21_000 * 1e18,
                indexLimit:   3_000,
                price:        2_981.007422784467321543 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  420.403846153846154040 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                borrowerDebt:         21_020.192307692307702000 * 1e18,
                actualUtilization:    0.420403846153846154 * 1e18,
                targetUtilization:    0.000000461866946770 * 1e18,
                minDebtAmount:        2_102.019230769230770200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_020.192307692307702000 * 1e18,
                pendingDebt:       21_051.890446235135648008 * 1e18,
                collateral:        50 * 1e18,
                collateralization: 7.090818626082626625 * 1e18,
                mompFactor:        2_981.007422784467321543 * 1e18,
                inflator:          1 * 1e18
            })
        );

        skip(10 days);
        _pledgeCollateral(
            PledgeSpecs({
                from:     _borrower,
                borrower: _borrower,
                amount:   10 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  351.393939751686889789 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_055.509493137959600000 * 1e18,
                pledgedCollateral:    60 * 1e18,
                encumberedCollateral: 7.072654775682389039 * 1e18,
                borrowerDebt:         21_083.636385101213387311 * 1e18,
                actualUtilization:    0.421205110058694735 * 1e18,
                targetUtilization:    0.000000973344306926 * 1e18,
                minDebtAmount:        2_108.363638510121338731 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0605 * 1e18,
                interestRateUpdate:   _startTime + 20 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_083.636385101213387311 * 1e18,
                pendingDebt:       21_083.636385101213387311 * 1e18,
                collateral:        60 * 1e18,
                collateralization: 8.483377444958217435 * 1e18,
                mompFactor:        2_972.037088529352426932 * 1e18,
                inflator:          1.003018244385218513 * 1e18
            })
        );

        skip(10 days);
        _pullCollateral(
            PullSpecs({
                from:    _borrower,
                amount:  10 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  422.372244265211513504 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_086.113113158840754551 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.084387664333398315 * 1e18,
                borrowerDebt:         21_118.612213260575675180 * 1e18,
                actualUtilization:    0.421646059169087376 * 1e18,
                targetUtilization:    0.000001538993982628 * 1e18,
                minDebtAmount:        2_111.861221326057567518 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.06655 * 1e18,
                interestRateUpdate:   _startTime + 30 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_118.612213260575675180 * 1e18,
                pendingDebt:       21_118.612213260575675180 * 1e18,
                collateral:        50 * 1e18,
                collateralization: 7.057773002983275249 * 1e18,
                mompFactor:        2_967.114915734949620331 * 1e18,
                inflator:          1.004682160092905114 * 1e18
            })
        );

        skip(10 days);
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 0,
                borrowAmount: 0,
                indexLimit:   3_000,
                price:        2_981.007422784467321543 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  423.143052860217065973 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_119.836959946754668326 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.097316323771045134 * 1e18,
                borrowerDebt:         21_157.152643010853298669 * 1e18,
                actualUtilization:    0.422131314192394169 * 1e18,
                targetUtilization:    0.000002164656347431 * 1e18,
                minDebtAmount:        2_115.715264301085329867 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.073205 * 1e18,
                interestRateUpdate:   _startTime + 40 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_157.152643010853298669 * 1e18,
                pendingDebt:       21_157.152643010853298669 * 1e18,
                collateral:        50 * 1e18,
                collateralization: 7.044916376706357985 * 1e18,
                mompFactor:        2_961.709940599570999250 * 1e18,
                inflator:          1.006515655675920014 * 1e18
            })
        );

        skip(10 days);
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: 0,
                price:       2_981.007422784467321543 * 1e18
            })
        );
        _assertPool(
            PoolState({
                htp:                  423.992567137945688924 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.005764521268387350 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.111565102073903531 * 1e18,
                borrowerDebt:         21_199.628356897284446170 * 1e18,
                actualUtilization:    0.422665349212151634 * 1e18,
                targetUtilization:    0.000002856824049756 * 1e18,
                minDebtAmount:        2_119.962835689728444617 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0805255 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_199.628356897284446170 * 1e18,
                pendingDebt:       21_199.628356897284446170 * 1e18,
                collateral:        50 * 1e18,
                collateralization: 7.030801136225104189 * 1e18,
                mompFactor:        2_955.775839211865438160 * 1e18,
                inflator:          1.008536365727696620 * 1e18
            })
        );

        skip(10 days);
        _assertPool(
            PoolState({
                htp:                  423.992567137945688924 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.005764521268387350 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.111565102073903531 * 1e18,
                borrowerDebt:         21_199.628356897284446170 * 1e18,
                actualUtilization:    0.422665349212151634 * 1e18,
                targetUtilization:    0.000002856824049756 * 1e18,
                minDebtAmount:        2_119.962835689728444617 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0805255 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        _assertBorrower(
            BorrowerState({
                borrower:          _borrower,
                debt:              21_199.628356897284446170 * 1e18,
                pendingDebt:       21_246.450141935843879765 * 1e18,
                collateral:        50 * 1e18,
                collateralization: 7.030801136225104189 * 1e18,
                mompFactor:        2_955.775839211865438160 * 1e18,
                inflator:          1.008536365727696620 * 1e18
            })
        );
    }

    /**
     *  @notice 1 lender, 2 borrowers tests reverts in borrow.
     *          Reverts:
     *              Attempts to borrow with no available quote.
     *              Attempts to borrow more than minimum amount.
     *              Attempts to borrow when result would be borrower under collateralization.
     *              Attempts to borrow when result would be pool under collateralization.
     */
    function testPoolBorrowRequireChecks() external {
        // should revert if borrower attempts to borrow with an out of bounds limitIndex
        changePrank(_borrower);
        vm.expectRevert(IPoolErrors.BorrowLimitIndexReached.selector);
        _pool.borrow(1_000 * 1e18, 5000);

        // add initial quote to the pool
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        changePrank(_borrower);
        // should revert if borrower didn't pledged any collateral
        vm.expectRevert(IPoolErrors.BorrowBorrowerUnderCollateralized.selector);
        _pool.borrow(500 * 1e18, 3000);

        // borrower 1 borrows 500 quote from the pool after adding sufficient collateral
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 500 * 1e18,
                indexLimit:   3_000,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        // borrower 2 borrows 15k quote from the pool with borrower2 becoming new queue HEAD
        _borrow(
            BorrowSpecs({
                from:         _borrower2,
                borrower:     _borrower2,
                pledgeAmount: 6 * 1e18,
                borrowAmount: 15_000 * 1e18,
                indexLimit:   3_000,
                price:        2_995.912459898389633881 * 1e18
            })
        );

        changePrank(_borrower);
        // should revert if borrower attempts to borrow more than minimum amount
        vm.expectRevert(IPoolErrors.BorrowAmountLTMinDebt.selector);
        _pool.borrow(10 * 1e18, 3000);

        changePrank(_borrower2);
        vm.expectRevert(IPoolErrors.BorrowBorrowerUnderCollateralized.selector);
        _pool.borrow(2_976 * 1e18, 3000);

        // should be able to borrow if properly specified
        _borrow(
            BorrowSpecs({
                from:         _borrower2,
                borrower:     _borrower2,
                pledgeAmount: 0,
                borrowAmount: 10 * 1e18,
                indexLimit:   3_000,
                price:        2_995.912459898389633881 * 1e18
            })
        );
    }

    /**
     *  @notice 1 lender, 2 borrowers tests reverts in repay.
     *          Reverts:
     *              Attempts to repay without quote tokens.
     *              Attempts to repay without debt.
     *              Attempts to repay when bucket would be left with amount less than averge debt.
     */
    function testPoolRepayRequireChecks() external {
        // add initial quote to the pool
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        changePrank(_borrower);
        // should revert if borrower has no debt
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);
        vm.expectRevert(IPoolErrors.RepayNoDebt.selector);
        _pool.repay(_borrower, 10_000 * 1e18);

        // borrower 1 borrows 1000 quote from the pool
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 1_000 * 1e18,
                indexLimit:   3_000,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                borrowerDebt:         1_000.961538461538462000 * 1e18,
                actualUtilization:    0.050048076923076923 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        100.096153846153846200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // borrower 2 borrows 5k quote from the pool and becomes new queue HEAD
        _borrow(
            BorrowSpecs({
                from:         _borrower2,
                borrower:     _borrower2,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 5_000 * 1e18,
                indexLimit:   3_000,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  100.096153846153846200 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 1.994681040200557607 * 1e18,
                borrowerDebt:         6_005.769230769230772000 * 1e18,
                actualUtilization:    0.300288461538461539 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                2,
                maxBorrower:          _borrower2,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // should revert if amount left after repay is less than the average debt
        changePrank(_borrower);
        vm.expectRevert(IPoolErrors.BorrowAmountLTMinDebt.selector);
        _pool.repay(_borrower, 750 * 1e18);

        // should be able to repay loan if properly specified
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: 0.0001 * 1e18,
                price:       3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  100.096153846153846200 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 1.994681006987808939 * 1e18,
                borrowerDebt:         6_005.769130769230772000 * 1e18,
                actualUtilization:    0.300288456538461539 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288456538461538600 * 1e18,
                loans:                2,
                maxBorrower:          _borrower2,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    function testRepayLoanFromDifferentActor() external {
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // borrower 1 borrows 1000 quote from the pool
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 1_000 * 1e18,
                indexLimit:   3_000,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                borrowerDebt:         1_000.961538461538462000 * 1e18,
                actualUtilization:    0.050048076923076923 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        100.096153846153846200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // should be able to repay loan on behalf of borrower
        _repay(
            RepaySpecs({
                from:        _lender,
                borrower:    _borrower,
                repayAmount: 0.0001 * 1e18,
                price:       3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  20.019228769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446806820677600 * 1e18,
                borrowerDebt:         1_000.961438461538462000 * 1e18,
                actualUtilization:    0.050048071923076923 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        100.096143846153846200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    /**
     *  @notice 1 lender, 1 borrower test significantly overcollateralized loans with 0 TP.
     *          Reverts:
     *              Attempts to borrow with a TP of 0.
     */
    function testZeroThresholdPriceLoan() external {
        // add initial quote to the pool
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // borrower 1 initiates a highly overcollateralized loan with a TP of 0 that won't be inserted into the Queue
        changePrank(_borrower);
        _pool.pledgeCollateral(_borrower, 50 * 1e18);
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.borrow(0.00000000000000001 * 1e18, 3000);

        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 500 * 1e18,
                indexLimit:   3_000,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  5.004807692307692310 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0.166223420016713134 * 1e18,
                borrowerDebt:         500.48076923076923100 * 1e18,
                actualUtilization:    0.025024038461538462 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    /**
     *  @notice 1 lender, 1 borrower test repayment that would result in significant overcollateraization and 0 TP.
     *          Reverts:
     *              Attempts to repay with a subsequent TP of 0.
     */
    function testZeroThresholdPriceLoanAfterRepay() external {

        // add initial quote to the pool
        Liquidity[] memory amounts = new Liquidity[](2);
        amounts[0] = Liquidity({amount: 10_000 * 1e18, index: 2550, newLup: BucketMath.MAX_PRICE});
        amounts[1] = Liquidity({amount: 10_000 * 1e18, index: 2551, newLup: BucketMath.MAX_PRICE});
        _addLiquidity(
            AddLiquiditySpecs({
                from:    _lender,
                amounts: amounts
            })
        );

        // borrower 1 borrows 500 quote from the pool
        _borrow(
            BorrowSpecs({
                from:         _borrower,
                borrower:     _borrower,
                pledgeAmount: 50 * 1e18,
                borrowAmount: 500 * 1e18,
                indexLimit:   2_551,
                price:        3_010.892022197881557845 * 1e18
            })
        );

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.166223420016713134 * 1e18,
                borrowerDebt:         500.480769230769231000 * 1e18,
                actualUtilization:    0.025024038461538462 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        (, uint256 pendingDebt, , , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);
        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.repay(_borrower, pendingDebt - 1);

        // should be able to pay back all pendingDebt
        _repay(
            RepaySpecs({
                from:        _borrower,
                borrower:    _borrower,
                repayAmount: pendingDebt,
                price:       BucketMath.MAX_PRICE
            })
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             20_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

}
