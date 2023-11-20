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
    address internal _attacker;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _attacker  = makeAddr("attacker");

        _mintCollateralAndApproveTokens(_borrower,  1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  1_000 * 1e18);
        _mintCollateralAndApproveTokens(_attacker,  11_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_attacker, 2_000_000 * 1e18);

        // fund reserves
        deal(address(_quote), address(_pool), 50 * 1e18);

        // lender deposits 1_000 quote in price of 1.0
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  4156 // 1.000000000000000000 
        });

    }

    function testStealReservesWithMargin() external {

        // Pool's reserves are already seeded with 50 quote token in setUp()

        // assert attacker's balances
        assertEq(2_000_000.0 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.0 * 1e18, _collateral.balanceOf(address(_attacker)));

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

        _assertReserveAuction({
            reserves:                   50.048076923076923100 * 1e18,
            claimableReserves :         49.797836438461538485 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
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

        // Attacker does the following in quick succession (ideally same block):

        // deposits 100 quote token at price 100
        _addLiquidity({
            from:    _attacker,
            amount:  100.0 * 1e18,
            index:   3232,
            lpAward: 100 * 1e18,
            newLup:  100.332368143282009890 * 1e18
        });

        // deposits 100 quote token at price 100.5
        _addLiquidity({
            from:    _attacker,
            amount:  100.0 * 1e18,
            index:   3231,
            lpAward: 100 * 1e18,
            newLup:  100.834029983998419124 * 1e18
        });

        // 2b. posts 1.04 collateral and borrows 99.9 quote token
        _pledgeCollateral({
            from:     _attacker,
            borrower: _attacker,
            amount:   1.04 * 1e18
        });

        _borrow({
            from:       _attacker,
            amount:     99.9 * 1e18,
            indexLimit: 7388,
            newLup:     100332368143282009890
        });

        // 2c. lenderKicks the loan in 2b using deposit in 2a
        _lenderKick({
            from:       _attacker,
            index:      3232,
            borrower:   _attacker,
            debt:       99.996057692307692354 * 1e18,
            collateral: 1.040000000000000000 * 1e18,
            bond:       1.517974143179184468 * 1e18
        });

        // 2d. withdraws 100 of the deposit from 2a
        _removeLiquidity({
            from:     _attacker,
            amount:   100.0 * 1e18,
            index:    3232,
            newLup:   1.000000000000000000 * 1e18,
            lpRedeem: 100.0 * 1e18
        });

        // Now wait until auction price drops to about $50
        skip(8 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _attacker,
                active:            true,
                kicker:            _attacker,
                bondSize:          1.517974143179184468 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 8 hours,
                referencePrice:    110.745960696249555227 * 1e18,
                totalBondEscrowed: 1.517974143179184468 * 1e18,
                auctionPrice:      55.372980348124777612 * 1e18,
                debtInAuction:     99.996057692307692354 * 1e18,
                thresholdPrice:    96.154445987103992600 * 1e18,
                neutralPrice:      110.745960696249555227 * 1e18
            })
        );

        _assertBucket({
            index:        3231,
            lpBalance:    100.0 * 1e18,
            collateral:   0 * 1e18,
            deposit:      100.000000000000000000 * 1e18,
            exchangeRate: 1.0 * 1e18
        });

        // In a single block finish the attack:

        // 2a. Call arbtake using 100.5 price bucket
        _arbTake({
            from:             _attacker,
            borrower:         _attacker,
            kicker:           _attacker,
            index:            3231,
            collateralArbed:  1.040000000000000000 * 1e18,
            quoteTokenAmount: 57.587899562049768716 * 1e18,
            bondChange:       0.874203888759067303 * 1e18,
            isReward:         true,
            lpAwardTaker:     47.278114938447149620 * 1e18,
            lpAwardKicker:    0.874178433715669284 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    148.152293372162818904 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      43.289216208587901186 * 1e18,
            exchangeRate: 1.000029118818786027 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.145162338400592905 * 1e18,
            claimableReserves :         49.678475742964129332 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 43.284951626362185652 * 1e18
        });

        _assertBucket({
            index:        3232,
            lpBalance:    0 * 1e18,
            collateral:   0,
            deposit:      0 * 1e18,
            exchangeRate: 1 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    148.152293372162818904 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      0.050319094592365857 * 1e18,
            exchangeRate: 0.708174729461625128 * 1e18
        });

        // 2c. Withdraw the deposit remaing (should be about 50)
        //     the collateral moved (should be 1.04) from the 100 price bucket (all go to the attacker)

        _removeAllLiquidity({
            from:     _attacker,
            amount:   0.050319094592365857 * 1e18,
            index:    3231,
            newLup:   1.0 * 1e18,
            lpRedeem: 0.071054631715847706 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 1.040000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 148.081238740446971198 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.097131299098677341 * 1e18,
            claimableReserves :         49.846879387717917230 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(1_999_998.432344951413181389 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.0 * 1e18, _collateral.balanceOf(address(_attacker)));

    }

       function testSpendOrigFeePushBadDebtToBorrowers() external {
        // Starts like the other test:  For background, set up a nice normal looking pool with some reserves.
        // Pool's reserves are already seeded with 50 quote token in setUp()

        // assert attacker's balances

        assertEq(2_000_000.0 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.0 * 1e18, _collateral.balanceOf(address(_attacker)));

        // 1a. Deposit 100 qt at a price of 1
        _removeLiquidity({
            from:     _lender,
            amount:   900.0 * 1e18,
            index:    4156,
            newLup:   1004968987.606512354182109771 * 1e18,
            lpRedeem: 900.0 * 1e18
        });

        // 1b. Legit borrower posts 75 collateral and borrows 50 quote token
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

        // Like other attack, but bigger: Attacker does the following in quick succession (ideally same block):
        // 2a. deposits 100 quote token at price 100

        // deposits 100 quote token at price 100
        _addLiquidity({
            from:    _attacker,
            amount:  100.0 * 1e18,
            index:   3232,
            lpAward: 100 * 1e18,
            newLup:  100.332368143282009890 * 1e18
        });

        // 2aa. deposits 1,000,000 quote token at price 100.5
        _addLiquidity({
            from:    _attacker,
            amount:  1_000_000.0 * 1e18,
            index:   3231,
            lpAward: 1_000_000 * 1e18,
            newLup:  100.834029983998419124 * 1e18
        });

        // 2b. posts 10,400 collateral and borrows ~999,000 quote token
        _pledgeCollateral({
            from:     _attacker,
            borrower: _attacker,
            amount:   10_400.0 * 1e18
        });

        _borrow({
            from:       _attacker,
            amount:     999_000.0 * 1e18,
            indexLimit: 7388,
            newLup:     100.332368143282009890 * 1e18
        });

        // 2c. lenderKicks the loan in 2b using deposit in 2a
        _lenderKick({
            from:       _attacker,
            index:      3232,
            borrower:   _attacker,
            debt:       999_960.576923076923538000 * 1e18,
            collateral: 10_400.000000000000000000 * 1e18,
            bond:       15_179.741431791844683088 * 1e18
        });

        // 2d. withdraws 100 of the deposit from 2a
        _removeLiquidity({
            from:     _attacker,
            amount:   100.0 * 1e18,
            index:    3232,
            newLup:   1.000000000000000000 * 1e18,
            lpRedeem: 100.0 * 1e18
        });

        // There now is a loan for about 1,000,000 quote token in auction
        // Now wait until auction price drops to about $50
        skip(8 hours);

        // In a single block finish the attack:
        // 2a. Call arbtake using 100.5 price bucket --> FIXME: 100.5 price bucket?
        _arbTake({
            from:             _attacker,
            borrower:         _attacker,
            kicker:           _attacker,
            index:            3231,
            collateralArbed:  10_400.000000000000000000 * 1e18,
            quoteTokenAmount: 575_878.995620497687164800 * 1e18,
            bondChange:       8_742.038887590673028366 * 1e18,
            isReward:         true,
            lpAwardTaker:     472_776.567658562419195962 * 1e18,
            lpAwardKicker:    8_741.699620454596618603 * 1e18
        });


        _assertBucket({
            index:        3231,
            lpBalance:    1_481_518.267279017015814565 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      432_901.853470006222863200 * 1e18,
            exchangeRate: 1.000038810202913237 * 1e18
        });

        _assertReserveAuction({
            reserves:                   1_017.474544223564376176 * 1e18,
            claimableReserves :         0 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 432_849.516263621856515769 * 1e18
        });

        _assertBucket({
            index:        3232,
            lpBalance:    0 * 1e18,
            collateral:   0,
            deposit:      0 * 1e18,
            exchangeRate: 1 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    1_481_518.267279017015814565 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      512.882330050869566761 * 1e18,
            exchangeRate: 0.708183501571391142 * 1e18
        });

        // 2c. Withdraw the deposit remaing (should be about 500,000) and the collateral moved (should be 10,400) from the 100 price bucket (all go to the attacker)
        _removeAllLiquidity({
            from:     _attacker,
            amount:   512.882330050869566761 * 1e18, // FIXME: ... this should be 500K per Matts example? 
            index:    3231,
            newLup:   1.0 * 1e18,
            lpRedeem: 724.222364560644181046 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 10_400.000000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 1_480_794.044914456371633519 * 1e18
        });

        _assertReserveAuction({
            reserves:                   537.164151204408755337 * 1e18,
            claimableReserves :         536.913899293027026088 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(1_984_333.140898259024883673 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.000000000000000000 * 1e18, _collateral.balanceOf(address(_attacker)));
        // End result: attack is out the origination fee (should be about 1000), but pushed a small amount of bad debt (should be small amount with these paramters, but could be made a bit larger by waiting longer and making bigger loan) that get pushed to the legit borrower at price of 1.  This can be measured by looking at the exchange rate of that bucket
    }

}