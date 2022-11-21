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

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
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
                thresholdPrice:    9.976561670003961916 * 1e18
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

    }

    function skipTestTakeLoanColConstraintBpfPosNoResidual () external {

        // In order to trigger the loan collateral as constraint the AP should be as high as possible while BPF is still positive
        skip(6 hours);

        _assertPool(
            PoolState({
                htp:                  9.901856025849255254 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.299538494119214286 * 1e18,
                poolDebt:             9_996.404051576968397807 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        999.640405157696839781 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 6 hours
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976869171506632084 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.869171506632084967 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974383416071571307 * 1e18
            }
        );


        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_001 * 1e18,
                bondChange:      97.212958650317796160 * 1e18,
                givenAmount:     9_721.295865031779616000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          195746901070110012617,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 195746901070110012617,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     352786265125170265127,
                thresholdPrice:    0
            })
        );


    }

    function testTakeCallerColConstraintBpfPosNoResidual () external {
        skip(6 hours);

        // not working... assume the Price needs to be as high as possible but just under the BPF positive threshold. Can't get it to work.
        _assertPool(
            PoolState({
                htp:                  9.901856025849255254 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.299538494119214286 * 1e18,
                poolDebt:             9_996.404051576968397807 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        999.640405157696839781 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 6 hours
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976869171506632084 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.869171506632084967 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974383416071571307 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   999.0 * 1e18,
                bondChange:      97.115745691667478364 * 1e18,
                givenAmount:     9_711.574569166747836384 * 1e18,
                collateralTaken: 999.0 * 1e18,
                isReward:        true
            }
        );        

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          195649688111459694821,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 195649688111459694821,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     362410348031551726947,
                thresholdPrice:    362410348031551726947
            })
        );


    }

    function testTakeCallerColConstraintBpfPosResidual () external {

        skip(6 hours);

        _assertPool(
            PoolState({
                htp:                  9.901856025849255254 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.299538494119214286 * 1e18,
                poolDebt:             9_996.404051576968397807 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        999.640405157696839781 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 6 hours
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976869171506632084 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.869171506632084967 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974383416071571307 * 1e18
            }
        );

        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   980 * 1e18,
                bondChange:      95.268699477311440237 * 1e18,
                givenAmount:     9_526.869947731144023680 * 1e18,
                collateralTaken: 980 * 1e18,
                isReward:        true
            }
        );

        _assertPool(
            PoolState({
                htp:                  27.640288998896102594 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_119.043483175680286453 * 1e18,
                pledgedCollateral:    22.000000000000000000 * 1e18,
                encumberedCollateral: 56.951928620849825279 * 1e18,
                poolDebt:             564.802803323135814363 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        28.240140166156790718 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 6 hours
            })
        );

        // Residual amount exists in the auction
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          193.802641897103656694 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 193.802641897103656694 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     545.267923252799501524 * 1e18,
                thresholdPrice:    27.263396162639975076 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              545.267923252799501524 * 1e18,
                borrowerCollateral:        20.000000000000000 * 1e18,
                borrowerMompFactor:        9.781957750713830996 * 1e18,
                borrowerCollateralization: 0.363754566169045063 * 1e18
            }
        );

    }

    function testTakeCallerColConstraintBpfNegResidual () external {

        skip(5 hours);

        _assertPool(
            PoolState({
                htp:                  9.901856025849255254 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.294256147043948394 * 1e18,
                poolDebt:             9_996.352700318187952784 * 1e18,
                actualUtilization:    0 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        999.635270031818795278 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5 hours
            })
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      19.442591730063559200 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976817920598005211 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.817920598005211273 * 1e18,
                borrowerCollateral:        1_000.000000000000000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974388421478688292 * 1e18
            }
        );

        // BPF Negative, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   10 * 1e18,
                bondChange:      1.944259173006355920 * 1e18,
                givenAmount:     194.425917300635592000 * 1e18,
                collateralTaken: 10 * 1e18,
                isReward:        false
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.017751669304894664 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.999834605716904563 * 1e18,
                pledgedCollateral:    992.000000000000000000 * 1e18,
                encumberedCollateral: 1_008.294256147043948405 * 1e18,
                poolDebt:             9_801.926783017552360784 * 1e18,
                actualUtilization:    4.626067320254781713 * 1e18,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        490.096339150877618039 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5 hours
            })
        );

        // Residual amount exists in the auction
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          96589683246785860537,
                bondFactor:        0.010000000000000000 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                kickMomp:          9721295865031779605,
                totalBondEscrowed: 96589683246785860537,
                auctionPrice:      19442591730063559200,
                debtInAuction:     9782392003297369619274,
                thresholdPrice:    9881204043734716787
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_782.392003297369619274 * 1e18,
                borrowerCollateral:        990.000000000000000 * 1e18,
                borrowerMompFactor:        9.684916710602077770 * 1e18,
                borrowerCollateralization: 0.983816933847821038 * 1e18
            }
        );
    }

    function skipTestTakeCallerDebtConstraintBpfPosResidual () external {

        // not working, is this the loan's debt constraint?
        skip(10 hours);

        // BPF Positive, Loan collateral constraint
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000 * 1e18,
                bondChange:      97.212958650317796160 * 1e18,
                givenAmount:     9_721.295865031779616000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );

    }
    
    function testTakeGTAndLTNeutral() external {

        uint256 snapshot = vm.snapshot();

        skip(2 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      155.540733840508473696 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18,
                thresholdPrice:    9.889329828112590306 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778659656225180612 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 0.983008559123679212 * 1e18
            }
        );

        // Collateral amount is restrained by debt
        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2 * 1e18,
                bondChange:      0.195342779771472726 * 1e18,
                givenAmount:     19.778659656225180612 * 1e18,
                collateralTaken: 0.127160642539504961 * 1e18,
                isReward:        false
            }
        );

        _assertPool(
            PoolState({
                htp:                  8.209707505045490451 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_094.573651667204129413 * 1e18,
                pledgedCollateral:    1_001.872839357460495039 * 1e18,
                encumberedCollateral: 833.009246211652698543 * 1e18,
                poolDebt:             8_097.929340730578997964 * 1e18,
                actualUtilization:    0.110787011075833458 * 1e18,
                targetUtilization:    0.833368500318426368 * 1e18,
                minDebtAmount:        809.792934073057899796 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045000000000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );

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
                thresholdPrice:    0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0 * 1e18,
                borrowerCollateral:        1.872839357460495039 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1.0 * 1e18
            }
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0, // the entire bond was penalized
                locked:    0
            }
        );

        vm.revertTo(snapshot);

        skip(6 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18,
                thresholdPrice:    9.889533035607758374 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.779066071215516749 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 0.982988360525190378 * 1e18
            }
        );

        // Collateral amount is restrained by taker
        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   1 * 1e18,
                bondChange:      0.097212958650317796 * 1e18,
                givenAmount:     9.721295865031779616 * 1e18,
                collateralTaken: 1 * 1e18,
                isReward:        true
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.292555738421790522 * 1e18,
                bondFactor:        0.010000000000000000 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.292555738421790522 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     10.154983164834054929 * 1e18,
                thresholdPrice:    10.154983164834054929 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              10.154983164834054929 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        9.684866959445391109 * 1e18,
                borrowerCollateralization: 0.957293154231500657 * 1e18
            }
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.292555738421790522 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  10.295367010789837835 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_094.716397818020278066 * 1e18,
                pledgedCollateral:    1_001.000000000000000000 * 1e18,
                encumberedCollateral: 834.070975103156730898 * 1e18,
                poolDebt:             8_108.250721413341922653 * 1e18,
                actualUtilization:    0.110928000285057328 * 1e18,
                targetUtilization:    0.833368500318426368 * 1e18,
                minDebtAmount:        405.412536070667096133 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.045000000000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 6 hours
            })
        );

    }

    function testTakeAndSettle() external {
    // function testTakeAndSettle() external tearDown { // FIXME: fails on tear down in removeQuoteToken when lender redeems, lender and bucket LPs are 30000.000000000000000000 but contract balance is only 29999.999999999999999004
        uint256 preTakeSnapshot = vm.snapshot();

        // skip ahead so take can be called on the loan
        // Debt cannot be used as a constraint when AP < NP
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
                thresholdPrice:    9.976867463138769510 * 1e18
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
                thresholdPrice:    0
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
                thresholdPrice:    9.977074177773911990 * 1e18
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
                thresholdPrice:    10.168412320551974655 * 1e18
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
                thresholdPrice:    0
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
                thresholdPrice:    0
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
                deposit:      8_891.790463124946990051 * 1e18,
                exchangeRate: 0.808344587556813362731909090 * 1e27
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
                thresholdPrice:    0
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
                thresholdPrice:    0
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
                thresholdPrice:    9.888301125810259647 * 1e18
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
                thresholdPrice:    9.999544513475625068 * 1e18
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