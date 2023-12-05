// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract  } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';
import '@std/console.sol';

import 'src/ERC20Pool.sol';

contract ERC20PoolDebtExceedsDepositTest is ERC20HelperContract {

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

        // lender deposits 100 quote in price of 1.0
        _addInitialLiquidity({
            from:   _lender,
            amount: 100 * 1e18,
            index:  4156 // 1.000000000000000000 
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

        // assert prices used in the attacks
        assertEq(_priceAt(3231), 100.834029983998419124 * 1e18);
        assertEq(_priceAt(3232), 100.332368143282009890 * 1e18);
    }

    function testStealReservesWithMargin() external tearDown {
        // Pool's reserves are already seeded with 50 quote token in setUp()

        // assert attacker's balances
        assertEq(2_000_000.0 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.0 * 1e18, _collateral.balanceOf(address(_attacker)));

        _assertPool(
            PoolParams({
                htp:                  0.694000000000000000 * 1e18,
                lup:                  1 * 1e18,
                poolSize:             99.995433789954337900 * 1e18,
                pledgedCollateral:    75.000000000000000000 * 1e18,
                encumberedCollateral: 52.050000000000000024   * 1e18,
                poolDebt:             50.048076923076923100 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        5.004807692307692310 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        _assertReserveAuction({
            reserves:                   50.052643133122585200 * 1e18,
            claimableReserves :         50.052643033127151410 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        _assertPool(
            PoolParams({
                htp:                  0.694000000000000000 * 1e18,
                lup:                  1 * 1e18,
                poolSize:             99.995433789954337900 * 1e18,
                pledgedCollateral:    75.000000000000000000 * 1e18,
                encumberedCollateral: 52.050000000000000024 * 1e18,
                poolDebt:             50.048076923076923100 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        5.004807692307692310 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // Attacker does the following in quick succession (ideally same block):

        // 2a. deposits 100 quote token at price 100
        _addLiquidity({
            from:    _attacker,
            amount:  100 * 1e18,
            index:   3232,
            lpAward: 99.995433789954337900 * 1e18,
            newLup:  100.332368143282009890 * 1e18
        });

        // deposits 100 quote token at price 100.5
        _addLiquidity({
            from:    _attacker,
            amount:  100 * 1e18,
            index:   3231,
            lpAward: 99.995433789954337900 * 1e18,
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
            amount:     98.7 * 1e18,
            indexLimit: 7388,
            newLup:     100332368143282009890
        });

        // 2c. lenderKicks the loan in 2b using deposit in 2a
        _lenderKick({
            from:       _attacker,
            index:      3232,
            borrower:   _attacker,
            debt:       98.794903846153846199 * 1e18,
            collateral: 1.040000000000000000 * 1e18,
            bond:       1.104560604152777078 * 1e18
        });

        // 2d. withdraws 100 of the deposit from 2a
        _removeLiquidity({
            from:     _attacker,
            amount:   99.995433789954337900 * 1e18,
            index:    3232,
            newLup:   1.000000000000000000 * 1e18,
            lpRedeem: 99.995433789954337900 * 1e18
        });

        // Now wait until auction price drops to about $50
        skip(8 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _attacker,
                active:            true,
                kicker:            _attacker,
                bondSize:          1.104560604152777078 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 8 hours,
                referencePrice:    105.615874892001555166 * 1e18,
                totalBondEscrowed: 1.104560604152777078 * 1e18,
                auctionPrice:      52.807937446000777584 * 1e18,
                debtInAuction:     98.794903846153846199 * 1e18,
                thresholdPrice:    94.995099852071005961 * 1e18,
                neutralPrice:      105.615874892001555166 * 1e18
            })
        );

        _assertBucket({
            index:        3231,
            lpBalance:    99.995433789954337900 * 1e18,
            collateral:   0 * 1e18,
            deposit:      99.995433789954337900 * 1e18,
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
            quoteTokenAmount: 54.920254943840808687 * 1e18,
            bondChange:       0.276456513923769287 * 1e18,
            isReward:         true,
            lpAwardTaker:     49.945693456678679159 * 1e18,
            lpAwardKicker:    0.276448528146325115 * 1e18
        });

        _assertBucket({
            index:        3231,
            lpBalance:    150.217575774779342174 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      45.354523931320475267 * 1e18,
            exchangeRate: 1.000028887031874320 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.579662148935341151 * 1e18,
            claimableReserves :         50.579662003582494858 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 44.577579955878023186 * 1e18
        });

        _assertBucket({
            index:        3232,
            lpBalance:    0 * 1e18,
            collateral:   0,
            deposit:      0 * 1e18,
            exchangeRate: 1 * 1e18
        });

        uint256 depositRemaining = 0.824443694255901374 * 1e18;
        _assertBucket({
            index:        3231,
            lpBalance:    150.217575774779342174 * 1e18,
            collateral:   1.040000000000000000 * 1e18,
            deposit:      depositRemaining,
            exchangeRate: 0.703591669167112881 * 1e18
        });

        // 2c. Withdraw the deposit remaing (should be about 50)
        //     the collateral moved (should be 1.04) from the 100 price bucket (all go to the attacker)
        _removeAllLiquidity({
            from:     _attacker,
            amount:   depositRemaining,
            index:    3231,
            newLup:   1.0 * 1e18,
            lpRedeem: 1.171764434379743124 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 1.040000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 149.045811340399599050 * 1e18
        });

        _assertReserveAuction({
            reserves:                   50.532162430121891858 * 1e18,
            claimableReserves :         50.532162330123569497 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(_quote.balanceOf(address(_attacker)),      1_999_998.415316880057462196 * 1e18);
        assertEq(_collateral.balanceOf(address(_attacker)), 11_000.0 * 1e18);
    }

    function testSpendOrigFeePushBadDebtToBorrowers() external tearDown {
        // Starts like the other test:  For background, set up a nice normal looking pool with some reserves.
        // Pool's reserves are already seeded with 50 quote token in setUp()

        // assert attacker's balances
        assertEq(2_000_000.0 * 1e18, _quote.balanceOf(address(_attacker)));
        assertEq(11_000.0 * 1e18, _collateral.balanceOf(address(_attacker)));

        // Like other attack, but bigger: Attacker does the following in quick succession (ideally same block):

        // 2a. deposits 100 quote token at price 100.3
        _addLiquidity({
            from:    _attacker,
            amount:  100.0 * 1e18,
            index:   3232,
            lpAward: 99.995433789954337900 * 1e18,
            newLup:  100.332368143282009890 * 1e18
        });

        // 2aa. deposits 1,000,000 quote token at price 100.8
        _addLiquidity({
            from:    _attacker,
            amount:  1_000_000.0 * 1e18,
            index:   3231,
            lpAward: 999_954.337899543379000000 * 1e18,
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
            amount:     998_980.0 * 1e18,
            indexLimit: 7388,
            newLup:     100.332368143282009890 * 1e18
        });

        // 2c. lenderKicks the loan in 2b using deposit in 2a
        _lenderKick({
            from:       _attacker,
            index:      3232,
            borrower:   _attacker,
            debt:       999_940.557692307692768760 * 1e18,
            collateral: 10_400.000000000000000000 * 1e18,
            bond:       11_179.675302295250711919 * 1e18
        });

        // 2d. withdraws 100 of the deposit from 2a
        _removeAllLiquidity({
            from:     _attacker,
            amount:   99.9954337899543379 * 1e18,
            index:    3232,
            newLup:   1.000000000000000000 * 1e18,
            lpRedeem: 99.9954337899543379 * 1e18
        });

        // There now is a loan for about 1,000,000 quote token in auction
        _assertBorrower({
            borrower:                  _attacker,
            borrowerDebt:              999_940.557692307692768760 * 1e18,
            borrowerCollateral:        10_400 * 1e18,
            borrowert0Np:              106.897818338005788835 * 1e18,
            borrowerCollateralization: 0.010000594458412903 * 1e18
        });

        // Now wait until auction price drops to about $50
        skip(8 hours + 10 minutes);
        _assertAuction(
            AuctionParams({
                borrower:          _attacker,
                active:            true,
                kicker:            _attacker,
                bondSize:          11_179.675302295250711919 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 8 hours - 10 minutes,
                referencePrice:    106.897818338005788835 * 1e18,
                totalBondEscrowed: 11_179.675302295250711919 * 1e18,
                auctionPrice:      50.449052405478872444 * 1e18,
                debtInAuction:     999_940.55769230769276876 * 1e18,
                thresholdPrice:    96.148130547337278151 * 1e18,
                neutralPrice:      106.897818338005788835 * 1e18
            })
        );

        // In a single block finish the attack:
        // 2a. Call arbtake using 100.8 price bucket
        _arbTake({
            from:             _attacker,
            borrower:         _attacker,
            kicker:           _attacker,
            index:            3231,
            collateralArbed:  10_400.000000000000000000 * 1e18,
            quoteTokenAmount: 524_670.145016980273417600 * 1e18,
            bondChange:       3_308.944954975446157085 * 1e18,
            isReward:         true,
            lpAwardTaker:     523_983.006723242908178800 * 1e18,
            lpAwardKicker:    3_308.813860486169934000 * 1e18
        });

        // borrower now has bad debt
        _assertBorrower({
            borrower:                  _attacker,
            borrowerDebt:              481_822.276333990032709282 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertBucket({
            index:        3231,
            lpBalance:    1_527_246.158483272457112800 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      478_632.755812061670839884 * 1e18,
            exchangeRate: 1.000039619783645660 * 1e18
        });

        _assertReserveAuction({
            reserves:                   4_259.576102439190468307 * 1e18,
            claimableReserves :         1_120.0045662100456621 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // 2b. Call settle
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 479_213.518269861612655464 * 1e18
        });

        _assertBucket({
            index:        3232,
            lpBalance:    0 * 1e18,
            collateral:   0,
            deposit:      0 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // 2c. There is no deposit remaing to withdraw
        _assertBucket({
            index:        3231,
            lpBalance:    1_527_246.158483272457112800 * 1e18,
            collateral:   10_400.000000000000000000 * 1e18,
            deposit:      0,
            exchangeRate: 0.686643672998356028 * 1e18
        });

        // wait for auction to end and settle again
        skip(16 hours);
        _settle({
            from:        _attacker,
            borrower:    _attacker,
            maxDepth:    10,
            settledDebt: 2_608.996317752997907862 * 1e18
        });

        _removeAllCollateral({
            from: _attacker,
            amount: 10_400.000000000000000000 * 1e18,
            index: 3231,
            lpRedeem: 1_527_246.158483272457112800 * 1e18
        });

        _assertReserveAuction({
            reserves:                   1_170.059547120642975304 * 1e18,
            claimableReserves :         1_120.004566210045662100 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // assert attacker's balances
        // attacker does not profit in QT
        assertEq(_quote.balanceOf(address(_attacker)),      1_987_800.320131494703625981 * 1e18);
        assertEq(_collateral.balanceOf(address(_attacker)), 11_000.000000000000000000 * 1e18);
        // End result: attack is out the origination fee (should be about 1000), but pushed a small amount of bad debt (should be small amount with these paramters, but could be made a bit larger by waiting longer and making bigger loan) that get pushed to the legit borrower at price of 1.  This can be measured by looking at the exchange rate of that bucket
    }
}