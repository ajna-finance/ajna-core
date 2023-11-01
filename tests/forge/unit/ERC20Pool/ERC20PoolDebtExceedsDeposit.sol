// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract  } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';
import '@std/console.sol';

import 'src/ERC20Pool.sol';

contract ERC20PoolBorrowTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintCollateralAndApproveTokens(_borrower,  1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  1_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);


        // lender deposits 1_000 quote in price of 1.0
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  4156
        });

    }

    function testDebtExceedsDepositSettle() external {

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     990.9999 * 1e18,
            indexLimit: 7388,
            newLup:     1.0 * 1e18
        });

        skip(150 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_012.546227883006932020 * 1e18,
            borrowerCollateral:        1_000.0 * 1e18,
            borrowert0Np:              1.102856477351990821 * 1e18,
            borrowerCollateralization: 0.000000098599234426 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           1_012.546227883006932019 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           11.320610979536981887 * 1e18,
            transferAmount: 11.320610979536981887 * 1e18
        });

        skip(73 hours);

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 991.952784519230769688 * 1e18
        });

        // Settle, settles debt successfully.

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0 * 1e18,
            borrowerCollateral:        0 * 1e18,
            borrowert0Np:              0 * 1e18,
            borrowerCollateralization: 1.0 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  1_004_968_987.606512354182109771 * 1e18,
                poolSize:             4.944245932031523809 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.745136886473306591 * 1e18,
                targetUtilization:    0.991952784519230770 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0495 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // Pool seems fine, actors are able to interact with the pool
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  4160
        });

        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     200.0 * 1e18,
            indexLimit: 7388,
            newLup:     0.980247521701303221 * 1e18
        });
    }
}