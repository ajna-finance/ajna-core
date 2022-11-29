// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/BucketMath.sol';
import '@std/console.sol';

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

        _mintCollateralAndApproveTokens(_borrower,  854 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender1,   4 * 1e18);

        // Lender adds Quote token accross 5 prices
        _addLiquidity(
            {
                from:   _lender,
                amount: 2_000 * 1e18,
                index:  _i9_91,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  _i9_81,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  _i9_72,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i9_62,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  _i9_52,
                newLup: BucketMath.MAX_PRICE
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
                borrowert0Np:              9.634254807692307697 * 1e18,
                borrowerCollateralization: 1.009034539679184679 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              8.067749499519230641 * 1e18,
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

        // Borrower2 borrows
        _borrow(
            {
                from:       _borrower2,
                amount:     1_730 * 1e18,
                indexLimit: _i9_72,
                newLup:     9.721295865031779605 * 1e18
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );

    }

    function testTakeLoanColConstraintBpfPosNoResidual() external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i100_33,
                newLup: _p100_33
            }
        );
        
        // calling repay stamps new t0NeutralPrice on loan (mompFactor)
        _repay({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   0,
            repaid:   0,
            newLup:   _p100_33
        });   

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   850 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     8_000 * 1e18,
                indexLimit: _i9_72,
                newLup:     _p9_72
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_853.394241979221645666 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           2_956.018272593766493700 * 1e18,
                transferAmount: 2_956.018272593766493700 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          _p100_33,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      3_210.635780585024316480 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18 
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    2_956.018272593766493700 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   33.358463298707422239 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        skip(33610 seconds);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.511778397294114128 * 1e18,
                poolDebt:             17_882.438245010870556573 * 1e18,
                actualUtilization:    0.635960636648455183 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.243824501087055657 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 33610 seconds
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 33610 seconds,
                kickMomp:          100.332368143282009890 * 1e18,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      9.935084144788591232 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853971836657592918 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.971836657592918128 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986535787413939251 * 1e18
            }
        );
        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_001 * 1e18,
                bondChange:      518.705713222703336422 * 1e18,
                givenAmount:     9_935.084144788591232000 * 1e18,
                collateralTaken: 1000.0 * 1e18,
                isReward:        true
            }
        );
        
        // Auction is still active, residual is not collateralized
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          3_474.723985816469830122 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 33610 seconds,
                kickMomp:          100.332368143282009890 * 1e18,
                totalBondEscrowed: 3_474.723985816469830122 * 1e18,
                auctionPrice:      9.935084144788591232 * 1e18,
                debtInAuction:     437.593405091705022550 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              437.593405091705022550 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0
            }
        );
    }

    function testTakeCallerColConstraintBpfPosNoResidual() external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i100_33,
                newLup: _p100_33
            }
        );
        
        // calling repay stamps new t0NeutralPrice on loan (mompFactor)
        _repay({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   0,
            repaid:   0,
            newLup:   _p100_33
        });   

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   850 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     8_000 * 1e18,
                indexLimit: _i9_72,
                newLup:     _p9_72
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_853.394241979221645666 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           2_956.018272593766493700 * 1e18,
                transferAmount: 2_956.018272593766493700 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          _p100_33,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      3_210.635780585024316480 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18 
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    2_956.018272593766493700 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   33.358463298707422239 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        skip(33610 seconds);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.511778397294114128 * 1e18,
                poolDebt:             17_882.438245010870556573 * 1e18,
                actualUtilization:    0.635960636648455183 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.243824501087055657 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 33610 seconds
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 33610 seconds,
                kickMomp:          100.332368143282009890 * 1e18,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      9.935084144788591232 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853971836657592918 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.971836657592918128 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986535787413939251 * 1e18
            }
        );

        // BPF Positive, Caller collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   10 * 1e18,
                bondChange:      5.187057132227033364 * 1e18,
                givenAmount:     99.350841447885912320 * 1e18,
                collateralTaken: 10.0 * 1e18,
                isReward:        true
            }
        );
        
        // Auction is still active, residual is not collateralized
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_961.205329725993527064 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 33610 seconds,
                kickMomp:          100.332368143282009890 * 1e18,
                totalBondEscrowed: 2_961.205329725993527064 * 1e18,
                auctionPrice:      9.935084144788591232 * 1e18,
                debtInAuction:     9759.808052341934039172 * 1e18,
                thresholdPrice:    9.858391972062559635 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_759.808052341934039172 * 1e18,
                borrowerCollateral:        990.000000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986093461548364772 * 1e18
            }
        );
    }

    function testTakeCallerColConstraintBpfPosResidual () external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i100_33,
                newLup: _p100_33
            }
        );
        
        // calling repay stamps new t0NeutralPrice on loan (mompFactor)
        _repay({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   0,
            repaid:   0,
            newLup:   _p100_33
        });   

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   850 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     8_000 * 1e18,
                indexLimit: _i9_72,
                newLup:     _p9_72
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_853.394241979221645666 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           2_956.018272593766493700 * 1e18,
                transferAmount: 2_956.018272593766493700 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          _p100_33,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      3_210.635780585024316480 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18 
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    2_956.018272593766493700 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   33.358463298707422239 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        skip(33610 seconds);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.511778397294114128 * 1e18,
                poolDebt:             17_882.438245010870556573 * 1e18,
                actualUtilization:    0.635960636648455183 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.243824501087055657 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 33610 seconds
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_956.018272593766493700 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 33610 seconds,
                kickMomp:          100.332368143282009890 * 1e18,
                totalBondEscrowed: 2_956.018272593766493700 * 1e18,
                auctionPrice:      9.935084144788591232 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853971836657592918 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.971836657592918128 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.986535787413939251 * 1e18
            }
        );


        // BPF Positive, Caller collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   990.0 * 1e18,
                bondChange:      513.518656090476303058 * 1e18,
                givenAmount:     9_835.733303340705319680 * 1e18,
                collateralTaken: 990.0 * 1e18,
                isReward:        true
            }
        );

        // Residual is collateralized, auction is not active
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    53.175718940736390150 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              531.757189407363901506 * 1e18,
                borrowerCollateral:        10.0 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 1.886807929293839146 * 1e18
            }
        );

    }

    function testTakeCallerColConstraintBpfNegResidual () external tearDown {

        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      314.200059394519137152 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.533942419792216457 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   148.064352861909228810 * 1e18,
                claimableReserves :         98.083873122003682866 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        skip(2 hours);

        _assertPool(
            PoolState({
                htp:                  9.901856025849255254 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.278409268629243557 * 1e18,
                poolDebt:             9_996.198648124581421281 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        999.619864812458142128 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      157.100029697259568576 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976664169451766428 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.664169451766428084 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974403437854316417 * 1e18
            }
        );

        // BPF Negative, Caller collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   60 * 1e18,
                bondChange:      94.260017818355741146 * 1e18,
                givenAmount:     9_426.001781835574114560 * 1e18,
                collateralTaken: 60.0 * 1e18,
                isReward:        false
            }
        );

        _assertPool(
            PoolState({
                htp:                  9.902059490734692431 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_118.868890241151360666 * 1e18,
                pledgedCollateral:    942.0 * 1e18,
                encumberedCollateral: 57.495839322427780643 * 1e18,
                poolDebt:             570.196866289007306722 * 1e18,
                actualUtilization:    0.007798217819054760 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        28.509843314450365336 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );
 
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0.585811050655523737 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              550.662387616192313524 * 1e18,
                borrowerCollateral:        940.000000000000000000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 16.928982190313006885 * 1e18
            }
        );
    }

    function testTakeLoanDebtConstraintBpfPosResidual() external {

        // FIXME: BPF needs to be positive below
        // Increase neutralPrice so it exceeds TP
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i100_33,
                newLup: _p100_33
            }
        );

        _assertBucket(
            {
                index:        _i100_33,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1.0* 1e27
            }
        );

        _assertPool(
            PoolState({
                htp:                  9.989300988155456469 * 1e18,
                lup:                  100.332368143282009890 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002.000000000000000000 * 1e18,
                encumberedCollateral: 98.402227542931110509 * 1e18,
                poolDebt:             9_872.928519956368918239 * 1e18,
                actualUtilization:    0.814679961220908454 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        493.646425997818445912 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        
        // calling pullCollateral stamps new t0NeutralPrice on loan (mompFactor)
        console.log("before Pull");
        _pullCollateral({
            from:     _borrower2,
            amount:   0
        });   
        console.log("after Pull");
        
        // _assertPool(
        //     PoolState({
        //         htp:                  9.989300988155456469 * 1e18,
        //         lup:                  100.332368143282009890 * 1e18,
        //         poolSize:             83_118.781595119199960000 * 1e18,
        //         pledgedCollateral:    1_002.000000000000000000 * 1e18,
        //         encumberedCollateral: 98.402227542931110509 * 1e18,
        //         poolDebt:             9_872.928519956368918239 * 1e18,
        //         actualUtilization:    0.814679961220908454 * 1e18,
        //         targetUtilization:    98205815911108893,
        //         minDebtAmount:        493.646425997818445912 * 1e18,
        //         loans:                2,
        //         maxBorrower:          address(_borrower2),
        //         interestRate:         0.0550 * 1e18,
        //         interestRateUpdate:   block.timestamp
        //     })
        // );

        // _assertBorrower(
        //     {
        //         borrower:                  _borrower2,
        //         borrowerDebt:              9_853.394241979221645666 * 1e18,
        //         borrowerCollateral:        1_000 * 1e18,
        //         borrowert0Np:              9.719336538461538465 * 1e18,
        //         borrowerCollateralization: 10.182518397145606251 * 1e18
        //     }
        // );

        // _assertAuction(
        //     AuctionState({
        //         borrower:          _borrower2,
        //         active:            false,
        //         kicker:            address(0),
        //         bondSize:          0,
        //         bondFactor:        0,
        //         kickTime:          0,
        //         kickMomp:          0,
        //         totalBondEscrowed: 0,
        //         auctionPrice:      0,
        //         debtInAuction:     0,
        //         thresholdPrice:    9.853394241979221645 * 1e18,
        //         neutralPrice:      0
        //     })
        // );

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   850 * 1e18
            }
        );

        _borrow(
            {
                from:       _borrower,
                amount:     8_000 * 1e18,
                indexLimit: _i9_72,
                newLup:     _p9_72
            }
        );

        // _kick(
        //     {
        //         from:           _lender,
        //         borrower:       _borrower2,
        //         debt:           9_853.394241979221645666 * 1e18,
        //         collateral:     1_000 * 1e18,
        //         bond:           2_956.018272593766493700 * 1e18,
        //         transferAmount: 2_956.018272593766493700 * 1e18
        //     }
        // );

        // _assertAuction(
        //     AuctionState({
        //         borrower:          _borrower2,
        //         active:            true,
        //         kicker:            _lender,
        //         bondSize:          2_956.018272593766493700 * 1e18,
        //         bondFactor:        0.3 * 1e18,
        //         kickTime:          block.timestamp,
        //         kickMomp:          _p100_33,
        //         totalBondEscrowed: 2_956.018272593766493700 * 1e18,
        //         auctionPrice:      3_210.635780585024316480 * 1e18,
        //         debtInAuction:     9_853.394241979221645666 * 1e18,
        //         thresholdPrice:    9.853394241979221645 * 1e18,
        //         neutralPrice:      9.853394241979221645 * 1e18 
        //     })
        // );

        // assertEq(true, false);

        // _assertKicker(
        //     {
        //         kicker:    _lender,
        //         claimable: 0,
        //         locked:    2_956.018272593766493700 * 1e18
        //     }
        // );
        // _assertBorrower(
        //     {
        //         borrower:                  _borrower2,
        //         borrowerDebt:              9_853.394241979221645666 * 1e18,
        //         borrowerCollateral:        1_000 * 1e18,
        //         borrowert0Np:              9.816772887259615229 * 1e18,
        //         borrowerCollateralization: 0.986593617011217057 * 1e18
        //     }
        // );
        // _assertReserveAuction(
        //     {
        //         reserves:                   33.358463298707422239 * 1e18,
        //         claimableReserves :         0,
        //         claimableReservesRemaining: 0,
        //         auctionPrice:               0,
        //         timeRemaining:              0
        //     }
        // );

        // skip(33609 seconds);

        // _assertPool(
        //     PoolState({
        //         htp:                  9.552494189823609848 * 1e18,
        //         lup:                  9.721295865031779605 * 1e18,
        //         poolSize:             83_118.781595119199960000 * 1e18,
        //         pledgedCollateral:    1_852.000000000000000000 * 1e18,
        //         encumberedCollateral: 1_839.511778397294114128 * 1e18,
        //         poolDebt:             17_882.438245010870556573 * 1e18,
        //         actualUtilization:    0.635960636648455183 * 1e18,
        //         targetUtilization:    98205815911108893,
        //         minDebtAmount:        1_788.243824501087055657 * 1e18,
        //         loans:                1,
        //         maxBorrower:          address(_borrower),
        //         interestRate:         0.0550 * 1e18,
        //         interestRateUpdate:   block.timestamp - 33610 seconds
        //     })
        // );

        // _assertAuction(
        //     AuctionState({
        //         borrower:          _borrower2,
        //         active:            true,
        //         kicker:            _lender,
        //         bondSize:          2_956.018272593766493700 * 1e18,
        //         bondFactor:        0.3 * 1e18,
        //         kickTime:          block.timestamp - 33610 seconds,
        //         kickMomp:          100.332368143282009890 * 1e18,
        //         totalBondEscrowed: 2_956.018272593766493700 * 1e18,
        //         auctionPrice:      9.935084144788591232 * 1e18,
        //         debtInAuction:     9_853.394241979221645666 * 1e18,
        //         thresholdPrice:    9.853971836657592918 * 1e18,
        //         neutralPrice:      9.952174519255063180 * 1e18
        //     })
        // );

        // _assertBorrower(
        //     {
        //         borrower:                  _borrower2,
        //         borrowerDebt:              9_853.971836657592918128 * 1e18,
        //         borrowerCollateral:        1_000.000000000000000 * 1e18,
        //         borrowert0Np:              9.816772887259615229 * 1e18,
        //         borrowerCollateralization: 0.986535787413939251 * 1e18
        //     }
        // );
 
        // BPF Positive, Loan Debt constraint
        // _take(
        //     {
        //         from:            _lender,
        //         borrower:        _borrower2,
        //         maxCollateral:   1_001 * 1e18,
        //         bondChange:      2_956.018272593766493700 * 1e18,
        //         givenAmount:     9_853.760282877293913283 * 1e18,
        //         collateralTaken: 92.699010164385584812 * 1e18,
        //         isReward:        false
        //     }
        // );

        // Residual is collateralized, auction is not active
        // _assertAuction(
        //     AuctionState({
        //         borrower:          _borrower2,
        //         active:            false,
        //         kicker:            address(0),
        //         bondSize:          0,
        //         bondFactor:        0,
        //         kickTime:          0,
        //         kickMomp:          0,
        //         totalBondEscrowed: 0,
        //         auctionPrice:      0,
        //         debtInAuction:     0,
        //         thresholdPrice:    0,
        //         neutralPrice:      0
        //     })
        // );

        // _assertBorrower(
        //     {
        //         borrower:                  _borrower2,
        //         borrowerDebt:              0,
        //         borrowerCollateral:        907.300989835614415188 * 1e18,
        //         borrowert0Np:              9816772887259615229,
        //         borrowerCollateralization: 1.0 * 1e18
        //     }
        // );
    }

    function testTakeAndSettle() external tearDown { 
        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      314.200059394519137152 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.533942419792216457 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   148.064352861909228810 * 1e18,
                claimableReserves :         98.083873122003682866 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        uint256 preTakeSnapshot = vm.snapshot();

        skip(358 minutes);

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 358 minutes,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      10.048254301505840000 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976867463138769510 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.867463138769510756 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974383582918060948 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000 * 1e18,
                bondChange:      98.533942419792216457 * 1e18,
                givenAmount:     9_976.867463138769510756 * 1e18,
                collateralTaken: 992.895597959102966127 * 1e18,
                isReward:        false
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        7.104402040897033873 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
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

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0
            }
        );

        vm.revertTo(preTakeSnapshot);

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      0.613671991004920192 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.977074177773911990 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_977.074177773911990381 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974363394700228467 * 1e18
            }
        );

        // partial take for 20 collateral
        // Collateral amount is restrained by taker
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   20 * 1e18,
                bondChange:      0.122734398200984038 * 1e18,
                givenAmount:     12.273439820098403840 * 1e18,
                collateralTaken: 20 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.656676817993200495 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.656676817993200495 * 1e18,
                auctionPrice:      0.613671991004920192 * 1e18,
                debtInAuction:     9_964.923472352014570580 * 1e18,
                thresholdPrice:    10.168289257502055684 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.656676817993200495 * 1e18 // locked bond + reward, auction is not yet finished
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_964.923472352014570580 * 1e18,
                borrowerCollateral:        980 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.956040452710323016 * 1e18
            }
        );

        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490833 * 1e18,
                claimableReserves :         98.219085783104889923 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        // take remaining collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   981 * 1e18,
                bondChange:      6.013985511848217882 * 1e18,
                givenAmount:     601.398551184821788160 * 1e18,
                collateralTaken: 980 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          104.670662329841418377 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 104.670662329841418377 * 1e18,
                auctionPrice:      0.613671991004920192 * 1e18,
                debtInAuction:     9_369.538906679041000301 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    104.670662329841418377 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_369.538906679041000301 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         101.196008611469757773 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        // should revert if there's no more collateral to be auctioned
        _assertTakeInsufficentCollateralRevert(
            {
                from:          _lender,
                borrower:      _borrower2,
                maxCollateral: 10 * 1e18
            }
        );

        // full clear / debt settle
        uint256 postTakeSnapshot = vm.snapshot();

        _assertBucket(
            {
                index:        3_696,
                lpBalance:    2_000 * 1e27,
                collateral:   0,
                deposit:      2_118.911507166546111004 * 1e18,
                exchangeRate: 1.059455753583273055502000000 * 1e27
            }
        );
        _settle(
            {
                from:        _lender,
                borrower:    _borrower2,
                maxDepth:    10,
                settledDebt: 9_241.589415329770722443 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
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
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 104.670662329841418377 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    0, // bucket is bankrupt
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   0, // bucket is bankrupt
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    0, // bucket is bankrupt
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_81,
                lpBalance:   0, // bucket is bankrupt
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      8_897.820552570976601535 * 1e18,
                exchangeRate: 0.808892777506452418321363636 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_72,
                lpBalance:   11_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_62,
                lpBalance:   25_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    30_000 * 1e27,
                collateral:   0,
                deposit:      30_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_52,
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );

        vm.revertTo(postTakeSnapshot);

        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         101.196008611469757773 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );
        // partial clears / debt settled - max buckets to use is 1, remaining will be taken from reserves
        _settle(
            {
                from:        _lender,
                borrower:    _borrower2,
                maxDepth:    1,
                settledDebt: 2_236.094237994809021102 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   0,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          104.670662329841418377 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 104.670662329841418377 * 1e18,
                auctionPrice:      0.613671991004920192 * 1e18,
                debtInAuction:     7_102.486019960249398465 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    104.670662329841418377 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_102.486019960249398465 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // clear remaining debt
        _settle(
            {
                from:        _lender,
                borrower:    _borrower2,
                maxDepth:    5,
                settledDebt: 7_005.495177334961701341 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
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
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 104.670662329841418377 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 46_287.794066575287591543 * 1e18);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 46_392.464728905129009920 * 1e18);
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0
            }
        );
    }

    function testTakeReverts() external {
        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      314.200059394519137152 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.952174519255063180 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.533942419792216457 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowert0Np:              9.816772887259615229 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   148.064352861909228810 * 1e18,
                claimableReserves :         98.083873122003682866 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.888301125810259647 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.776602251620519294 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              9.634254807692307697 * 1e18,
                borrowerCollateralization: 0.983110823724556080 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           19.999089026951250136 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.197766022516205193 * 1e18,
                transferAmount: 0.197766022516205193 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.197766022516205193 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.731708442308421650 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     10_120.320801313999710974 * 1e18,
                thresholdPrice:    9.999544513475625068 * 1e18,
                neutralPrice:      9.888301125810259647 * 1e18
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.731708442308421650 * 1e18
            }
        );

        skip(2 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, 7_777);
        }        
        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertTakeDebtUnderMinPoolDebtRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 0.1 * 1e18
            }
        );
    }
}