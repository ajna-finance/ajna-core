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
    uint internal _anonBorrowerCount = 0;

    uint256 highest = 2550;
    uint256 high    = 2551;
    uint256 med     = 2552;
    uint256 low     = 2553;
    uint256 lowest  = 2554;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);

        // lender deposits 10000 DAI in 5 buckets each
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  highest,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  high,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  med,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  low,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  lowest,
                newLup: BucketMath.MAX_PRICE
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
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

    /**
     *  @dev Creates debt for an anonymous non-player borrower not otherwise involved in the test.
     **/
    function _anonBorrowerDrawsDebt(uint256 loanAmount) internal {
        _anonBorrowerCount += 1;
        address borrower = makeAddr(string(abi.encodePacked("anonBorrower", _anonBorrowerCount)));
        vm.stopPrank();
        _mintCollateralAndApproveTokens(borrower,  100 * 1e18);
        _pledgeCollateral(
            {
                from:     borrower,
                borrower: borrower,
                amount:   100 * 1e18
            }
        );
        _pool.borrow(loanAmount, 7_777);
    }

    function testPoolBorrowAndRepay() external {
        // check balances before borrow
        assertEq(_quote.balanceOf(address(_pool)), 50_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     21_000 * 1e18,
                indexLimit: 3_000,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  210.201923076923077020 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                poolDebt:             21_020.192307692307702000 * 1e18,
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

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       highest,
                lpBalance:   10_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       high,
                lpBalance:   10_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       med,
                lpBalance:   10_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       low,
                lpBalance:   10_000 * 1e27,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       lowest,
                lpBalance:   10_000 * 1e27,
                depositTime: 0
            }
        );

        // check buckets
        _assertBucket(
            {
                index:        highest,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        high,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        med,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        low,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        lowest,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // borrow 19_000 DAI
        _borrow(
            {
                from:       _borrower,
                amount:     19_000 * 1e18,
                indexLimit: 3_500,
                newLup:     2_951.419442869698640451 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  400.384615384615384800 * 1e18,
                lup:                  2_951.419442869698640451 * 1e18,  // FIMXE: actual is 2_995.912459898389633881,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 13.565832411651963522 * 1e18,
                poolDebt:             40_038.461538461538480000 * 1e18,
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
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10_000 * 1e18,
                repaid:   10_000 * 1e18,
                newLup:   2_966.176540084047110076 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  300.384615384615384800 * 1e18,
                lup:                  2_966.176540084047110076 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 10.126997207526425123 * 1e18,
                poolDebt:             30_038.461538461538480000 * 1e18,
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
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   30_038.461538461538480000 * 1e18,
                repaid:   30_038.461538461538480000 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
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
            {
                from:       _borrower,
                amount:     8_000 * 1e18,
                indexLimit: 3_500,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  80.076923076923076960 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 2.659574720267410143 * 1e18,
                poolDebt:             8_007.692307692307696000 * 1e18,
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
        skip(10 days);
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     21_000 * 1e18,
                indexLimit: 3_000,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  420.403846153846154040 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.062005376213123432 * 1e18,
                poolDebt:             21_051.890446235135648008 * 1e18,
                actualUtilization:    0.421037808924702713 * 1e18,
                targetUtilization:    0.000000461866946770 * 1e18,
                minDebtAmount:        2_105.189044623513564801 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_083.636385101213377977 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        2_981.007422784467321543 * 1e18,
                borrowerCollateralization: 7.069481204131847866 * 1e18
            }
        );

        skip(10 days);
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  352.454532537342231182 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_055.682846339673350000 * 1e18,
                pledgedCollateral:    60 * 1e18,
                encumberedCollateral: 7.072654775682389039 * 1e18,
                poolDebt:             21_083.636385101213387311 * 1e18,
                actualUtilization:    0.421203651338120869 * 1e18,
                targetUtilization:    0.000000973344306926 * 1e18,
                minDebtAmount:        2_108.363638510121338731 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0605 * 1e18,
                interestRateUpdate:   _startTime + 20 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_147.271952240533870911 * 1e18,  // TODO: doesn't match poolDebt because this is pending
                borrowerCollateral:        60 * 1e18,
                borrowerMompFactor:        2_972.037088529352426932 * 1e18,
                borrowerCollateralization: 8.457849587928429739 * 1e18
            }
        );

        skip(10 days);
        _pullCollateral(
            {
                from:    _borrower,
                amount:  10 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  424.349858731660857846 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_086.338994338719038707 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.084387664333398317 * 1e18,
                poolDebt:             21_118.612213260575680078 * 1e18,
                actualUtilization:    0.421644157614466925 * 1e18,
                targetUtilization:    0.000001538993982628 * 1e18,
                minDebtAmount:        2_111.861221326057568008 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.06655 * 1e18,
                interestRateUpdate:   _startTime + 30 days
            })
        );
        // FIXME: borrower debt does not match pool debt, even though no time has passed since pool interest accrual
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_217.492936583042892299 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        2_967.114915734949620331 * 1e18,
                borrowerCollateralization: 7.024881383711071213 * 1e18
            }
        );

        skip(10 days);
        _borrow(
            {
                from:       _borrower,
                amount:     0,
                indexLimit: 3_000,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  425.900107294311861922 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_120.126521144040579960 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.097316323771045135 * 1e18,
                poolDebt:             21_157.152643010853304038 * 1e18,
                actualUtilization:    0.422128875394704824 * 1e18,
                targetUtilization:    0.000002164656347431 * 1e18,
                minDebtAmount:        2_115.715264301085330404 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.073205 * 1e18,
                interestRateUpdate:   _startTime + 40 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_295.005364715593096087 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        2_961.709940599570999250 * 1e18,
                borrowerCollateralization: 6.999311274473305047 * 1e18
            }
        );

        skip(10 days);
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   0,
                repaid:   0,
                newLup:   2_981.007422784467321543 * 1e18
            }
        );
        _assertPool(
            PoolState({
                htp:                  427.611922756860156608 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.372540179480195775 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.111565102073903530 * 1e18,
                poolDebt:             21_199.628356897284442294 * 1e18,
                actualUtilization:    0.422662258472868263 * 1e18,
                targetUtilization:    0.000002856824049756 * 1e18,
                minDebtAmount:        2_119.962835689728444229 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0805255 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_380.596137843007830373 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        2_955.775839211865438160 * 1e18,
                borrowerCollateralization: 6.971291641181544134 * 1e18
            }
        );

        skip(10 days);
        _assertPool(
            PoolState({
                htp:                  427.611922756860156608 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.372540179480195775 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.127271800648583574 * 1e18,
                poolDebt:             21_246.450141935843866714 * 1e18,
                actualUtilization:    0.423595756035984273 * 1e18,
                targetUtilization:    0.000002856824049756 * 1e18,
                minDebtAmount:        2_124.645014193584386671 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0805255 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
            // FIXME: borrowerPendingDebt was 21_246.450141935843879765 * 1e18
                borrowerDebt:              21_475.143377664162909876 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        2_955.775839211865438160 * 1e18,
                borrowerCollateralization: 6.940599581479277462 * 1e18
            }
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
        _assertBorrowLimitIndexRevert(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 1000
            }
        );

        // should revert if borrower didn't pledged any collateral
        _assertBorrowBorrowerUnderCollateralizedRevert(
            {
                from:       _borrower,
                amount:     500 * 1e18,
                indexLimit: 3000
            }
        );

        // borrower 1 borrows 500 quote from the pool after adding sufficient collateral
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     500 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        // borrower 2 borrows 15k quote from the pool with borrower2 becoming new queue HEAD
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   6 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     15_000 * 1e18,
                indexLimit: 3_000,
                newLup:     2_995.912459898389633881 * 1e18
            }
        );

        // should revert if borrower undercollateralized
        _assertBorrowBorrowerUnderCollateralizedRevert(
            {
                from:       _borrower2,
                amount:     2_976 * 1e18,
                indexLimit: 3000
            }
        );

        // should be able to borrow if properly specified
        _borrow(
            {
                from:       _borrower2,
                amount:     10 * 1e18,
                indexLimit: 3_000,
                newLup:     2_995.912459898389633881 * 1e18
            }
        );
    }

    function testMinBorrowAmountCheck() external {
        // 10 borrowers draw debt
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_200 * 1e18);
        }
        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );

        // should revert if borrower attempts to borrow more than minimum amount
        _assertBorrowMinDebtRevert(
            {
                from:       _borrower,
                amount:     10 * 1e18,
                indexLimit: 7_777
            }
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
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);

        // should revert if borrower has no debt
        _assertRepayNoDebtRevert(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10_000 * 1e18
            }
        );

        // borrower 1 borrows 1000 quote from the pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                poolDebt:             1_000.961538461538462000 * 1e18,
                actualUtilization:    0.020019230769230769 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        100.096153846153846200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // borrower 2 borrows 5k quote from the pool and becomes new queue HEAD
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     5_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  100.096153846153846200 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 1.994681040200557607 * 1e18,
                poolDebt:             6_005.769230769230772000 * 1e18,
                actualUtilization:    0.120115384615384615 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                2,
                maxBorrower:          _borrower2,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // should be able to repay loan if properly specified
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   0.0001 * 1e18,
                repaid:   0.0001 * 1e18,
                newLup:   3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  100.096153846153846200 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 1.994681006987808939 * 1e18,
                poolDebt:             6_005.769130769230772000 * 1e18,
                actualUtilization:    0.120115382615384615 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288456538461538600 * 1e18,
                loans:                2,
                maxBorrower:          _borrower2,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    function testMinRepayAmountCheck() external {
        // borrower 1 borrows 1000 quote from the pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        // 9 other borrowers draw debt
        for (uint i=0; i<9; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18);
        }
        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        // should revert if amount left after repay is less than the average debt
        _assertRepayMinDebtRevert(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   950 * 1e18
            }
        );
    }

    function testRepayLoanFromDifferentActor() external {
        // borrower 1 borrows 1000 quote from the pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                poolDebt:             1_000.961538461538462000 * 1e18,
                actualUtilization:    0.020019230769230769 * 1e18,
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
            {
                from:     _lender,
                borrower: _borrower,
                amount:   0.0001 * 1e18,
                repaid:   0.0001 * 1e18,
                newLup:   3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  20.019228769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446806820677600 * 1e18,
                poolDebt:             1_000.961438461538462000 * 1e18,
                actualUtilization:    0.020019228769230769 * 1e18,
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
        // borrower 1 initiates a highly overcollateralized loan with a TP of 0 that won't be inserted into the Queue
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.borrow(0.00000000000000001 * 1e18, 3000);

        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     500 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  5.004807692307692310 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0.166223420016713134 * 1e18,
                poolDebt:             500.48076923076923100 * 1e18,
                actualUtilization:    0.010009615384615385 * 1e18,
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

        // borrower 1 borrows 500 quote from the pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     500 * 1e18,
                indexLimit: 2_551,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.009615384615384620 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.166223420016713134 * 1e18,
                poolDebt:             500.480769230769231000 * 1e18,
                actualUtilization:    0.010009615384615385 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              500.480769230769231 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 300.799971477982403259 * 1e18
            }
        );
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);
        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert("H:I:VAL_EQ_0");
        _pool.repay(_borrower, 500.480769230769231000 * 1e18 - 1);

        // should be able to pay back all pendingDebt
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   500.480769230769231000 * 1e18,
                repaid:   500.480769230769231000 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
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
