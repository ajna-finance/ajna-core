// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/base/PoolHelper.sol';

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
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      314.200059394519137152 * 1e18,
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

        skip(6 hours);

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
               borrowerDebt:              19.779066071215516749 * 1e18,
               borrowerCollateral:        2 * 1e18,
               borrowert0Np:              10.115967548076923081 * 1e18,
               borrowerCollateralization: 0.982988360525190378 * 1e18
           }
        );

        // add liquidity to accrue interest and update reserves before arb take
        _addLiquidity(
           {
               from:   _lender1,
               amount: 1 * 1e18,
               index:  _i9_52,
               newLup: 9.721295865031779605 * 1e18
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000 * 1e27,
               collateral:   0,
               deposit:      2_027.006589100074752000 * 1e18,
               exchangeRate: 1.013503294550037376000000000 * 1e27
           }
        );
        _assertReserveAuction(
           {
               reserves:                   23.908406501703106407 * 1e18,
               claimableReserves :         0,
               claimableReservesRemaining: 0,
               auctionPrice:               0,
               timeRemaining:              0
           }
        );

        _assertAuction(
           AuctionState({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18, // should be the same after arb take, kicker will be rewarded with LPs
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      9.818751856078723040 * 1e18,
               debtInAuction:     19.779066071215516749 * 1e18,
               thresholdPrice:    9.889533035607758374 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.779066071215516749 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.982988360525190378 * 1e18
            }
        );

        // Amount is restricted by the collateral in the loan
        _arbTake(
           {
               from:             _taker,
               borrower:         _borrower,
               index:            _i9_91,
               collateralArbed:  2 * 1e18,
               quoteTokenAmount: 19.637503712157446080 * 1e18,
               bondChange:       0.196375037121574461 * 1e18,
               isReward:         true
           }
        );

        _assertLenderLpBalance(
           {
               lender:      _taker,
               index:       _i9_91,
               lpBalance:   0.194243053548020465062464152 * 1e27,
               depositTime: _startTime + 100 days + 6 hours
           }
        );
        _assertLenderLpBalance(
           {
               lender:      _lender,
               index:       _i9_91,
               lpBalance:   2_000.193758656905756398832457540 * 1e27, // rewarded with LPs in bucket
               depositTime: _startTime + 100 days + 6 hours
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000.388001710453776863894921692 * 1e27,
               collateral:   2 * 1e18,
               deposit:      2_007.565460425038880381 * 1e18,
               exchangeRate: 1.013503294550037375999999999 * 1e27
           }
        );
        // reserves should remain the same after arb take
        _assertReserveAuction(
           {
               reserves:                   23.908406501703106402 * 1e18,
               claimableReserves :         0,
               claimableReservesRemaining: 0,
               auctionPrice:               0,
               timeRemaining:              0
           }
        );
        _assertBorrower(
           {
               borrower:                  _borrower,
               borrowerDebt:              0.337937396179645130 * 1e18,
               borrowerCollateral:        0,
               borrowert0Np:              10.115967548076923081 * 1e18,
               borrowerCollateralization: 0
           }
        );
        _assertAuction(
           AuctionState({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18, // bond size remains the same, kicker was rewarded with LPs
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      9.818751856078723040 * 1e18,
               debtInAuction:     0.337937396179645130 * 1e18,
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
           AuctionState({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      19.637503712157446080 * 1e18,
               debtInAuction:     19.778456451861613480 * 1e18,
               thresholdPrice:    9.889482233342512889 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _addLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i1505_26,
                newLup: 1_505.263728469068226832 * 1e18
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
                index:            _i1505_26,
                collateralArbed:  1.007203601669595219 * 1e18,
                quoteTokenAmount: 19.778964466685025779 * 1e18,
                bondChange:       0.195342779771472726 * 1e18,
                isReward:         false
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0 * 1e18,
                borrowerCollateral:        0.992796398330404781 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   1_496.328084309964105327000000000 * 1e27,
                depositTime: block.timestamp
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i1505_26,
                lpBalance:   25_000.0 * 1e27,
                depositTime: block.timestamp
            }
        );
        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    26_496.328084309964105327000000000 * 1e27,
                collateral:   1.007203601669595219 * 1e18,
                deposit:      24_980.221035533314974222 * 1e18,
                exchangeRate: 0.999999999999999999999693447 * 1e27
            }
        );

        _assertReserveAuction(
            {
                reserves:                   24.097734789604532720 * 1e18,
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
           AuctionState({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.195342779771472726 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.195342779771472726 * 1e18,
               auctionPrice:      19.637503712157446080 * 1e18,
               debtInAuction:     19.778456451861613480 * 1e18,
               thresholdPrice:    9.889482233342512889 * 1e18,
               neutralPrice:      10.255495938002318100 * 1e18
           })
        );

        _addLiquidity(
            {
                from:   _lender,
                amount: 15.0 * 1e18,
                index:  _i1505_26,
                newLup: 9.721295865031779605 * 1e18
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

        // Amount is restricted by the deposit in the bucket in the loan
        _arbTake(
            {
                from:             _taker,
                borrower:         _borrower,
                index:            _i1505_26,
                collateralArbed:  0.763844540521390261 * 1e18,
                quoteTokenAmount: 15.0 * 1e18,
                bondChange:       0.15 * 1e18,
                isReward:         false
            }
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
               thresholdPrice:    3.865989855920480453 * 1e18,
               neutralPrice:      0
           })
        );

        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    1_149.787481035970172219000000000 * 1e27,
                collateral:   0.763844540521390261 * 1e18,
                deposit:      0,
                exchangeRate: 0.999999999999999999995151547 * 1e27
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              4.778964466685025779 * 1e18,
                borrowerCollateral:        1.236155459478609739 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 2.514568384121424074 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   1_134.787481035970172219000000000 * 1e27,
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
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  _i10016,
                newLup: 9.721295865031779605 * 1e18
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
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      78.550014848629784288 * 1e18,
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
                index:            _i10016,
                collateralArbed:  0.251798313435135887 * 1e18,
                quoteTokenAmount: 19.778761259189860403 * 1e18,
                bondChange:       0.195342779771472726 * 1e18,
                isReward:         false
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i10016,
                lpBalance:   2_502.359445445046938391 * 1e27, // arb taker was rewarded LPBs in arbed bucket
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
                lpBalance:    3_502.359445445046938391 * 1e27,       // LP balance in arbed bucket increased with LPs awarded for arb taker
                collateral:   0.251798313435135887 * 1e18,          // arbed collateral added to the arbed bucket
                deposit:      980.221238740810139596 * 1e18,        // quote token amount is diminished in arbed bucket
                exchangeRate: 1.000000000000000000007614372 * 1e27
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.748201686564864113 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
    }

    function testArbTakeReverts() external tearDown {

        // should revert if auction in grace period
        _assertArbTakeAuctionInCooldownRevert(
            {
                from:     _lender,
                borrower: _borrower,
                index:    _i9_91
            }
        );

        skip(2 hours);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2 hours,
                kickMomp:          9.818751856078723036 * 1e18, 
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      157.100029697259568576 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18,
                thresholdPrice:    9.889329828112590306 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778659656225180612 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.983008559123679212 * 1e18
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
