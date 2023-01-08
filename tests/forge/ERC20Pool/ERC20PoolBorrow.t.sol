// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract, ERC20FuzzyHelperContract  } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

import 'src/ERC20Pool.sol';

contract ERC20PoolBorrowTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

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
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   highest,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   high,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            } 
        ); 
        _addLiquidity( 
            { 
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   med,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            } 
        ); 
        _addLiquidity( 
            { 
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   low,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            } 
        ); 
        _addLiquidity( 
            { 
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   lowest,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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

    function testPoolBorrowAndRepay() external tearDown {
        // check balances before borrow
        assertEq(_quote.balanceOf(address(_pool)), 50_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        150_000 * 1e18);

        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 21_000 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 100 * 1e18,
            newLup: 2_981.007422784467321543 * 1e18
        });

        _assertPool(
            PoolParams({
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
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       high,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       med,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       low,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       lowest,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
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
            PoolParams({
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
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    10_000 * 1e18,
            amountRepaid:     10_000 * 1e18,
            collateralToPull: 0,
            newLup:           2_966.176540084047110076 * 1e18
        });

        _assertPool(
            PoolParams({
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
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    30_038.461538461538480000 * 1e18,
            amountRepaid:     30_038.461538461538480000 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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
            PoolParams({
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

    function testPoolBorrowerInterestAccumulation() external tearDown {
        (uint256 liquidityAdded, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
        skip(10 days);
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     21_000 * 1e18,
            limitIndex:         3_000,
            collateralToPledge: 50 * 1e18,
            newLup:             2_981.007422784467321543 * 1e18
        });

        uint256 expectedDebt = 21_051.890446235135648008 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  420.403846153846154040 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.062005376213123432 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421037808924702713 * 1e18,
                targetUtilization:    0.141027440233999772 * 1e18,
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
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              441.424038461538461742 * 1e18,
                borrowerCollateralization: 7.080141877038845214 * 1e18
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

        expectedDebt = 21_083.636385101213387311 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  352.454532537342231182 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_055.509493137959600000 * 1e18,
                pledgedCollateral:    60 * 1e18,
                encumberedCollateral: 7.072654775682389039 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421205110058694735 * 1e18,
                targetUtilization:    0.127834905411600422 * 1e18,
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
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        60 * 1e18,
                borrowert0Np:              441.424038461538461742 * 1e18,
                borrowerCollateralization: 8.483377444958217435 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 55.509493137959600000 * 1e18);

        skip(10 days);
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 10 * 1e18
        });

        expectedDebt = 21_118.612213260575680078 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  424.349858731660857846 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_086.113113158840750000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.084387664333398317 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421646059169087376 * 1e18,
                targetUtilization:    0.132599912976061670 * 1e18,
                minDebtAmount:        2_111.861221326057568008 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.06655 * 1e18,
                interestRateUpdate:   _startTime + 30 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              445.838278846153846359 * 1e18,
                borrowerCollateralization: 7.057773002983275247 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 86.113113158840750000 * 1e18);

        skip(10 days);
        _borrowZeroAmount(
            {
                from:       _borrower,
                amount:     0,
                indexLimit: 3_000,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        expectedDebt = 21_157.152643010853304038 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  425.900107294311861922 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_119.836959946754650000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.097316323771045135 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.422131314192394169 * 1e18,
                targetUtilization:    0.135172469119117962 * 1e18,
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
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              448.381722115384615591 * 1e18,
                borrowerCollateralization: 7.044916376706357984 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 119.836959946754650000 * 1e18);

        skip(10 days);

        // call drawDebt to restamp the loan's neutral price
        IERC20Pool(address(_pool)).drawDebt(_borrower, 0, 0, 0);

        expectedDebt = 21_199.628356897284442294 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  427.611922756860156608 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.005764521268350000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.111565102073903530 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.422665349212151634 * 1e18,
                targetUtilization:    0.136817652441066412 * 1e18,
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
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              448.381722115384615591 * 1e18,
                borrowerCollateralization: 7.030801136225104190 * 1e18
            }
        );
        _assertLenderInterest(liquidityAdded, 157.005764521268350000 * 1e18);

        skip(10 days);
        expectedDebt = 21_246.450141935843866714 * 1e18;
        _assertPool(
            PoolParams({
                htp:                  427.611922756860156608 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_157.005764521268350000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.127271800648583574 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.423598853601516100 * 1e18,
                targetUtilization:    0.136817652441066412 * 1e18,
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
                borrowerDebt:              expectedDebt,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              448.381722115384615591 * 1e18,
                borrowerCollateralization: 7.015307034516347067 * 1e18
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
    function testPoolBorrowReverts() external tearDown {
        // should revert if borrower attempts to borrow with an out of bounds limitIndex
        _assertBorrowLimitIndexRevert(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 1000
            }
        );

        // should revert if borrower tries to borrow on behalf of different address
        _assertBorrowBorrowerNotSenderRevert(
            {
                from:       _borrower,
                borrower:   _borrower2,
                amount:     1 * 1e18,
                indexLimit: 7000
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

    function testMinBorrowAmountCheck() external tearDown {
        // 10 borrowers draw debt
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(100 * 1e18, 1_200 * 1e18, 7777);
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
    function testPoolRepayReverts() external tearDown {
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);

        // should revert if borrower has no debt
        _assertRepayNoDebtRevert(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10_000 * 1e18
            }
        );

        _assertPullBorrowerNotSenderRevert(
            {
                from:     _borrower,
                borrower: _borrower2,
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
            PoolParams({
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
            PoolParams({
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
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0.0001 * 1e18,
            amountRepaid:     0.0001 * 1e18,
            collateralToPull: 0,
            newLup:           3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
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

    function testMinRepayAmountCheck() external tearDown {
        // borrower 1 borrows 1000 quote from the pool
        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 1_000 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 50 * 1e18,
            newLup: 3_010.892022197881557845 * 1e18
        });

        // 9 other borrowers draw debt
        for (uint i=0; i<9; ++i) {
            _anonBorrowerDrawsDebt(100 * 1e18, 1_000 * 1e18, 7777);
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

    function testRepayLoanFromDifferentActor() external tearDown {
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
            PoolParams({
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
        _repayDebt({
            from:             _lender,
            borrower:         _borrower,
            amountToRepay:    0.0001 * 1e18,
            amountRepaid:     0.0001 * 1e18,
            collateralToPull: 0,
            newLup:           3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
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
    function testZeroThresholdPriceLoan() external tearDown {
        // borrower 1 initiates a highly overcollateralized loan with a TP of 0 that won't be inserted into the Queue
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   50 * 1e18
            }
        );
        vm.expectRevert(abi.encodeWithSignature('ZeroThresholdPrice()'));
        IERC20Pool(address(_pool)).drawDebt(_borrower, 0.00000000000000001 * 1e18, 3000, 0);


        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 500 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 50 * 1e18,
            newLup: 3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
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
    function testZeroThresholdPriceLoanAfterRepay() external tearDown {

        // borrower 1 borrows 500 quote from the pool
        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 500 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 50 * 1e18,
            newLup: 3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
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
                borrowert0Np:              10.510096153846153851 * 1e18,
                borrowerCollateralization: 300.799971477982403259 * 1e18
            }
        );
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);
        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert(abi.encodeWithSignature('ZeroThresholdPrice()'));
        IERC20Pool(address(_pool)).repayDebt(_borrower, 500.480769230769231000 * 1e18 - 1, 0);

        // should be able to pay back all pendingDebt
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    500.480769230769231000 * 1e18,
            amountRepaid:     500.480769230769231000 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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

    function testPoolBorrowRepayAndRemoveWithPenalty() external tearDown {
        // check balances before borrow
        assertEq(_quote.balanceOf(_lender), 150_000 * 1e18);

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       highest,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        assertEq(_quote.balanceOf(_borrower),      0);
        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);

        // pledge and borrow
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
        assertEq(_quote.balanceOf(_borrower),      21_000 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 0);

        _assertPoolPrices(
            {
                htp:      210.201923076923077020 * 1e18,
                htpIndex: 3_083,
                hpb:      3_010.892022197881557845 * 1e18,
                hpbIndex: 2550,
                lup:      2_981.007422784467321543 * 1e18,
                lupIndex: 2_552
            }
        );
        // penalty should not be applied on buckets with prices lower than PTP
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   _indexOf(200 * 1e18),
                lpAward: 10_000 * 1e27,
                newLup:  2_981.007422784467321543 * 1e18
            }
        );
        assertEq(_quote.balanceOf(_lender), 140_000 * 1e18);
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   10_000 * 1e18,
                index:    _indexOf(200 * 1e18),
                newLup:   2_981.007422784467321543 * 1e18,
                lpRedeem: 10_000 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_lender), 150_000 * 1e18); // no tokens paid as penalty

        // repay entire loan
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 40 * 1e18);
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    21_100 * 1e18,
            amountRepaid:     21_020.192307692307702000 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });
        assertEq(_quote.balanceOf(_borrower),      19.807692307692298000 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 0);

        _assertPoolPrices(
            {
                htp:      0,
                htpIndex: 7_388,
                hpb:      3_010.892022197881557845 * 1e18,
                hpbIndex: 2550,
                lup:      MAX_PRICE,
                lupIndex: 0
            }
        );
        // lender removes everything from above PTP, penalty should be applied
        uint256 snapshot = vm.snapshot();
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   9_990.384615384615380000 * 1e18,
                index:    highest,
                newLup:   MAX_PRICE,
                lpRedeem: 10_000 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_lender), 159_990.384615384615380000 * 1e18); // 5 tokens paid as penalty
        vm.revertTo(snapshot);

        // borrower pulls first all their collateral pledged, PTP goes to 0, penalty should be applied
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 100 * 1e18
        });
        assertEq(_quote.balanceOf(_borrower),      19.807692307692298000 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   9_990.384615384615380000 * 1e18,
                index:    highest,
                newLup:   MAX_PRICE,
                lpRedeem: 10_000 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_lender), 159_990.384615384615380000 * 1e18); // 5 tokens paid as penalty

        // lender removes everything from price above PTP after 24 hours, penalty should not be applied
        skip(1 days);
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   10_000 * 1e18,
                index:    med,
                newLup:   MAX_PRICE,
                lpRedeem: 10_000 * 1e27
            }
        );
        assertEq(_quote.balanceOf(_lender), 169_990.384615384615380000 * 1e18); // no tokens paid as penalty
    }
}

contract ERC20PoolBorrowFuzzyTest is ERC20FuzzyHelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

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
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   highest,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   high,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   med,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   low,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:    _lender,
                amount:  10_000 * 1e18,
                index:   lowest,
                lpAward: 10_000 * 1e27,
                newLup:  MAX_PRICE
            }
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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

    function testDrawRepayDebtFuzzy(uint256 numIndexes, uint256 mintAmount_) external tearDown {
        numIndexes = bound(numIndexes, 3, 20); // number of indexes to add liquidity to
        mintAmount_ = bound(mintAmount_, 1 * 1e18, 100_000 * 1e18);

        // lender adds liquidity to random indexes
        changePrank(_lender);
        uint256[] memory indexes = new uint256[](numIndexes);
        for (uint256 i = 0; i < numIndexes; ++i) {
            deal(address(_quote), _lender, mintAmount_);
            indexes[i] = _randomIndex();

            _addLiquidity({
                from:    _lender,
                amount:  mintAmount_,
                index:   indexes[i],
                lpAward: mintAmount_ * 1e9,
                newLup:  _calculateLup(address(_pool), 0)
            });

            _assertBucket({
                index:      indexes[i],
                lpBalance:  mintAmount_ * 1e9,
                collateral: 0,
                deposit:    mintAmount_,
                exchangeRate: 1e27
            });
        }

        // borrower draw a random amount of debt
        changePrank(_borrower);
        uint256 limitIndex = _findLowestIndexPrice(indexes);
        uint256 borrowAmount = Maths.wdiv(mintAmount_, Maths.wad(3));
        uint256 requiredCollateral = _requiredCollateral(Maths.wdiv(mintAmount_, Maths.wad(3)), limitIndex);
        deal(address(_collateral), _borrower, requiredCollateral);
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     borrowAmount,
            limitIndex:         limitIndex,
            collateralToPledge: requiredCollateral,
            newLup:             _calculateLup(address(_pool), borrowAmount)
        });

        // check buckets after borrow
        for (uint256 i = 0; i < numIndexes; ++i) {
            _assertBucket({
                index:        indexes[i],
                lpBalance:    mintAmount_ * 1e9,
                collateral:   0,
                deposit:      mintAmount_,
                exchangeRate: 1e27
            });
        }

        // check borrower info
        (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        assertGt(debt, borrowAmount); // check that initial fees accrued

        // check pool state
        (uint256 minDebt, , uint256 poolActualUtilization, uint256 poolTargetUtilization) = _poolUtils.poolUtilizationInfo(address(_pool));
        _assertPool(
            PoolParams({
                htp:                  Maths.wdiv(debt, requiredCollateral),
                lup:                  _poolUtils.lup(address(_pool)),
                poolSize:             (50_000 * 1e18) + (indexes.length * mintAmount_),
                pledgedCollateral:    requiredCollateral,
                encumberedCollateral: Maths.wdiv(debt, _poolUtils.lup(address(_pool))),
                poolDebt:             debt,
                actualUtilization:    poolActualUtilization,
                targetUtilization:    poolTargetUtilization,
                minDebtAmount:        minDebt,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertLt(_htp(), _poolUtils.lup(address(_pool)));
        assertGt(minDebt, 0);
        assertEq(_poolUtils.lup(address(_pool)), _calculateLup(address(_pool), debt));

        // pass time to allow interest to accumulate
        skip(1 days);

        // repay all debt and withdraw collateral
        (debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        deal(address(_quote), _borrower, debt);
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     debt,
            collateralToPull: requiredCollateral,
            newLup:           _calculateLup(address(_pool), 0)
        });

        // check that deposit and exchange rate have increased as a result of accrued interest
        for (uint256 i = 0; i < numIndexes; ++i) {
            (, uint256 deposit, , uint256 lpAccumulator, , uint256 exchangeRate) = _poolUtils.bucketInfo(address(_pool), indexes[i]);

            // check that only deposits above the htp earned interest
            if (indexes[i] <= _poolUtils.priceToIndex(Maths.wdiv(debt, requiredCollateral))) {
                assertGt(deposit, mintAmount_);
                assertGt(exchangeRate, 1e27);
            } else {
                assertEq(deposit, mintAmount_);
                assertEq(exchangeRate, 1e27);
            }

            assertEq(lpAccumulator, mintAmount_ * 1e9);
            _assertBucket({
                index:        indexes[i],
                lpBalance:    mintAmount_ * 1e9,
                collateral:   0,
                deposit:      deposit,
                exchangeRate: exchangeRate
            });
        }

        // check borrower state after repayment
        (debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        assertEq(debt, 0);

        // check pool state
        assertEq(_htp(), 0);
        assertEq(_poolUtils.lup(address(_pool)), MAX_PRICE);
    }

}
