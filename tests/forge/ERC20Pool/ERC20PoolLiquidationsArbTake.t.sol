// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsArbTakeTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;
    address internal _taker;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");
        _taker     = makeAddr("taker");

        _mintQuoteAndApproveTokens(_lender,  120_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender1,   4 * 1e18);

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 2_000 * 1e18,
                index:  _i9_91
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  _i9_81
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  _i9_72
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i9_62
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  _i9_52
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
            PoolParams({
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
                borrowert0Np:              8.471136974495192174 * 1e18,
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
        _assertArbTakeNoAuctionRevert(
            {
                from:     _lender,
                borrower: _borrower,
                index:    _i9_91
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
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
                thresholdPrice:    9.767138988573636286 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.534277977147272573 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.995306391810796636 * 1e18
            }
        );
        
        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           19.778456451861613480 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.195342779771472726 * 1e18,
                transferAmount: 0.195342779771472726 * 1e18
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      328.175870016074179200 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18,
                thresholdPrice:    9.889228225930806740 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.195342779771472726 * 1e18
            }
        );
    }

    function testArbTakeCollateralRestrict() external tearDown {

        skip(6.5 hours);

        _assertLenderLpBalance(
           {
               lender:      _taker,
               index:       _i9_91,
               lpBalance:   0,
               depositTime: 0
           }
        );
        _assertLenderLpBalance(
           {
               lender:      _lender,
               index:       _i9_91,
               lpBalance:   2_000 * 1e27,
               depositTime: _startTime
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000 * 1e27,
               collateral:   0,
               deposit:      2_027.000651340490292000 * 1e18,
               exchangeRate: 1.013500325670245146000000000 * 1e27
           }
        );
        _assertBorrower(
           {
               borrower:                  _borrower,
               borrowerDebt:              19.779116873676490456 * 1e18,
               borrowerCollateral:        2 * 1e18,
               borrowert0Np:              10.115967548076923081 * 1e18,
               borrowerCollateralization: 0.982985835729561629 * 1e18
           }
        );

        // add liquidity to accrue interest and update reserves before arb take
        _addLiquidity(
           {
               from:    _lender1,
               amount:  1 * 1e18,
               index:   _i9_52,
               lpAward: 0.999996826562080000190961519 * 1e27,
               newLup:  9.721295865031779605 * 1e18
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000 * 1e27,
               collateral:   0,
               deposit:      2_027.007083921634518000 * 1e18,
               exchangeRate: 1.013503541960817259000000000 * 1e27
           }
        );
        _assertReserveAuction(
           {
               reserves:                   23.911413759224212224 * 1e18,
               claimableReserves :         0,
               claimableReservesRemaining: 0,
               auctionPrice:               0,
               timeRemaining:              0
           }
        );

        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18, // should be the same after arb take, kicker will be rewarded with LPs
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6.5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      7.251730722192532064 * 1e18,
               debtInAuction:     19.779116873676490456 * 1e18,
               thresholdPrice:    9.889558436838245228 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.779116873676490456 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.982985835729561629 * 1e18
            }
        );

        // Amount is restricted by the collateral in the loan
        _arbTake(
           {
               from:             _taker,
               borrower:         _borrower,
               kicker:           _lender,
               index:            _i9_91,
               collateralArbed:  2 * 1e18,
               quoteTokenAmount: 14.503461444385064128 * 1e18,
               bondChange:       0.145034614443850641 * 1e18,
               isReward:         true,
               lpAwardTaker:     5.259881215780552826000000000 * 1e27,
               lpAwardKicker:    0.143102227509983165000000000 * 1e27
           }
        );

        _assertLenderLpBalance(
           {
               lender:      _taker,
               index:       _i9_91,
               lpBalance:   5.259881215780552826000000000 * 1e27,
               depositTime: _startTime + 100 days + 6.5 hours
           }
        );
        _assertLenderLpBalance(
           {
               lender:      _lender,
               index:       _i9_91,
               lpBalance:   2_000.143102227509983165000000000 * 1e27, // rewarded with LPs in bucket
               depositTime: _startTime + 100 days + 6.5 hours
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_005.402983443290535991000000000 * 1e27,
               collateral:   2 * 1e18,
               deposit:      2_012.648657091693304514 * 1e18,
               exchangeRate: 1.013503541960817259000463129 * 1e27
           }
        );
        // reserves should remain the same after arb take
        _assertReserveAuction(
           {
               reserves:                   25.295951940381566551 * 1e18,
               claimableReserves :         0,
               claimableReservesRemaining: 0,
               auctionPrice:               0,
               timeRemaining:              0
           }
        );
        _assertBorrower(
           {
               borrower:                  _borrower,
               borrowerDebt:              6.805228224892631302 * 1e18,
               borrowerCollateral:        0,
               borrowert0Np:              10.115967548076923081 * 1e18,
               borrowerCollateralization: 0
           }
        );
        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18, // bond size remains the same, kicker was rewarded with LPs
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6.5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      7.251730722192532064 * 1e18,
               debtInAuction:     6.805228224892631302 * 1e18,
               thresholdPrice:    0,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        // Arb take should fail on an auction without any remaining collateral to auction
        _assertArbTakeInsufficentCollateralRevert(
           {
               from:     _taker,
               borrower: _borrower,
               index:    _i9_91
           }
        );
    }

    function testArbTakeDebtRestrict() external tearDown {

        skip(5 hours);

        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      20.510991876004636192 * 1e18,
               debtInAuction:     19.778456451861613480 * 1e18,
               thresholdPrice:    9.889482233342512889 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _addLiquidity(
            {
                from:    _lender,
                amount:  25_000 * 1e18,
                index:   _i1505_26,
                lpAward: 25_000 * 1e27,
                newLup:  1_505.263728469068226832 * 1e18
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778964466685025779 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 152.208547722958917634 * 1e18
            }
        );

        // Amount is restricted by the debt in the loan
        _arbTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i1505_26,
                collateralArbed:  1.031812215971460994 * 1e18,
                quoteTokenAmount: 21.163491979352977584 * 1e18,
                bondChange:       0.195342779771472726 * 1e18,
                isReward:         false,
                lpAwardTaker:     1_531.986011313779866428534379038 * 1e27,
                lpAwardKicker:    0
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0.968187784028539006 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   1_531.986011313779866428534379038 * 1e27,
                depositTime: block.timestamp
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i1505_26,
                lpBalance:   25_000 * 1e27,
                depositTime: block.timestamp
            }
        );
        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    26_531.986011313779866428534379038 * 1e27,
                collateral:   1.031812215971460994 * 1e18,
                deposit:      24_978.836508020647022417 * 1e18,
                exchangeRate: 0.999999999999999999999729424 * 1e27
            }
        );

        _assertReserveAuction(
            {
                reserves:                   25.482262302272484525 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );
    }

    function testArbTakeDepositRestrict() external tearDown {

        skip(5 hours);

        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      20.510991876004636192 * 1e18,
               debtInAuction:     19.778456451861613480 * 1e18,
               thresholdPrice:    9.889482233342512889 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _addLiquidity(
            {
                from:    _lender,
                amount:  15.0 * 1e18,
                index:   _i1505_26,
                lpAward: 15.0 * 1e27,
                newLup:  9.721295865031779605 * 1e18
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778964466685025779 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.982993410135902682 * 1e18
            }
        );

        // Amount is restricted by the deposit in the bucket
        _arbTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i1505_26,
                collateralArbed:  0.731315193857015473 * 1e18,
                quoteTokenAmount: 15.000000000000000000 * 1e18,
                bondChange:       0.15 * 1e18,
                isReward:         false,
                lpAwardTaker:     1_085.822235391290531116686016658 * 1e27,
                lpAwardKicker:    0
            }
        );

        _assertAuction(
           AuctionParams({
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
               thresholdPrice:    4.858174346779663271 * 1e18,
               neutralPrice:      0
           })
        );

        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    1_100.822235391290531116686016658 * 1e27,
                collateral:   0.731315193857015473 * 1e18,
                deposit:      0,
                exchangeRate: 0.999999999999999999966196099 * 1e27
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              6.163491979352977583 * 1e18,
                borrowerCollateral:        1.268684806142984527 * 1e18,
                borrowert0Np:              5.108498139847549815 * 1e18,
                borrowerCollateralization: 2.001018319047304755  * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   1_085.822235391290531116686016658 * 1e27,
                depositTime: block.timestamp
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i1505_26,
                lpBalance:   15.0 * 1e27,
                depositTime: block.timestamp
            }
        );
    }

    function testArbTakeGTNeutralPrice() external tearDown {

        skip(3 hours);

        _addLiquidity(
            {
                from:    _lender,
                amount:  1_000 * 1e18,
                index:   _i10016,
                lpAward: 1_000 * 1e27,
                newLup:  9.721295865031779605 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i10016,
                lpBalance:   0,
                depositTime: 0
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i10016,
                lpBalance:   1_000 * 1e27,
                depositTime: block.timestamp
            }
        );

        _assertBucket(
            {
                index:        _i10016,
                lpBalance:    1_000 * 1e27,
                collateral:   0,
                deposit:      1_000 * 1e18,
                exchangeRate: 1.0 * 1e27
            }
        );
        
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778761259189860403 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.983003509435146965 * 1e18
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      82.043967504018544800 * 1e18,
                debtInAuction:     19.778761259189860403 * 1e18,
                thresholdPrice:    9.889380629594930201 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778761259189860403 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.983003509435146965 * 1e18
            }
        );

        _arbTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i10016,
                collateralArbed:  0.257950403803869741 * 1e18,
                quoteTokenAmount: 21.163274547333150631 * 1e18,
                bondChange:       0.195342779771472726 * 1e18,
                isReward:         false,
                lpAwardTaker:     2_562.597355112798042001349648580 * 1e27,
                lpAwardKicker:    0
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i10016,
                lpBalance:   2_562.597355112798042001349648580 * 1e27, // arb taker was rewarded LPBs in arbed bucket
                depositTime: _startTime + 100 days + 3 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i10016,
                lpBalance:   1_000 * 1e27,
                depositTime: _startTime + 100 days + 3 hours
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0 // kicker was penalized
            }
        );
        _assertBucket(
            {
                index:        _i10016,
                lpBalance:    3_562.597355112798042001349648580 * 1e27,       // LP balance in arbed bucket increased with LPs awarded for arb taker
                collateral:   0.257950403803869741 * 1e18,          // arbed collateral added to the arbed bucket
                deposit:      978.836725452666849368 * 1e18,        // quote token amount is diminished in arbed bucket
                exchangeRate: 1.000000000000000000007160522 * 1e27
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.742049596196130259 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
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
    }

    function testArbTakeReverts() external tearDown {

        // should revert if borrower not auctioned
        _assertArbTakeNoAuction(
            {
                from:     _lender,
                borrower: _borrower2,
                index:    _i9_91
            }
        );

        // should revert if auction in grace period
        _assertArbTakeAuctionInCooldownRevert(
            {
                from:     _lender,
                borrower: _borrower,
                index:    _i9_91
            }
        );

        skip(2.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2.5 hours,
                kickMomp:          9.818751856078723036 * 1e18, 
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      116.027691555080513536 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18,
                thresholdPrice:    9.889355228821139433 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778710457642278866 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.983006034276170567 * 1e18
            }
        );

        // should revert if bucket deposit is 0
        _assertArbTakeAuctionInsufficientLiquidityRevert(
            {
                from:     _taker,
                borrower: _borrower,
                index:    _i100_33
            }
        );

        // should revert if auction price is greater than the bucket price
        _assertArbTakeAuctionPriceGreaterThanBucketPriceRevert(
            {
                from:     _taker,
                borrower: _borrower,
                index:    _i9_91
            }
        );

        skip(4 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, 7777);
        }

        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertArbTakeDebtUnderMinPoolDebtRevert(
            {
                from:     _taker,
                borrower: _borrower,
                index:    _i9_91
            }
        );
    }
}
