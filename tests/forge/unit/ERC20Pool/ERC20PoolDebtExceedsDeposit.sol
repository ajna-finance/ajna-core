// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract  } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';
import '@std/console.sol';

import 'src/ERC20Pool.sol';

import '@std/console.sol';

contract ERC20PoolBorrowTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _attacker;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _attacker  = makeAddr("attacker");

        _mintCollateralAndApproveTokens(_borrower,  1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  1_000 * 1e18);
        _mintCollateralAndApproveTokens(_attacker,  10 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_attacker, 200_000 * 1e18);


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

        skip(500 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           1_062.275580978447336880 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           11.876602049529453524 * 1e18,
            transferAmount: 11.876602049529453524 * 1e18
        });

        skip(73 hours);

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             1_059.774376990334082000 * 1e18,
                pledgedCollateral:    1_000.000000000000000000 * 1e18,
                encumberedCollateral: 10_645_053_462.679700356660584401 * 1e18,
                poolDebt:             1_062.762568879264622268 * 1e18,
                actualUtilization:    0.991952784519230770 * 1e18,
                targetUtilization:    0.991952784519230770 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   block.timestamp - 73 hours
            })
        );

        // 7388 bankrupts then settle emit occurs
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(7388, 0);

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 989.604567844708659388 * 1e18
        });

        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(7388, 0);

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          11.876602049529453524 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 73 hours,
                referencePrice:    1.181041601473741876 * 1e18,
                totalBondEscrowed: 11.876602049529453524 * 1e18,
                auctionPrice:      0,
                debtInAuction:     2.515842310488378269 * 1e18,
                thresholdPrice:    0 * 1e18,
                neutralPrice:      1.181041601473741876 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              2.515842310488378269 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        // Pool is burned, actors are able to interact with pool
        changePrank(_lender);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        _pool.addQuoteToken(1_000 * 1e18, 4160, type(uint256).max, false);
    }


    function testStealReservesWithMargin() external {

        // Deposit 100 qt at a price of 1
        _removeLiquidity({
            from:     _lender,
            amount:   900.0 * 1e18,
            index:    4156,
            newLup:   1004968987.606512354182109771 * 1e18,
            lpRedeem: 900.0 * 1e18
        });

        // 1b. Legit borrower posts 75 collateral and borrows 50 quote token
        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   75.0 * 1e18
        });

        _borrow({
            from:       _borrower,
            amount:     50.0 * 1e18,
            indexLimit: 7388,
            newLup:     1.0 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  667307692307692308,
                lup:                  1 * 1e18,
                poolSize:             100.0 * 1e18,
                pledgedCollateral:    75.000000000000000000 * 1e18,
                encumberedCollateral: 50048076923076923100,
                poolDebt:             50.048076923076923100 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        5004807692307692310,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // 50 quote token to the pool address, just to create a bunch of reserves.
        deal(address(_quote), address(_pool), 50.0 * 1e18);

        _assertPool(
            PoolParams({
                htp:                  667307692307692308,
                lup:                  1 * 1e18,
                poolSize:             100.0 * 1e18,
                pledgedCollateral:    75.000000000000000000 * 1e18,
                encumberedCollateral: 50048076923076923100,
                poolDebt:             50.048076923076923100 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        5004807692307692310,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // Attacker does the following in quick succession (ideally same block):
        console.log(_indexOf(100.0 * 1e18), "price");

        // 2a. deposits 200 quote token at price 100

        _addLiquidity({
            from:    _attacker,
            amount:  200.0 * 1e18,
            index:   3232,
            lpAward: 200 * 1e18,
            newLup:  100.332368143282009890 * 1e18
        });

        // 2b. posts 1.04 collateral and borrows 100 quote token
        _pledgeCollateral({
            from:     _attacker,
            borrower: _attacker,
            amount:   1.04 * 1e18
        });

        _borrow({
            from:       _attacker,
            amount:     100.0 * 1e18,
            indexLimit: 7388,
            newLup:     100332368143282009890
        });

        // 2c. lenderKicks the loan in 2b using deposit in 2a
        _lenderKick({
            from:       _attacker,
            index:      3232,
            borrower:   _attacker,
            debt:       100.096153846153846200 * 1e18,
            collateral: 1.040000000000000000 * 1e18,
            bond:       1.119109021431385084 * 1e18
        });

        // 2d. withdraws 100 of the deposit from 2a
        _removeLiquidity({
            from:     _lender,
            amount:   10.0 * 1e18,
            index:    3232,
            newLup:   1004968987.606512354182109771 * 1e18,
            lpRedeem: 100.0 * 1e18
        });

        // Now wait until auction price drops to about $50

        // In a single block finish the attack:
        // 2a. Call arbtake using 100 price bucket
        // 2b. Call settle
        // 2c. Withdraw the deposit remaing (should be about 50) and the collateral moved (should be 1.04) from the 100 price bucket (all go to the attacker)




    }







}