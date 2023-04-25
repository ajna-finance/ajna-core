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

        // lender deposits 10000 quote in 5 buckets each
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   highest,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   high,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({ 
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   med,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   low,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   lowest,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });

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
                actualUtilization:    0,
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

        _assertLenderLpBalance({
            lender:      _lender,
            index:       highest,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       high,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       med,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       low,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       lowest,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });

        // check buckets
        _assertBucket({
            index:        highest,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        high,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        med,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        low,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        lowest,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // borrow 19_000 quote
        _borrow({
            from:       _borrower,
            amount:     19_000 * 1e18,
            indexLimit: 3_500,
            newLup:     2_951.419442869698640451 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  400.384615384615384800 * 1e18,
                lup:                  2_951.419442869698640451 * 1e18,  // FIMXE: actual is 2_995.912459898389633881,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 13.565832411651963522 * 1e18,
                poolDebt:             40_038.461538461538480000 * 1e18,
                actualUtilization:    0,
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
                actualUtilization:    0,
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

        // borrow 8_000 quote
        _borrow({
            from:       _borrower,
            amount:     8_000 * 1e18,
            indexLimit: 3_500,
            newLup:     3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  80.076923076923076960 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 2.659574720267410143 * 1e18,
                poolDebt:             8_007.692307692307696000 * 1e18,
                actualUtilization:    0,
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

        uint256 expectedDebt = 21_046.123595032677924433 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  420.403846153846154040 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.060070845235984474 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.000000000000000000 * 1e18,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        2_104.612359503267792443 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              441.424038461538461742 * 1e18,
            borrowerCollateralization: 7.082081907682151400 * 1e18
        });

        skip(10 days);

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   10 * 1e18
        });

        expectedDebt = 21_072.086872169016071672 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  351.201447869483601195 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_044.110379805202100000 * 1e18,
                pledgedCollateral:    60 * 1e18,
                encumberedCollateral: 7.068780409975037237 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.420403445225801443 * 1e18,
                targetUtilization:    0.141027440233999772 * 1e18,
                minDebtAmount:        2_107.208687216901607167 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0495 * 1e18,
                interestRateUpdate:   _startTime + 10 days + 10 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        60 * 1e18,
            borrowert0Np:              441.424038461538461742 * 1e18,
            borrowerCollateralization: 8.488027144729466085 * 1e18
        });
        _assertLenderInterest(liquidityAdded, 44.110379805202100000 * 1e18);

        skip(10 days);

        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 10 * 1e18
        });

        expectedDebt = 21_100.683472334824303370 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  422.013669446696486067 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_069.130567554535450000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.078373341528054648 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421070265420802644 * 1e18,
                targetUtilization:    0.120628314442263426 * 1e18,
                minDebtAmount:        2_110.068347233482430337 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05445 * 1e18,
                interestRateUpdate:   _startTime + 30 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              441.213836538461538664 * 1e18,
            borrowerCollateralization: 7.063769822178689107 * 1e18
        });
        _assertLenderInterest(liquidityAdded, 69.130567554535450000 * 1e18);

        skip(10 days);

        // accrue debt and restamp Neutral Price of the loan
        vm.expectEmit(true, true, true, true);
        emit LoanStamped(_borrower);
        _pool.stampLoan();

        expectedDebt = 21_132.184557783880298440 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  422.643691155677605969 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_096.693504733499050000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.088940603188755848 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421430993826609139 * 1e18,
                targetUtilization:    0.138725200998853604 * 1e18,
                minDebtAmount:        2_113.218455778388029844 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.059895 * 1e18,
                interestRateUpdate:   _startTime + 40 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              443.294835576923077127 * 1e18,
            borrowerCollateralization: 7.053240081812639175 * 1e18
        });
        _assertLenderInterest(liquidityAdded, 96.693504733499050000 * 1e18);

        skip(10 days);

        _updateInterest();

        expectedDebt = 21_166.890071570436649845 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  423.337801431408732997 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_127.061165904636850000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.100582812973708010 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421827930356991768 * 1e18,
                targetUtilization:    0.141358334848097873 * 1e18,
                minDebtAmount:        2_116.689007157043664985 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0658845 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              443.294835576923077127 * 1e18,
            borrowerCollateralization: 7.041675495797803839 * 1e18
        });
        _assertLenderInterest(liquidityAdded, 127.061165904636850000 * 1e18);

        skip(10 days);

        expectedDebt = 21_205.131971958652447704 * 1e18;

        _assertPool(
            PoolParams({
                htp:                  423.337801431408732997 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             50_127.061165904636850000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.113411328627820409 * 1e18,
                poolDebt:             expectedDebt,
                actualUtilization:    0.421827930356991768 * 1e18,
                targetUtilization:    0.141358334848097873 * 1e18,
                minDebtAmount:        2_120.513197195865244770 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.0658845 * 1e18,
                interestRateUpdate:   _startTime + 50 days
            })
        );
        assertEq(_poolUtils.momp(address(_pool)), 2_981.007422784467321543 * 1e18);
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              expectedDebt,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              443.294835576923077127 * 1e18,
            borrowerCollateralization: 7.028976350457301320 * 1e18
        });
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
        _assertBorrowLimitIndexRevert({
            from:       _borrower,
            amount:     1_000 * 1e18,
            indexLimit: 1000
        });

        // should revert if borrower tries to borrow on behalf of different address
        _assertBorrowBorrowerNotSenderRevert({
            from:       _borrower,
            borrower:   _borrower2,
            amount:     1 * 1e18,
            indexLimit: 7000
        });

        // should revert if borrower didn't pledged any collateral
        _assertBorrowBorrowerUnderCollateralizedRevert({
            from:       _borrower,
            amount:     500 * 1e18,
            indexLimit: 3000
        });

        // borrower 1 borrows 500 quote from the pool after adding sufficient collateral
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     500 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        // borrower 2 borrows 15k quote from the pool with borrower2 becoming new queue HEAD
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   6 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     15_000 * 1e18,
            indexLimit: 3_000,
            newLup:     2_995.912459898389633881 * 1e18
        });

        // should revert if borrower undercollateralized
        _assertBorrowBorrowerUnderCollateralizedRevert({
            from:       _borrower2,
            amount:     2_976 * 1e18,
            indexLimit: 3000
        });

        // should be able to borrow if properly specified
        _borrow({
            from:       _borrower2,
            amount:     10 * 1e18,
            indexLimit: 3_000,
            newLup:     2_995.912459898389633881 * 1e18
        });

        // skip to make loan undercolalteralized
        skip(10000 days);

        // should not allow borrower to restamp the Neutral Price of the loan if under collateralized
        _assertStampLoanBorrowerUnderCollateralizedRevert({
            borrower: _borrower2
        });
    }

    function testMinBorrowAmountCheck() external tearDown {
        // 10 borrowers draw debt
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(100 * 1e18, 1_200 * 1e18, MAX_FENWICK_INDEX);
        }

        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });

        // should revert if borrower attempts to borrow more than minimum amount
        _assertBorrowMinDebtRevert({
            from:       _borrower,
            amount:     10 * 1e18,
            indexLimit: MAX_FENWICK_INDEX
        });
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
        _assertRepayNoDebtRevert({
            from:     _borrower,
            borrower: _borrower,
            amount:   10_000 * 1e18
        });

        _assertPullBorrowerNotSenderRevert({
            from:     _borrower,
            borrower: _borrower2,
            amount:   10_000 * 1e18
        });

        // borrower 1 borrows 1000 quote from the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     1_000 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                poolDebt:             1_000.961538461538462000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        100.096153846153846200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // borrower 2 borrows 5k quote from the pool and becomes new queue HEAD
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     5_000 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  100.096153846153846200 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 1.994681040200557607 * 1e18,
                poolDebt:             6_005.769230769230772000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                2,
                maxBorrower:          _borrower2,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // should revert if LUP is below the limit
        ( , , , , , uint256 lupIndex ) = _poolUtils.poolPricesInfo(address(_pool));        
        _assertPullLimitIndexRevert({
            from:       _borrower,
            amount:     20 * 1e18,
            indexLimit: lupIndex - 1
        });

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
                actualUtilization:    0,
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
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     1_000 * 1e18,
            limitIndex:         3_000,
            collateralToPledge: 50 * 1e18,
            newLup:             3_010.892022197881557845 * 1e18
        });

        // 9 other borrowers draw debt
        for (uint i=0; i<9; ++i) {
            _anonBorrowerDrawsDebt(100 * 1e18, 1_000 * 1e18, MAX_FENWICK_INDEX);
        }

        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        // should revert if amount left after repay is less than the average debt
        _assertRepayMinDebtRevert({
            from:     _borrower,
            borrower: _borrower,
            amount:   950 * 1e18
        });
    }

    function testRepayLoanFromDifferentActor() external tearDown {
        // borrower 1 borrows 1000 quote from the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     1_000 * 1e18,
            indexLimit: 3_000,
            newLup:     3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 0.332446840033426268 * 1e18,
                poolDebt:             1_000.961538461538462000 * 1e18,
                actualUtilization:    0,
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
                actualUtilization:    0,
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
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   50 * 1e18
        });

        vm.expectRevert(abi.encodeWithSignature('ZeroThresholdPrice()'));
        IERC20Pool(address(_pool)).drawDebt(_borrower, 0.00000000000000001 * 1e18, 3000, 0);

        // borrower 1 borrows 500 quote from the pool after using a non 0 TP
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     500 * 1e18,
            limitIndex:         3_000,
            collateralToPledge: 50 * 1e18,
            newLup:             3_010.892022197881557845 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  5.004807692307692310 * 1e18,
                lup:                  3_010.892022197881557845 * 1e18,
                poolSize:             50_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0.166223420016713134 * 1e18,
                poolDebt:             500.48076923076923100 * 1e18,
                actualUtilization:    0,
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
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        50.048076923076923100 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              500.480769230769231 * 1e18,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              10.510096153846153851 * 1e18,
            borrowerCollateralization: 300.799971477982403259 * 1e18
        });

        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 10_000 * 1e18);

        // should revert if borrower repays most, but not all of their debt resulting in a 0 tp loan remaining on the book
        vm.expectRevert(abi.encodeWithSignature('ZeroThresholdPrice()'));
        IERC20Pool(address(_pool)).repayDebt(_borrower, 500.480769230769231000 * 1e18 - 1, 0, _borrower, MAX_FENWICK_INDEX);

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

    function testPoolBorrowRepayAndRemove() external tearDown {
        // check balances before borrow
        assertEq(_quote.balanceOf(_lender), 150_000 * 1e18);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       highest,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });

        assertEq(_quote.balanceOf(_borrower),      0);
        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);

        // pledge and borrow
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     21_000 * 1e18,
            indexLimit: 3_000,
            newLup:     2_981.007422784467321543 * 1e18
        });

        assertEq(_quote.balanceOf(_borrower),      21_000 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 0);

        _assertPoolPrices({
            htp:      210.201923076923077020 * 1e18,
            htpIndex: 3_083,
            hpb:      3_010.892022197881557845 * 1e18,
            hpbIndex: 2550,
            lup:      2_981.007422784467321543 * 1e18,
            lupIndex: 2_552
        });

        // add liquidity below LUP, ensuring fee is levied
        _addLiquidityWithPenalty({
            from:        _lender,
            amount:      10_000 * 1e18,
            amountAdded: 9_998.630136986301370000 * 1e18,
            index:       _indexOf(200 * 1e18),
            lpAward:     9_998.630136986301370000 * 1e18,
            newLup:      2_981.007422784467321543 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 140_000 * 1e18);

        _removeAllLiquidity({
            from:     _lender,
            amount:   9_998.630136986301370000 * 1e18,
            index:    _indexOf(200 * 1e18),
            newLup:   2_981.007422784467321543 * 1e18,
            lpRedeem: 9_998.630136986301370000 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 149_998.630136986301370000 * 1e18);

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

        _assertPoolPrices({
            htp:      0,
            htpIndex: 7_388,
            hpb:      3_010.892022197881557845 * 1e18,
            hpbIndex: 2550,
            lup:      MAX_PRICE,
            lupIndex: 0
        });

        // lender removes everything from above PTP
        uint256 snapshot = vm.snapshot();

        _removeAllLiquidity({
            from:     _lender,
            amount:   10_000.000000000000000000 * 1e18,
            index:    highest,
            newLup:   MAX_PRICE,
            lpRedeem: 10_000 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 159_998.630136986301370000 * 1e18);

        vm.revertTo(snapshot);

        // borrower pulls first all their collateral pledged, PTP goes to 0
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 100 * 1e18
        });

        assertEq(_quote.balanceOf(_borrower),      19.807692307692298000 * 1e18);
        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);

        _removeAllLiquidity({
            from:     _lender,
            amount:   10_000 * 1e18,
            index:    highest,
            newLup:   MAX_PRICE,
            lpRedeem: 10_000 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 159_998.630136986301370000 * 1e18);

        // lender removes everything from price above PTP after 24 hours
        skip(1 days);

        _removeAllLiquidity({
            from:     _lender,
            amount:   10_000 * 1e18,
            index:    med,
            newLup:   MAX_PRICE,
            lpRedeem: 10_000 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 169_998.630136986301370000 * 1e18);
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

        // lender deposits 10000 quote tokens in 5 buckets each
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   highest,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   high,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   med,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   low,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   lowest,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });

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
                lpAward: mintAmount_,
                newLup:  _calculateLup(address(_pool), 0)
            });

            _assertBucket({
                index:      indexes[i],
                lpBalance:  mintAmount_,
                collateral: 0,
                deposit:    mintAmount_,
                exchangeRate: 1e18
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
                lpBalance:    mintAmount_,
                collateral:   0,
                deposit:      mintAmount_,
                exchangeRate: 1e18
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
                assertGt(exchangeRate, 1e18);
            } else {
                assertEq(deposit, mintAmount_);
                assertEq(exchangeRate, 1e18);
            }

            assertEq(lpAccumulator, mintAmount_);

            _assertBucket({
                index:        indexes[i],
                lpBalance:    mintAmount_,
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

    function testPOCOverCollateralized_SingleBorrower() external {
        // _borrower borrows 1,000 USDC collateralized by 100 eth
        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 1000 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 100 * 1e18,
            newLup:0
        });
        (uint interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18); // 5% initial interest rate

        //pay down a little ($10) every 12 hours to trigger interestRate update
        for (uint index; index < 8; ++index) {
            skip(12.01 hours); // actually needs to be > 12 hours to trigger interestRate update
            _repayDebt({
                from:             _borrower,
                borrower:         _borrower,
                amountToRepay:    10 * 1e18,
                amountRepaid:     10 * 1e18,
                collateralToPull: 0,
                newLup:           0
            });
        }
        (interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.107179440500000000 * 1e18); // interest rate increased over 10% to 10.7%

        // lender can reset interest rate to 10% (even if 12 hours not passed) by triggering any action
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit ResetInterestRate(0.107179440500000000 * 1e18, 0.1 * 1e18);
        _pool.updateInterest();
        (interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.1 * 1e18); // interest rate resetted to 10%
    }

    function testPOCOverCollateralized_MultipleBorrowers_LowDebt() external {

        // 10 borrowers borrow 120 usdc collateralized by 10 eth
        address[] memory otherBorrowers = new address[](10);
        for (uint index; index < 10; ++index) {
            otherBorrowers[index] = address(bytes20(keccak256(abi.encodePacked(index + 0x1000))));
            vm.stopPrank(); // test helper contains a startPrank without a stopPrank

            _mintCollateralAndApproveTokens(otherBorrowers[index],  100 * 1e18);
            _drawDebt({
                from: otherBorrowers[index],
                borrower: otherBorrowers[index],
                amountToBorrow: 120 * 1e18, // borrow 120 usdc
                limitIndex: 3_000,
                collateralToPledge: 10 * 1e18, // collateralized by 10 eth
                newLup:0
            });
        }

        (uint interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.05 * 1e18); // 5% initial interest rate

        //pay down a little ($1) every 12 hours to trigger interestRate update
        for (uint index; index < 8; ++index) {
            skip(12.01 hours); // actually needs to be > 12 hours to trigger interestRate update
            _repayDebt({
                from:             otherBorrowers[0],
                borrower:         otherBorrowers[0],
                amountToRepay:    1 * 1e18,
                amountRepaid:     1 * 1e18,
                collateralToPull: 0,
                newLup:           0
            });
        }
        (interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.107179440500000000 * 1e18); // interest rate increased over 10% to 10.7%

        // lender can reset interest rate to 10% (even if 12 hours not passed) by triggering any action
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit ResetInterestRate(0.107179440500000000 * 1e18, 0.1 * 1e18);
        _pool.updateInterest();
        (interestRate,) = _pool.interestRateInfo();
        assertEq(interestRate, 0.1 * 1e18); // interest rate resetted to 10%
    }

}
