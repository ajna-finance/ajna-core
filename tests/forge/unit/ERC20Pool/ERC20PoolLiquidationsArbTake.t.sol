// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsArbTakeTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;
    address internal _taker;

    function setUp() external {
        _startTest();

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
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower pledge collateral and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     18.55 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral and borrows
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     7_980 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.655275000000000004 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             72_996.666666666666667 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 856.520639388314730224 * 1e18,
                poolDebt:             8_006.240913461538465230 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.312045673076923262 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.567836538461538470 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 1.006837802655209676 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 1.170228147822941070 * 1e18
        });

        _assertReserveAuction({
            reserves:                   11.02424679487179823 * 1e18,
            claimableReserves :         11.024173798205131563 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        // should revert if there's no auction started
        _assertArbTakeNoAuctionRevert({
            from:     _lender,
            borrower: _borrower,
            index:    _i9_91
        });

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
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.823940596160099025 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993139541901194031 * 1e18
        });
        
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.823940596160099024 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.210458053887159482 * 1e18,
            transferAmount: 0.210458053887159482 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      2_678.850705284056820992 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.210458053887159482 * 1e18
        });
    }

    function testArbTakeCollateralRestrict() external tearDown {
        // add liquidity to accrue interest and update reserves before arb take
        _addLiquidityWithPenalty({
            from:        _lender1,
            amount:      1 * 1e18,
            amountAdded: 0.999958904109589041 * 1e18,
            index:       _i9_52,
            lpAward:     0.999958904109589041 * 1e18,
            newLup:      9.721295865031779605 * 1e18
        });

        skip(6.5 hours);

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   1_999.908675799086758 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758 * 1e18,
            collateral:   0,
            deposit:      2_010.338097446880098916 * 1e18,
            exchangeRate: 1.005214948949419476 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824569145766177224 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993106381117379594 * 1e18
        });

        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758 * 1e18,
            collateral:   0,
            deposit:      2_010.338097446880098916 * 1e18,
            exchangeRate: 1.005214948949419476 * 1e18
        });
        _assertReserveAuction({
            reserves:                   27.588663449022222983 * 1e18,
            claimableReserves :         27.588590357490802582 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18, // should be the same after arb take, kicker will be rewarded with LP
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6.5 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      8.799359199504876220 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824569145766177224 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993106381117379594 * 1e18
        });

        // Amount is restricted by the collateral in the loan
        _arbTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i9_91,
            collateralArbed:  2 * 1e18,
            quoteTokenAmount: 17.598718399009752440 * 1e18,
            bondChange:       0.102293476350866899 * 1e18,
            isReward:         true,
            lpAwardTaker:     2.224045908450701035 * 1e18,
            lpAwardKicker:    0.101762465718392482 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i9_91,
            lpBalance:   2.224045908450701035 * 1e18,
            depositTime: _startTime + 100 days + 6.5 hours
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   2_000.010438264805150482 * 1e18, // rewarded with LP in bucket
            depositTime: _startTime + 100 days + 6.5 hours
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_002.234484173255851517 * 1e18,
            collateral:   2 * 1e18,
            deposit:      1_992.848051181875920483 * 1e18,
            exchangeRate: 1.005218138423884932 * 1e18
        });
        // reserves should remain the same after arb take
        _assertReserveAuction({
            reserves:                   27.745855492035450694 * 1e18,
            claimableReserves :         27.745782417768541063 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1.446226944275346019 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18, // bond size remains the same, kicker was rewarded with LP
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6.5 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      8.799359199504876220 * 1e18,
                debtInAuction:     1.446226944275346019 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );

        // Arb take should fail on an auction without any remaining collateral to auction
        _assertArbTakeInsufficentCollateralRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });
    }

    function testArbTakeDebtRestrict() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  25_000 * 1e18,
            index:   _i1505_26,
            lpAward: 24_998.972602739726025 * 1e18,
            newLup:  1_505.263728469068226832 * 1e18
        });
        
        skip(5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      14.798699214786891216 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824424093994278183 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 153.775644073335900060 * 1e18
        });

        // Amount is restricted by the debt in the loan
        _arbTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  1.293728839166329275 * 1e18,
            quoteTokenAmount: 19.145503956317913307 * 1e18,
            bondChange:       0.210458053887159482 * 1e18,
            isReward:         false,
            lpAwardTaker:     1_928.254085210578490012 * 1e18,
            lpAwardKicker:    0
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0.706271160833670725 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   1_928.254085210578490012 * 1e18,
            depositTime: block.timestamp
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   24_998.972602739726025 * 1e18,
            depositTime: block.timestamp - 5 hours
        });
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    26_927.226687950304515012 * 1e18,
            collateral:   1.293728839166329275 * 1e18,
            deposit:      24_979.872564270547957314 * 1e18,
            exchangeRate: 1.000001818694226453 * 1e18
        });
        _assertReserveAuction({
            reserves:                   29.177641507437069653 * 1e18,
            claimableReserves :         29.177543436900114558 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
    }

    function testArbTakeDepositRestrict() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  15.0 * 1e18,
            index:   _i1505_26,
            lpAward: 14.999383561643835615 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        skip(5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      14.798699214786891216 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824424093994278183 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993114033507675628 * 1e18
        });

        // Amount is restricted by the deposit in the bucket
        _arbTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  1.013563418378406048 * 1e18,
            quoteTokenAmount: 14.999420163693234888 * 1e18,
            bondChange:       0.167698615545495474 * 1e18,
            isReward:         false,
            lpAwardTaker:     1_510.677143614314927782 * 1e18,
            lpAwardKicker:    0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.042759438341664008 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.042759438341664008 * 1e18,
                auctionPrice:      14.798699214786891216 * 1e18,
                debtInAuction:     4.076551853619286508 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    1_525.676527175958763397 * 1e18,
            collateral:   1.013563418378406048 * 1e18,
            deposit:      0.000000000000000005 * 1e18,
            exchangeRate: 1.000002440236910328 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4.076551853619286508 * 1e18,
            borrowerCollateral:        0.986436581621593952 * 1e18,
            borrowert0Np:              4.532015687052148028 * 1e18,
            borrowerCollateralization: 2.261866770281955326 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   1_510.677143614314927782 * 1e18,
            depositTime: block.timestamp
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   14.999383561643835615 * 1e18,
            depositTime: block.timestamp - 5 hours
        });
    }

    function testArbTakeGTNeutralPrice() external tearDown {
        _addLiquidity({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   _i100_33,
            lpAward: 999.958904109589041 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        skip(3 hours);

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i100_33,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i100_33,
            lpBalance:   999.958904109589041 * 1e18,
            depositTime: block.timestamp - 3 hours
        });
        _assertBucket({
            index:        _i100_33,
            lpBalance:    999.958904109589041 * 1e18,
            collateral:   0,
            deposit:      999.958904109589041 * 1e18,
            exchangeRate: 1.0 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                referencePrice:    10.464260567515846957 * 1e18,
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      29.597398429573782432 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824230693370372191 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993124236786461296 * 1e18
        });

        _arbTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i100_33,
            collateralArbed:  0.646857773749979766 * 1e18,
            quoteTokenAmount: 19.145307256945244166 * 1e18,
            bondChange:       0.210458053887159482 * 1e18,
            isReward:         false,
            lpAwardTaker:     45.755398933810678651 * 1e18,
            lpAwardKicker:    0
        });

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i100_33,
            lpBalance:   45.755398933810678651 * 1e18, // arb taker was rewarded LPBs in arbed bucket
            depositTime: _startTime + 100 days + 3 hours
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i100_33,
            lpBalance:   999.958904109589041 * 1e18,
            depositTime: _startTime + 100 days
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0 // kicker was penalized
        });
        _assertBucket({
            index:        _i100_33,
            lpBalance:    1_045.714303043399719651 * 1e18,    // LP balance in arbed bucket increased with LP awarded for arb taker
            collateral:   0.646857773749979766 * 1e18,        // arbed collateral added to the arbed bucket
            deposit:      980.815041463682283936 * 1e18,      // quote token amount is diminished in arbed bucket
            exchangeRate: 1.000001444670408504 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1.353142226250020234 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testArbTakeReverts() external tearDown {
        // should revert if taken from same block when kicked
        _assertArbTakeAuctionNotTakeableRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_62
        });

        // should revert if borrower not auctioned
        _assertArbTakeNoAuction({
            from:     _lender,
            borrower: _borrower2,
            index:    _i9_91
        });

        skip(2.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.210458053887159482 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 2.5 hours,
                referencePrice:    10.464260567515846957 * 1e18, 
                totalBondEscrowed: 0.210458053887159482 * 1e18,
                auctionPrice:      35.197436798019505000 * 1e18,
                debtInAuction:     18.823940596160099025 * 1e18,
                thresholdPrice:    9.411970298080049512 * 1e18,
                neutralPrice:      10.464260567515846957 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.824182343524862490 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.321891886608378937 * 1e18,
            borrowerCollateralization: 0.993126787622537163 * 1e18
        });

        // borrower cannot repay amidst auction
        _assertRepayAuctionActiveRevert({
            from:      _borrower,
            maxAmount: 10 * 1e18
        });

        // should revert if bucket deposit is 0
        _assertArbTakeAuctionInsufficientLiquidityRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i100_33
        });

        // should revert if auction price is greater than the bucket price
        _assertArbTakeAuctionPriceGreaterThanBucketPriceRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });

        skip(4 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, MAX_FENWICK_INDEX);
        }

        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertArbTakeDebtUnderMinPoolDebtRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });

        // ensure zero bid reverts
        skip(3 days);
        _assertArbTakeZeroBidRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_52
        });
    }
}
