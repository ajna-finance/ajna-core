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
        _mintCollateralAndApproveTokens(_attacker,  11_000 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_attacker, 2_000_000 * 1e18);

        // fund reserves
        deal(address(_quote), address(_pool), 50 * 1e18);

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

        // Pool's reserves are already seeded with 50 quote token in setUp()

        // assert attacker's balances
        assertEq(200_000.0 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(10 * 1e18, _collateral.balanceOf(address(_attacker)));

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
            claimableReserves :         50.048076823076923100 * 1e18,
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
            bond:       1.117989912409953699 * 1e18
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
                bondSize:          1.117989912409953699 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 8 hours,
                referencePrice:    106.899958477314643983 * 1e18,
                totalBondEscrowed: 1.117989912409953699 * 1e18,
                auctionPrice:      53.449979238657321992 * 1e18,
                debtInAuction:     99.996057692307692354 * 1e18,
                thresholdPrice:    96.154445987103992600 * 1e18,
                neutralPrice:      106.899958477314643983 * 1e18
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

        // 2a. Call arbtake using 100.5 price bucket --> FIXME: 100.5 price bucket?
        _arbTake({
            from:             _attacker,
            borrower:         _attacker,
            kicker:           _attacker,
            index:            3231,
            collateralArbed:  1.040000000000000000 * 1e18,
            quoteTokenAmount: 55.587978408203614872 * 1e18,
            bondChange:       0.621492492262669154 * 1e18,
            isReward:         true,
            lpAwardTaker:     49.277977858647333263 * 1e18,
            lpAwardKicker:    0.621474395662361706 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    149.899452254309694969 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      45.036425965937656883 * 1e18,
            exchangeRate: 1.000029118818786027 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.145162338400592903 * 1e18,
            claimableReserves :         50.145162193361255055 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 45.032081604265944855 * 1e18
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
            lpBalance:    149.899452254309694969 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      0.002288055290450296 * 1e18,
            exchangeRate: 0.699600149710578699 * 1e18
        });

        // 2c. Withdraw the deposit remaing (should be about 50)
        //     the collateral moved (should be 1.04) from the 100 price bucket (all go to the attacker)

        _removeAllLiquidity({
            from:     _attacker,
            amount:   0.002288055290450296 * 1e18,
            index:    3231,
            newLup:   1.0 * 1e18,
            lpRedeem: 0.003270518583217648 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 1.040000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 149.896181735726477321 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.145162338400592902 * 1e18,
            claimableReserves :         50.145162238397681020 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(199_998.784298142880496597 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(10 * 1e18, _collateral.balanceOf(address(_attacker)));
    }

    // Griefing attempt where someone spends orig fee to cause bad debt to get pushed to book.  This will work in branch with reserves not used for bad debt, but fail if reserves are used, as well as fail in settle-half-originationfee-reserves

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
            debt:       999960.576923076923538000 * 1e18,
            collateral: 10_400.000000000000000000 * 1e18,
            bond:       11179.899124099536988936 * 1e18
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
            quoteTokenAmount: 555_879.784082036148716800 * 1e18,
            bondChange:       6_214.924922626691540182 * 1e18,
            isReward:         true,
            lpAwardTaker:     492_775.003053688325546576 * 1e18,
            lpAwardKicker:    6_214.683729490108436591 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    1_498_989.686783178433983167 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      450_373.951043503779827200 * 1e18,
            exchangeRate: 1.000038810202913238 * 1e18
        });

        _assertReserveAuction({
            reserves:                   1_017.474544223564365776 * 1e18,
            claimableReserves :         1_017.474093749609441252 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 450_320.816042659448546281 * 1e18
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
            lpBalance:    1_498_989.686783178433983167 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      32.571937031713956323 * 1e18,
            exchangeRate: 0.699608871907005698 * 1e18
        });

        // 2c. Withdraw the deposit remaing (should be about 500,000) and the collateral moved (should be 10,400) from the 100 price bucket (all go to the attacker)
        _removeAllLiquidity({
            from:     _attacker,
            amount:   32.571937031713956323 * 1e18, // FIXME: ... this should be 500K per Matts example? 
            index:    3231,
            newLup:   1.0 * 1e18,
            lpRedeem: 46.557352743296149701 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 10_400.000000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 1_498_943.129430435137833466 * 1e18
        });

        _assertReserveAuction({
            reserves:                   1_017.474544223564365775 * 1e18,
            claimableReserves :         1_017.474544123560484755 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(1_987_852.672812932176967387 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.000000000000000000 * 1e18, _collateral.balanceOf(address(_attacker)));
        // End result: attack is out the origination fee (should be about 1000), but pushed a small amount of bad debt (should be small amount with these paramters, but could be made a bit larger by waiting longer and making bigger loan) that get pushed to the legit borrower at price of 1.  This can be measured by looking at the exchange rate of that bucket
    }


}