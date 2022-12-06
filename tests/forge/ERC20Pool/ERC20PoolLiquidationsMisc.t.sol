// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/base/PoolHelper.sol';
import 'src/erc20/interfaces/IERC20Pool.sol';

contract ERC20PoolLiquidationsTakeTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintQuoteAndApproveTokens(_lender,  120_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender1,   4 * 1e18);

        // Lender adds Quote token accross 5 prices
        _addLiquidity(
            {
                from:   _lender,
                amount: 2_000 * 1e18,
                index:  _i9_91,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  _i9_81,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  _i9_72,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i9_62,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  _i9_52,
                newLup: MAX_PRICE
            }
        );

        // first borrower adds collateral token and borrows
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   2 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     19.25 * 1e18,
                indexLimit: _i9_91,
                newLup:     9.917184843435912074 * 1e18
            }
        );

        // second borrower adds collateral token and borrows
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   1_000 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     7_980 * 1e18,
                indexLimit: _i9_72,
                newLup:     9.721295865031779605 * 1e18
            }
        );

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolState({
                htp:                  9.634254807692307697 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 823.649613971736296163 * 1e18,
                poolDebt:             8_006.941586538461542154 * 1e18,
                actualUtilization:    0.109684131322444679 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        400.347079326923077108 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.268509615384615394 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 1.009034539679184679 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              8.471136974495192173 * 1e18,
                borrowerCollateralization: 1.217037273735858713 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   7.691586538461542154 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );
        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        // should revert if there's no auction started
        _assertTakeNoAuctionRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 10 * 1e18
            }
        );
    }


    function testLenderForcedExit() external tearDown {

        skip(25 hours);
        
        // Lender attempts to withdraw entire position
        _removeLiquidity(
            {
                from:     _lender,
                amount:   2_000.00 * 1e18,
                index:    _i9_91,
                penalty:  0,
                newLup:   9.721295865031779605 * 1e18,
                lpRedeem: 1999891367962935869240493669537
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   5_000 * 1e18,
                index:    _i9_81,
                penalty:  0,
                newLup:   9.721295865031779605 * 1e18,
                lpRedeem: 4999728419907339673101234173842
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   2_992.8 * 1e18,
                index:    _i9_72,
                penalty:  0,
                newLup:   9721295865031779605,
                lpRedeem: 2992637443019737234731474727095
            }
        );

        // Lender amount to withdraw is restricted by HTP 
        _assertRemoveAllLiquidityLupBelowHtpRevert(
            {
                from:     _lender,
                index:    _i9_72
            }
        );

        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    8_007.362556980262765268525272905 * 1e27, 
                collateral:   0,
                deposit:      8_007.797508658144068000 * 1e18,
                exchangeRate: 1.000054318968922188000000000 * 1e27
            }
        );

        skip(16 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.636421658861206949 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.272843317722413898 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.998794730435100101 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           19.489662805046791054 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.192728433177224139 * 1e18,
                transferAmount: 0.192728433177224139 * 1e18
            }
        );

        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    8_007.362556980262765268525272905 * 1e27,
                collateral:   0,          
                deposit:      8_008.361347558277120605 * 1e18,
                exchangeRate: 1.000124734027079076000086027 * 1e27
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.192728433177224139 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.192728433177224139 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     19.489662805046791054 * 1e18,
                thresholdPrice:    9.744831402523395527 * 1e18,
                neutralPrice:      10.118242741804267296 * 1e18
            })
        );

        // lender cannot withdraw
        _assertRemoveDepositLockedByAuctionDebtRevert(
            {
                from:     _lender,
                amount:   10.0 * 1e18,
                index:    _i9_72
            }
        );

        skip(3 hours);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.489933125874732298 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.987669594447545452 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.192728433177224139 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.192728433177224139 * 1e18,
                auctionPrice:      77.770366920254236832 * 1e18,
                debtInAuction:     19.489662805046791054 * 1e18,
                thresholdPrice:    9.744966562937366149 * 1e18,
                neutralPrice:      10.118242741804267296 * 1e18
            })
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2.0 * 1e18,
                bondChange:      0.192728433177224139 * 1e18,
                givenAmount:     19.489933125874732298 * 1e18,
                collateralTaken: 0.250608733090583422 * 1e18,
                isReward:        false
            }
        );
        
        // Borrower is removed from auction, keeps collateral in system
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.749391266909416578 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  7.991488192808991114 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             63_008.836766669707730070 * 1e18,
                pledgedCollateral:    1_001.749391266909416578 * 1e18,
                encumberedCollateral: 821.863722498661263922 * 1e18,
                poolDebt:             7_989.580407145861717463 * 1e18,
                actualUtilization:    0.126800950741756503 * 1e18,
                targetUtilization:    0.826474536317057937 * 1e18,
                minDebtAmount:        798.958040714586171746 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 3 hours
            })
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   8_008.373442262808822463 * 1e18,
                index:    _i9_72,
                penalty:  0,
                newLup:   9.624807173121239337 * 1e18,
                lpRedeem: 8_007.362556980262765268525272905 * 1e27
            }
        );
        
        _assertBucket(
        {
                index:        _i9_72,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   25_000.037756489769875000 * 1e18,
                index:    _i9_62,
                penalty:  0,
                newLup:   9.529276179422528643 * 1e18,
                lpRedeem: 25_000.00 * 1e27
            }
        );

        _assertBucket(
        {
                index:        _i9_62,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   22_010.045307787723850000 * 1e18,
                penalty:  0,
                index:    _i9_52,
                newLup:   9.529276179422528643 * 1e18,
                lpRedeem: 22_010.012066955906216160936672387 * 1e27
            }
        );

        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    7_989.987933044093783839063327613 * 1e27,
                collateral:   0,          
                deposit:      7_990.0 * 1e18,
                exchangeRate: 1.000001510259590795000000000 * 1e27
            }
        );

        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:  _lender,
            index: _i9_52
        });

        skip(25 hours);

        _assertPool(
            PoolState({
                htp:                  7.991488192808991114 * 1e18,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             7_990.380260129405182606 * 1e18,
                pledgedCollateral:    1_001.749391266909416578 * 1e18,
                encumberedCollateral: 80036071881.142911713937910614 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    1.000015475308649579 * 1e18,
                targetUtilization:    0.826474536317057937 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 28 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_990.503913730158190391 * 1e18,
                borrowerCollateral:        1_000.00 * 1e18,
                borrowert0Np:              8.471136974495192173 * 1e18,
                borrowerCollateralization: 0.000000012494366309 * 1e18
            }
        );

        // draw debt is called to trigger accrual of pool interest that will push the lup back up
        IERC20Pool(address(_pool)).drawDebt(_lender, 0, 0, 0);

        _assertPool(
            PoolState({
                htp:                  7.993335753787741967 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             7_991.297334721700255549 * 1e18,
                pledgedCollateral:    1_001.749391266909416578 * 1e18,
                encumberedCollateral: 838.521600516187410670 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.999900714369856481 * 1e18,
                targetUtilization:    0.830319852811902746 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.04455 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        skip(117 days);

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              8_105.430237884635118282 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              8.471136974495192173 * 1e18,
                borrowerCollateralization: 0.000000012317209569 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           8_195.704467159075241912 * 1e18,
                collateral:     1_000.0 * 1e18,
                bond:           81.054302378846351183 * 1e18,
                transferAmount: 81.054302378846351183 * 1e18
            }
        );

        _assertRemoveDepositLockedByAuctionDebtRevert(
            {
                from:   _lender,
                amount: 10.0 * 1e18,
                index:  _i9_52
            }
        );

        skip(10 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          81.054302378846351183 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 81.054302378846351183 * 1e18,
                auctionPrice:      0.000000006239767680 * 1e18,
                debtInAuction:     8_195.704467159075241912 * 1e18,
                thresholdPrice:    8.196079597628232153 * 1e18,
                neutralPrice:      8.596021534820399874 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              8_196.079597628232153239 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              8.471136974495192173 * 1e18,
                borrowerCollateralization: 0.000000012180980150 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000.0 * 1e18,
                bondChange:      0.000000062397676800 * 1e18,
                givenAmount:     0.000006239767680000 * 1e18,
                collateralTaken: 1_000.0 * 1e18,
                isReward:        true
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             8_105.800538156165696386 * 1e18,
                pledgedCollateral:    1.749391266909416578 * 1e18,
                encumberedCollateral: 82_095_199_803.074941485714603011 * 1e18,
                poolDebt:             8_196.079591450862150038 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.174754005164844884 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              8_196.079591450862150038 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              8.471136974495192173 * 1e18,
                borrowerCollateralization: 0
            }
        );

        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 7_990.0 * 1e18,
            index:  _i9_52
        });

        _settle(
            {
                from:        _lender,
                borrower:    _borrower2,
                maxDepth:    5,
                settledDebt: 8_076.635779729962272432 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  1_004_968_987.606512354182109771 * 1e18,
                poolSize:             9.176161196119415534 * 1e18,
                pledgedCollateral:    1.749391266909416578 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1.174754005164844884 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        _assertBucket( 
            {
                index:        _i9_52,
                lpBalance:    7_989.987933044093783839063327613 * 1e27,
                collateral:   0,          
                deposit:      9.176161196119415534 * 1e18,
                exchangeRate: 1_148_457.453630146264614048 * 1e18
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   9.176155018749412335 * 1e18,
                penalty:  0,
                index:    _i9_52,
                newLup:   1_004_968_987.606512354182109771 * 1e18,
                lpRedeem: 7_989.982554203124383518185819249 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    0.005378840969400320877508364 * 1e27,
                collateral:   0,          
                deposit:      0.000006177370003204 * 1e18,
                exchangeRate: 0.001148457453631075833426706 * 1e27
            }
        );


        _pullCollateral(_borrower, 1.746878914360183483 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0.002512352549233095 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1.0 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  1_004_968_987.606512354182109771 * 1e18,
                poolSize:             0.000006177370003204 * 1e18,
                pledgedCollateral:    0.002512352549233095 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1.174754005164844884 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );
    }
 }