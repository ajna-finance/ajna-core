// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/BucketMath.sol';

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
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 1.009034539679184679 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );

    }

    function testTakeLoanColConstraintBpfPosNoResidual() external {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  _i100_33,
                newLup: _p100_33
            }
        );
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
                amount:     8000 * 1e18,
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      _p100_33 
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
                borrowerDebt:              9853394241979221645666,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        98967323110934109659,
                borrowerCollateralization: 986593617011217057
            }
        );
        _assertReserveAuction(
            {
                reserves:                   33358463298707422239,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        skip(358 minutes);

        _assertPool(
            PoolState({
                htp:                  9552494189823609848,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83118781595119199960000,
                pledgedCollateral:    1852000000000000000000,
                encumberedCollateral: 1_839.472863591931803026 * 1e18,
                poolDebt:             17_882.059942674413405135 * 1e18,
                actualUtilization:    635947182924111635,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.205994267441340514 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 358 minutes
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 358 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.948520384649726656 * 1e18,
                debtInAuction:     98_53.394241979221645666 * 1e18,
                thresholdPrice:    9.853763376238598848 * 1e18,
                neutralPrice:      100.336126859669134979 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9853763376238598848835,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        98967323110934109659,
                borrowerCollateralization: 986556657984476075
            }
        );

        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_001 * 1e18,
                bondChange:      99.381018677866129082 * 1e18,
                givenAmount:     9_948.520384649726656000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );
        
        // Auction is still active, residual is not collateralized
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          197914961097658345539,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 358 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 197.914961097658345539 * 1e18,
                auctionPrice:      9.948520384649726656 * 1e18,
                debtInAuction:     4.624010266738321916 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              4.624010266738321916 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        98.963615671641707633 * 1e18,
                borrowerCollateralization: 0
            }
        );
    }

    function testTakeCallerColConstraintBpfPosNoResidual() external {

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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      _p100_33 
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
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
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

        skip(355 minutes);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.472286131933987823 * 1e18,
                poolDebt:             17_882.054329014924422935 * 1e18,
                actualUtilization:    0.635946983283189428 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.205432901492442294 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 355 minutes
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 355 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      10.299354198348791200 * 1e18,
                debtInAuction:     98_53.394241979221645666 * 1e18,
                thresholdPrice:    9.853760282877293913 * 1e18,
                neutralPrice:      100.336095361460738455 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.760282877293913283 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
                borrowerCollateralization: 0.986556967691238095 * 1e18
            }
        );

        // BPF Positive, Caller collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   10 * 1e18,
                bondChange:      1.024863347413135944 * 1e18,
                givenAmount:     102.993541983487912000 * 1e18,
                collateralTaken: 10 * 1e18,
                isReward:        true
            }
        );
        
        // Auction is still active, residual is not collateralized
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          99558805767205352401,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 355 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 99.558805767205352401 * 1e18,
                auctionPrice:      10.299354198348791200 * 1e18,
                debtInAuction:     9_751.791604241219137227 * 1e18,
                thresholdPrice:    9.850294549738605189 * 1e18,
                neutralPrice:      100.332368143282009890 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_751.791604241219137227 * 1e18,
                borrowerCollateral:        990.000000000000000000 * 1e18,
                borrowerMompFactor:        98.963646738991686415 * 1e18,
                borrowerCollateralization: 0.986904078446035018 * 1e18
            }
        );
    }

    function testTakeCallerColConstraintBpfPosResidual () external {

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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      _p100_33 
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
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
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

        skip(355 minutes);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.472286131933987823 * 1e18,
                poolDebt:             17_882.054329014924422935 * 1e18,
                actualUtilization:    0.635946983283189428 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.205432901492442294 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 355 minutes
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 355 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      10.299354198348791200 * 1e18,
                debtInAuction:     98_53.394241979221645666 * 1e18,
                thresholdPrice:    9.853760282877293913 * 1e18,
                neutralPrice:      100.336095361460738455 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.760282877293913283 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
                borrowerCollateralization: 0.986556967691238095 * 1e18
            }
        );

        // BPF Positive, Caller collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   950.0 * 1e18,
                bondChange:      97.362018004247914694 * 1e18,
                givenAmount:     9_784.386488431351640000 * 1e18,
                collateralTaken: 950.0 * 1e18,
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
                thresholdPrice:    3.334716249003803759 * 1e18,
                neutralPrice:      100.332368143282009890 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              166.735812450190187977 * 1e18,
                borrowerCollateral:        50.0 * 1e18,
                borrowerMompFactor:        98.963646738991686415 * 1e18,
                borrowerCollateralization: 30.087228013254439061 * 1e18
            }
        );

    }

    function testTakeCallerColConstraintBpfNegResidual () external {

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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.954180783766029465 * 1e18
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
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      155.540733840508473696 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976664169451766428 * 1e18,
                neutralPrice:      9.954283053272040738 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.664169451766428084 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974403437854316417 * 1e18
            }
        );

        // BPF Negative, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   60 * 1e18,
                bondChange:      93.324440304305084218 * 1e18,
                givenAmount:     9_332.444030430508421760 * 1e18,
                collateralTaken: 60 * 1e18,
                isReward:        false
            }
        );

        _assertPool(
            PoolState({
                htp:                  9.902059490734692431 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_118.868890241151360666 * 1e18,
                pledgedCollateral:    942.0 * 1e18,
                encumberedCollateral: 66.929741471281107300 * 1e18,
                poolDebt:             663.754617694072999522 * 1e18,
                actualUtilization:    0.009077747341666842 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        33.187730884703649976 * 1e18,
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
                bondFactor:        0 * 1e18,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0.685340573426870219 * 1e18,
                neutralPrice:      9.917184843435912074 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              644.220139021258006324 * 1e18,
                borrowerCollateral:        940.000000000000000000 * 1e18,
                borrowerMompFactor:        9.782158751910768707 * 1e18,
                borrowerCollateralization: 14.470447581773199554 * 1e18
            }
        );
    }

    function testTakeLoanDebtConstraintBpfPosResidual() external {

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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_853.394241979221645666 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      _p100_33 
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
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
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

        skip(355 minutes);

        _assertPool(
            PoolState({
                htp:                  9.552494189823609848 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_852.000000000000000000 * 1e18,
                encumberedCollateral: 1_839.472286131933987823 * 1e18,
                poolDebt:             17_882.054329014924422935 * 1e18,
                actualUtilization:    0.635946983283189428 * 1e18,
                targetUtilization:    98205815911108893,
                minDebtAmount:        1_788.205432901492442294 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0550 * 1e18,
                interestRateUpdate:   block.timestamp - 355 minutes
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 355 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      10.299354198348791200 * 1e18,
                debtInAuction:     98_53.394241979221645666 * 1e18,
                thresholdPrice:    9.853760282877293913 * 1e18,
                neutralPrice:      100.336095361460738455 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.760282877293913283 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        98.967323110934109659 * 1e18,
                borrowerCollateralization: 0.986556967691238095 * 1e18
            }
        );

        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_001 * 1e18,
                bondChange:      99.037840670257198615 * 1e18,
                givenAmount:     9_952.798123547551111898 * 1e18,
                collateralTaken: 966.351669422457525768 * 1e18,
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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        33.648330577542474232 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1.0 * 1e18
            }
        );
    }

    function testTakeAndSettle() external { 
    // function testTakeAndSettle() external tearDown { 
    // FIXME: fails on tear down in removeQuoteToken when lender redeems, lender and bucket LPs are 30000.000000000000000000 but contract balance is only 29999.999999999999999004
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.954180783766029465 * 1e18
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
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.948520384649726656 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976867463138769510 * 1e18,
                neutralPrice:      9.954485890900831362 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.867463138769510756 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974383582918060948 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000 * 1e18,
                bondChange:      99.485203846497266560 * 1e18,
                givenAmount:     9_948.520384649726656000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              127.832282335540121316 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.781959425706739955 * 1e18,
                borrowerCollateralization: 0
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          198.019146266289483017 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 358 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 198.019146266289483017 * 1e18,
                auctionPrice:      9.948520384649726656 * 1e18,
                debtInAuction:     127.832282335540121316 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    198.019146266289483017 * 1e18 // locked bond + reward, auction is not yet finished
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.977074177773911990 * 1e18,
                neutralPrice:      9.954692141803388822 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_977.074177773911990381 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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
                bondChange:      0.121516198312897248 * 1e18,
                givenAmount:     12.151619831289724800 * 1e18,
                collateralTaken: 20 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.655458618105113705 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.655458618105113705 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_965.044074140935162829 * 1e18,
                thresholdPrice:    10.168412320551974655 * 1e18,
                neutralPrice:      9.818751856078723036 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.655458618105113705 * 1e18 // locked bond + reward, auction is not yet finished
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_965.044074140935162829 * 1e18,
                borrowerCollateral:        980 * 1e18,
                borrowerMompFactor:        9.684667957374334904 * 1e18,
                borrowerCollateralization: 0.956028882245805301 * 1e18
            }
        );

        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         98.218482774160286961 * 1e18,
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
                bondChange:      5.954293717331965152 * 1e18,
                givenAmount:     595.429371733196515200 * 1e18,
                collateralTaken: 980 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          104.609752335437078857 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 104.609752335437078857 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_375.568996125070612781 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0 * 1e18,
                locked:    104.609752335437078857 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_375.568996125070612781 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         101.165858164239609711 * 1e18,
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
                index:        3696,
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
                settledDebt: 9_247.537158474120526797 * 1e18
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
                claimable: 104.609752335437078857 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
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
                deposit:      8_891.790463124946989056 * 1e18,
                exchangeRate: 0.808344587556813362641454545 * 1e27
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
                claimableReserves :         101.165858164239609711 * 1e18,
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
                bondSize:          104.609752335437078857 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 104.609752335437078857 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     7_108.516109406279010945 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    104.609752335437078857 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_108.516109406279010945 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // clear remaining debt
        _settle(
            {
                from:        _lender,
                borrower:    _borrower2,
                maxDepth:    5,
                settledDebt: 7_011.442920479311505695 * 1e18
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
                claimable: 104.609752335437078857 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 46_293.885066015721543543 * 1e18);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 46_398.494818351158622400 * 1e18);
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
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      9.954180783766029465 * 1e18
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
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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
                neutralPrice:      10.178691762845855387 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.776602251620519294 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 98.731708442308421650 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_120.320801313999710974 * 1e18,
                thresholdPrice:    9.999544513475625068 * 1e18,
                neutralPrice:      10.178691762845855387 * 1e18
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
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, 7777);
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