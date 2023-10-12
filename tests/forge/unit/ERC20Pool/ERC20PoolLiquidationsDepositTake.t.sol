// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/ERC20Pool.sol';
import 'src/interfaces/pool/commons/IPoolErrors.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsDepositTakeTest is ERC20HelperContract {

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

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     19.25 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
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
                htp:                  9.634254807692307697 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 823.649613971736296163 * 1e18,
                poolDebt:             8_006.941586538461542154 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.347079326923077108 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.268509615384615394 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 1.009034539679184679 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.200228999102245332 * 1e18,
            borrowerCollateralization: 1.217037273735858713 * 1e18
        });
        _assertReserveAuction({
            reserves:                   7.691586538461542154 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        // should revert if there's no auction started
        _assertDepositTakeNoAuctionRevert({
            from:     _lender,
            borrower: _borrower,
            index:    _i9_91
        });

        // Skip to make borrower undercollateralized
        skip(250 days);

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
                thresholdPrice:    9.969909752188970169 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.939819504377940339 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.975063576969429891 * 1e18
        });
        
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.939819504377940339 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.302693237371837952 * 1e18,
            transferAmount: 0.302693237371837952 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      2_939.744240396328951808 * 1e18,
                debtInAuction:     19.939819504377940339 * 1e18,
                thresholdPrice:    9.969909752188970169 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.302693237371837952 * 1e18
        });
    }

    function testDepositTakeCollateralRestrict() external tearDown {
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
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_026.346200779800152000 * 1e18,
            exchangeRate: 1.013173100389900076 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.940485314261408832 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.975031019739436493 * 1e18
        });

        // add liquidity to accrue interest and update reserves before deposit take
        _addLiquidityWithPenalty({
            from:        _lender1,
            amount:      1 * 1e18,
            amountAdded: 0.999876712328767123 * 1e18,
            index:       _i9_52,
            lpAward:     0.999873480092787187 * 1e18,
            newLup:      9.721295865031779605 * 1e18
        });

        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_026.352751237661440000 * 1e18,
            exchangeRate: 1.013176375618830720 * 1e18
        });
        _assertReserveAuction({
            reserves:                   49.575600446873147197 * 1e18,
            claimableReserves :         8.144637039662123068 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 6.5 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      9.656329662156355672 * 1e18,
                debtInAuction:     19.940485314261408832 * 1e18,
                thresholdPrice:    9.970242657130704416 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.940485314261408832 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.975031019739436493 * 1e18
        });

        // Amount is restricted by the collateral in the loan
        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i9_91,
            collateralArbed:  2 * 1e18,
            quoteTokenAmount: 19.834369686871824148 * 1e18,
            bondChange:       0.301092473301020371 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    0.297176760677150868 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   2_000.297176760677150868 * 1e18,
            depositTime: _startTime + 250 days + 6.5 hours
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000.297176760677150868 * 1e18,
            collateral:   2 * 1e18,
            deposit:      2_006.819474024090636225 * 1e18,
            exchangeRate: 1.013176375618830721 * 1e18
        });
        // reserves should remain the same after deposit take
        _assertReserveAuction({
            reserves:                   49.575600446873147192 * 1e18,
            claimableReserves :         8.242303445263254296 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 6.5 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      9.656329662156355672 * 1e18,
                debtInAuction:     0.407208100690605057 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        ); 
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0.407208100690605057 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        // deposit take should fail on an auction without any remaining collateral to auction
        _assertDepositTakeInsufficentCollateralRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });
    }

    function testDepositTakeDebtRestrict() external tearDown {
        skip(5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      16.239945994830783896 * 1e18,
                debtInAuction:     19.939819504377940339 * 1e18,
                thresholdPrice:    9.970165831926765787 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );

        _addLiquidity({
            from:    _lender,
            amount:  25_000 * 1e18,
            index:   _i1505_26,
            lpAward: 25_000 * 1e18,
            newLup:  1_505.263728469068226832 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.940331663853531575 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 150.976799568254654687 * 1e18
        });
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    25_000 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      25_000 * 1e18,
            exchangeRate: 1.0 * 1e18
        });

        // Amount is restricted by the debt in the loan
        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  0.013555739562620698 * 1e18,
            quoteTokenAmount: 20.404963076186087933 * 1e18,
            bondChange:       0.302693237371837952 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1.986444260437379302 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   25_000 * 1e18,
            depositTime: block.timestamp
        });
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    25_000 * 1e18,
            collateral:   0.013555739562620698 * 1e18,
            deposit:      24_979.595036923813911959 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertReserveAuction({
            reserves:                   50.333588303732929197 * 1e18,
            claimableReserves :         9.002620819943559986 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
    }

    function testDepositTakeDepositRestrict() external tearDown {
        skip(5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      16.239945994830783896 * 1e18,
                debtInAuction:     19.939819504377940339 * 1e18,
                thresholdPrice:    9.970165831926765787 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );

        _addLiquidity({
            from:    _lender,
            amount:  15.0 * 1e18,
            index:   _i1505_26,
            lpAward: 15.0 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.940331663853531575 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.975038532849870233 * 1e18
        });

        // Amount is restricted by the deposit in the bucket in the loan
        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  0.009965031187761219 * 1e18,
            quoteTokenAmount: 14.999999999999999995 * 1e18,
            bondChange:       0.227705098312484220 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.074988139059353732 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.074988139059353732 * 1e18,
                auctionPrice:      16.239945994830783896 * 1e18,
                debtInAuction:     5.281889311322257910 * 1e18,
                thresholdPrice:    2.654169094563588010 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    15 * 1e18,
            collateral:   0.009965031187761219 * 1e18,
            deposit:      0.000000000000000005 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5.281889311322257910 * 1e18,
            borrowerCollateral:        1.990034968812238781 * 1e18,
            borrowert0Np:              2.954082977863112822 * 1e18,
            borrowerCollateralization: 3.662651292618643252 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   15.0 * 1e18,
            depositTime: block.timestamp
        });
    }

    function testDepositTakeGTNeutralPrice() external tearDown {
        skip(3 hours);

        _addLiquidity({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   _i10016,
            lpAward: 1_000 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i10016,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i10016,
            lpBalance:   1_000 * 1e18,
            depositTime: block.timestamp
        });
        _assertBucket({
            index:        _i10016,
            lpBalance:    1_000 * 1e18,
            collateral:   0,
            deposit:      1_000 * 1e18,
            exchangeRate: 1.0 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                referencePrice:    11.483375939048159968 * 1e18,
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      32.479891989661567792 * 1e18,
                debtInAuction:     19.940126798484719991 * 1e18,
                thresholdPrice:    9.970063399242359995 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.940126798484719991 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.975048550420503383 * 1e18
        });

        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i10016,
            collateralArbed:  0.002037113782225481 * 1e18,
            quoteTokenAmount: 20.404753437231397559 * 1e18,
            bondChange:       0.302693237371837952 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });
        
        // deposit taker wasn't rewarded any LPBs in arbed bucket
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i10016,
            lpBalance:   0,     
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i10016,
            lpBalance:   1_000 * 1e18,
            depositTime: _startTime + 250 days + 3 hours
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0 // kicker was penalized
        });
        _assertBucket({
            index:        _i10016,
            lpBalance:    1_000 * 1e18,      // LP balance in arbed bucket increased with LP awarded for deposit taker
            collateral:   0.002037113782225481 * 1e18,          // arbed collateral added to the arbed bucket
            deposit:      979.595246562768594325 * 1e18,        // quote token amount is diminished in arbed bucket
            exchangeRate: 1.000000000000000001 * 1e18
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
            borrowerCollateral:        1.997962886217774519 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testDepositTakeReverts() external tearDown {
        // should revert if taken from same block when kicked
        _assertDepositTakeAuctionNotTakeableRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_72
        });

        skip(2.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.302693237371837952 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 2.5 hours,
                referencePrice:    11.483375939048159968 * 1e18, 
                totalBondEscrowed: 0.302693237371837952 * 1e18,
                auctionPrice:      38.625318648625422832 * 1e18,
                debtInAuction:     19.939819504377940339 * 1e18,
                thresholdPrice:    9.970037791235694161 * 1e18,
                neutralPrice:      11.483375939048159968 * 1e18
            })
        );

        // should revert if bucket deposit is 0
        _assertDepositTakeAuctionInsufficientLiquidityRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i100_33
        });

        // should revert if auction price is greater than the bucket price
        _assertDepositTakeAuctionPriceGreaterThanBucketPriceRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });

        skip(4 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint256 i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, MAX_FENWICK_INDEX);
        }

        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertDepositTakeDebtUnderMinPoolDebtRevert({
            from:     _taker,
            borrower: _borrower,
            index:    _i9_91
        });
    }
}

contract ERC20PoolLiquidationsDepositTakeRegressionTest is ERC20HelperContract {

    function setUp() external {
        _startTest();
    }

    function testDepositTakeOnAuctionPriceZero() external {
        // initialize kicker to be rewarded after bucket take
        address actor1 = makeAddr("actor1");
        _mintQuoteAndApproveTokens(actor1, type(uint256).max);
        _mintCollateralAndApproveTokens(actor1, type(uint256).max);

        // initialize borrower to be kicked and take
        address actor2 = makeAddr("actor2");
        _mintQuoteAndApproveTokens(actor2, type(uint256).max);
        _mintCollateralAndApproveTokens(actor2, type(uint256).max);

        // initialize taker
        address actor4 = makeAddr("actor4");
        _mintQuoteAndApproveTokens(actor4, type(uint256).max);
        _mintCollateralAndApproveTokens(actor4, type(uint256).max);

        assertEq(_priceAt(2572), 2_697.999235705754194133 * 1e18);
        _addInitialLiquidity({
            from:   actor2,
            amount: 1_791_670_358_647.909977170293982862 * 1e18,
            index:  2572
        });
        _pool.updateInterest();
        _drawDebtNoLupCheck({
            from:               actor2,
            borrower:           actor2,
            amountToBorrow:     895_835_179_323.954988585146991431 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 333_688_779.021420071719646593 * 1e18
        });
        // skip to make loan undercollateralized
        skip(100 days);

        // kicker kicks undercollateralized loan
        changePrank(actor1);
        _pool.updateInterest();
        _pool.kick(actor2, 7388);
        skip(100 days);

        changePrank(actor4);
        _pool.updateInterest();

        // assert auction before bucket take, enough time passed so auction price is zero
        _assertAuction(
            AuctionParams({
                borrower:          actor2,
                active:            true,
                kicker:            actor1,
                bondSize:          13_799_909_500.935435603423349661 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    3_137.845063437099084063 * 1e18,
                totalBondEscrowed: 13_799_909_500.935435603423349661 * 1e18,
                auctionPrice:      0,
                debtInAuction:     920_341_611_662.285708998644615657 * 1e18,
                thresholdPrice:    2_758.083788017359002804 * 1e18,
                neutralPrice:      3_137.845063437099084063 * 1e18  // was 2_860.503207254858101199
            })
        );

        // assert kicker balances in bucket before bucket take auction with auction price zero
        _assertLenderLpBalance({
            lender:      actor1,
            index:       2572,
            lpBalance:   0,
            depositTime: 0
        });

        ERC20Pool(address(_pool)).bucketTake(actor2, true, 2572);

        // ensure some debt was covered by the take
        _assertAuction(
            AuctionParams({
                borrower:          actor2,
                active:            true,
                kicker:            actor1,
                bondSize:          13_799_909_500.935435603423349661 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    3_137.845063437099084063 * 1e18,
                totalBondEscrowed: 13_799_909_500.935435603423349661 * 1e18,
                auctionPrice:      0,
                debtInAuction:     33_716_280_531.11637887639485531 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      3_137.845063437099084063 * 1e18  // was 2_860.503207254858101199
            })
        );
        // ensure kicker was rewarded since bucket price taken was below the neutral price
        _assertLenderLpBalance({
            lender:      actor1,
            index:       2572,  // 2697.99923570534
            lpBalance:   13512526017.591065704389485704 * 1e18,
            depositTime: _startTime + 200 days
        });
    }

    function testDepositTakeRevertOnCollateralCalculatedAsZero() external {
        // initialize borrower to be kicked and take
        address actor0 = makeAddr("actor0");
        _mintQuoteAndApproveTokens(actor0, type(uint256).max);
        _mintCollateralAndApproveTokens(actor0, type(uint256).max);

        // initialize kicker to be rewarded after bucket take
        address actor2 = makeAddr("actor2");
        _mintQuoteAndApproveTokens(actor2, type(uint256).max);
        _mintCollateralAndApproveTokens(actor2, type(uint256).max);

        // initialize taker
        address actor3 = makeAddr("actor3");
        _mintQuoteAndApproveTokens(actor3, type(uint256).max);
        _mintCollateralAndApproveTokens(actor3, type(uint256).max);

        changePrank(actor0);
        _addInitialLiquidity({
            from:   actor0,
            amount: 1_927_834_830_600.755456044194881800 * 1e18,
            index:  2572
        });
        _pool.updateInterest();
        _drawDebtNoLupCheck({
            from:               actor0,
            borrower:           actor0,
            amountToBorrow:     963_917_415_300.377728022097440900 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 359_048_665.215178534787974447 * 1e18
        });
        // skip to make loan undercollateralized
        skip(100 days);

        // kicker kicks undercollateralized loan
        changePrank(actor2);
        _pool.updateInterest();
        _pool.kick(actor0, 7388);
        skip(70 hours);

        changePrank(actor3);
        _pool.updateInterest();
        // taker adds a tiny amount of quote token in bucket to take
        _addLiquidityNoEventCheck({
            from:   actor3,
            amount: 3,
            index:  2571
        });

        // assert bucket before take
        _assertBucket({
            index:        2571,
            lpBalance:    3,
            collateral:   0,
            deposit:      3, // tiny deposit that cannot cover one unit of collateral, collateral to take will be calculated as 0
            exchangeRate: 1 * 1e18
        });

        changePrank(actor2);
        _pool.updateInterest();

        // bucket take with bucket 2571 should revert as deposit of 3 cannot cover at least one unit of collateral
        _assertDepositTakeZeroBidRevert({
            from:     actor2,
            borrower: actor0,
            index:    2571
        });

        // assert bucket after take
        _assertBucket({
            index:        2571,
            lpBalance:    3,
            collateral:   0,
            deposit:      3,
            exchangeRate: 1 * 1e18
        });
    }
}
