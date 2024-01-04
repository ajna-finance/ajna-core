// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract } from './ERC20DSTestPlus.sol';

import 'src/ERC20Pool.sol';
import 'src/interfaces/pool/commons/IPoolEvents.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsSettleTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintQuoteAndApproveTokens(_lender,  120_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_001 * 1e18);
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
            amount:     18.65 * 1e18,
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
                htp:                  9.707325000000000004 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             72_996.666666666666667 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 856.531347837213447051 * 1e18,
                poolDebt:             8_006.341009615384619076 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.317050480769230954 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.667932692307692316 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 1.001439208539095951 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.170228147822941070 * 1e18
        });
        _assertReserveAuction({
            reserves:                   11.024342948717952076 * 1e18,
            claimableReserves :         11.024269952051285409 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

    }
    
    function testSettleOnAuctionKicked72HoursAgoAndPartiallyTaken() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_300 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_417.044136515672180410 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           105.285754181824258217 * 1e18,
            transferAmount: 105.285754181824258217 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2_787.506622839621476352 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      2_012.033316090796323720 * 1e18,
            exchangeRate: 1.006062596976766964 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    4_999.771689497716895000 * 1e18,
            collateral:   0,
            deposit:      5_030.083290226990809301 * 1e18,
            exchangeRate: 1.006062596976766965 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0,
            deposit:      11_066.183238499379780461 * 1e18,
            exchangeRate: 1.006062596976766964 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2.722174436366817848 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.527901208315548003 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992553456520532021 * 1e18
        });

        // take partial 800 collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   800 * 1e18,
            bondChange:      24.347868345313520351 * 1e18,
            givenAmount:     2_177.739549093454278400 * 1e18,
            collateralTaken: 800 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          129.633622527137778568 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 129.633622527137778568 * 1e18,
                auctionPrice:      2.722174436366817848 * 1e18,
                debtInAuction:     7_264.136220460174790403 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_264.136220460174790403 * 1e18,
            borrowerCollateral:        200 * 1e18,
            borrowert0Np:              41.423212004652813045 * 1e18,
            borrowerCollateralization: 0.257357505050496364 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      2_012.080837484034115925 * 1e18,
            exchangeRate: 1.006086358758398720 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    4_999.771689497716895000 * 1e18,
            collateral:   0,
            deposit:      5_030.202093710085289813 * 1e18,
            exchangeRate: 1.006086358758398721 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0,
            deposit:      11_066.444606162187637588 * 1e18,
            exchangeRate: 1.006086358758398720 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // settle should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_266.860782366276289457 * 1e18,
            borrowerCollateral:        200 * 1e18,
            borrowert0Np:              41.423212004652813045 * 1e18,
            borrowerCollateralization: 0.257261014079290282 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      2_012.080837484034115925 * 1e18,
            exchangeRate: 1.006086358758398720 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 7_266.860782366276289457 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 129.633622527137778568 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   200 * 1e18,
            deposit:      0,
            exchangeRate: 0.991763770360502646 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0,
            deposit:      10_848.806394658411625913 * 1e18,
            exchangeRate: 0.986300163324266424 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1.000000000000000000 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  9.845413922741351377 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             65_846.294979133297470913 * 1e18,
                pledgedCollateral:    2 * 1e18,
                encumberedCollateral: 2.025535290651122678 * 1e18,
                poolDebt:             18.933488312964137265 * 1e18,
                actualUtilization:    0.571142885809255306 * 1e18,
                targetUtilization:    0.955567693408119411 * 1e18,
                minDebtAmount:        1.893348831296413727 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 83 hours + 100 days
            })
        );
    }

    function testSettleOnAuctionKicked72HoursAgo() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_300 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_417.044136515672180410 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           105.285754181824258217 * 1e18,
            transferAmount: 105.285754181824258217 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2_787.506622839621476352 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      2_012.033316090796323720 * 1e18,
            exchangeRate: 1.006062596976766964 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    4_999.771689497716895000 * 1e18,
            collateral:   0,
            deposit:      5_030.083290226990809301 * 1e18,
            exchangeRate: 1.006062596976766965 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0,
            deposit:      11_066.183238499379780461 * 1e18,
            exchangeRate: 1.006062596976766964 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // settle should work on an kicked auction if 72 hours passed from kick time
        // settle should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 73 hours,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_420.576190285556153618 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992232288282095723 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 9_420.576190285556153618 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        40.159651907487263058 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   202.918500579787987864 * 1e18,
            deposit:      0,
            exchangeRate: 1.006236086054551886 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    4_999.771689497716895000 * 1e18,
            collateral:   512.381896370250897817 * 1e18,
            deposit:      0,
            exchangeRate: 1.006236086054551886 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   244.539951142473851261 * 1e18,
            deposit:      8_690.846315337976774916 * 1e18,
            exchangeRate: 1.006236086054551886 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        
        // borrower can re-open a loan once their previous loan is fully settled
        _drawDebt({
            from: _borrower2,
            borrower: _borrower2,
            amountToBorrow: 5 * 1e18,
            limitIndex: _i9_72,
            collateralToPledge: 1 * 1e18,
            newLup: 9.721295865031779605 * 1e18
        });
    }

    function testSettleAuctionReverts() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_300 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);
        // settle should revert on a borrower that is not auctioned
        _assertSettleOnNotKickedAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });

        uint256 kickTime = _startTime + 100 days;

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_417.044136515672180410 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           105.285754181824258217 * 1e18,
            transferAmount: 105.285754181824258217 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2_787.506622839621476352 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });

        // settle should revert on an kicked auction but 72 hours not passed (there's still debt to settle and collateral to be auctioned)
        _assertSettleOnNotClearableAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });

        _addLiquidityWithPenalty({
            from:        _lender1,
            amount:      100 * 1e18,
            amountAdded: 99.995890410958904100 * 1e18,
            index:       _i9_52,
            lpAward:     99.995890410958904100 * 1e18,
            newLup:      9.721295865031779605 * 1e18
        });
 
        _addLiquidity({
            from:    _lender1, 
            amount:  100 * 1e18, 
            index:   _i9_91, 
            lpAward: 99.393308837291078044 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(12.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      1.144533362618078976 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.648846264483444961 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992540709768608251 * 1e18
        });

        // take entire collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      12.796272006652205754 * 1e18,
            givenAmount:     1_144.533362618078976000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // remove quote tokens should fail since auction head is clearable
        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  _i9_52
        });

        _assertRemoveAllLiquidityAuctionNotClearedRevert({
            from:   _lender,
            index:  _i9_52
        });

        // remove collateral should fail since auction head is clearable
        _assertRemoveCollateralAuctionNotClearedRevert({
            from:   _lender,
            amount: 10 * 1e18,
            index:  _i9_52
        });

        // remove all collateral should fail since auction head is clearable
        _assertRemoveAllCollateralAuctionNotClearedRevert({
            from:   _lender,
            index:  _i9_52
        });

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   99.393308837291078044 * 1e18,
            depositTime: _startTime + 100 days
        });

        // settle to make buckets insolvent
        // settle should work because there is still debt to settle but no collateral left to auction (even if 72 hours didn't pass from kick)
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_285.911755653056674961 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });


        assertTrue(block.timestamp - kickTime < 72 hours); // assert auction was kicked less than 72 hours ago

        // LP forfeited when forgive bad debt should be reflected in BucketBankruptcy event
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_91, 2_099.301984636377836044 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_81, 4_999.771689497716895000 * 1e18);
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 8_285.911755653056674961 * 1e18
        });

        // bucket is insolvent, balances are resetted
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        // after bucket bankruptcy lenders balance is zero
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime + 100 days
        });

        // cannot add liquidity in same block when bucket marked insolvent
        _assertAddLiquidityBankruptcyBlockRevert({
            from:   _lender1,
            amount: 1_000 * 1e18,
            index:  _i9_91
        });

        // cannot add collateral in same block when bucket marked insolvent
        _assertAddCollateralBankruptcyBlockRevert({
            from:   _lender1,
            amount: 10 * 1e18,
            index:  _i9_91
        });

        // cannot move LP in same block when bucket marked insolvent
        _assertMoveLiquidityBankruptcyBlockRevert({
            from:      _lender1,
            amount:    10 * 1e18,
            fromIndex: _i9_52,
            toIndex:   _i9_91
        });

        // all operations should work if not in same block
        skip(1 hours);

        // move quote token in a bankrupt bucket should set deposit time to time of bankruptcy + 1 to prevent losing deposit
        _pool.moveQuoteToken(10 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes);
        (, , uint256 bankruptcyTime, , ) = _pool.bucketInfo(_i9_91);
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   10 * 1e18,
            depositTime: bankruptcyTime + 1
        });

        _pool.addQuoteToken(100 * 1e18, _i9_91, block.timestamp + 1 minutes);
        ERC20Pool(address(_pool)).addCollateral(4 * 1e18, _i9_91, block.timestamp + 1 minutes);

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   149.665040743606661996 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 hours
        });
        // bucket is healthy again
        _assertBucket({
            index:        _i9_91,
            lpBalance:    149.665040743606661996 * 1e18,
            collateral:   4 * 1e18,
            deposit:      109.996301369863013700 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // when moving to a bucket that was marked insolvent, the deposit time should be the greater between from bucket deposit time and insolvency time + 1
        changePrank(_lender);
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime
        });

        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   1_000 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 // _i9_91 bucket insolvency time + 1 (since deposit in _i9_52 from bucket was done before _i9_91 target bucket become insolvent)
        });

        _pool.addQuoteToken(1_000 * 1e18, _i9_52, block.timestamp + 1 minutes);
        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 hours // time of deposit in _i9_52 from bucket (since deposit in _i9_52 from bucket was done after _i9_91 target bucket become insolvent)
        });

        // ensure bucket bankruptcy when moving amounts from an unbalanced bucket leave bucket healthy
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0 * 1e18,
            deposit:      9_927.446391683186115164 * 1e18,
            exchangeRate: 0.902536338221594909 * 1e18
        });

        _pool.moveQuoteToken(10000000000 * 1e18, _i9_72, _i9_91, type(uint256).max);

        _assertBucket({
            index:        _i9_72,
            lpBalance:    0,
            collateral:   0 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }

    function testSettleZeroExchangeRateResidualBankruptcy() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_300 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);
        // settle should revert on a borrower that is not auctioned
        _assertSettleOnNotKickedAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });
        
        uint256 kickTime = _startTime + 100 days;

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_417.044136515672180410 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           105.285754181824258217 * 1e18,
            transferAmount: 105.285754181824258217 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2_787.506622839621476352 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });

        _addLiquidity({
            from:    _lender1,
            amount:  100 * 1e18,
            index:   _i9_91,
            lpAward: 99.393308837291078044 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.285754181824258217 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    10.888697745467271392 * 1e18,
                totalBondEscrowed: 105.285754181824258217 * 1e18,
                auctionPrice:      2.722174436366817848 * 1e18,
                debtInAuction:     9_417.044136515672180411 * 1e18,
                debtToCollateral:  9.417044136515672180 * 1e18,
                neutralPrice:      10.888697745467271392 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.527901208315548003 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992553456520532021 * 1e18
        });

        // take entire collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      30.434835431641900439 * 1e18,
            givenAmount:     2_722.174436366817848000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   99.393308837291078044 * 1e18,
            depositTime: _startTime + 100 days
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              6_725.788300273139601003 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_099.301984636377836044 * 1e18,
            collateral:   0,
            deposit:      2_112.078815709953620479 * 1e18,
            exchangeRate: 1.006086228264005035 * 1e18
        });

        // LP forfeited when forgive bad debt should be reflected in BucketBankruptcy event
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_91, 2_099.301984636377836044 * 1e18);
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 6_725.788300273139601003 * 1e18
        });

        // bucket is insolvent, balances are resetted
        _assertBucketAssets({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }
}

contract ERC20PoolLiquidationsSettleRegressionTest is ERC20HelperContract {

    address internal actor1;
    address internal actor2;
    address internal actor3;
    address internal actor4;
    address internal actor6;
    address internal actor7;
    address internal actor8;

    function setUp() external {
        _startTest();

        actor1 = makeAddr("actor1");
        _mintQuoteAndApproveTokens(actor1, type(uint256).max);
        _mintCollateralAndApproveTokens(actor1, type(uint256).max);

        actor2 = makeAddr("actor2");
        _mintQuoteAndApproveTokens(actor2, type(uint256).max);
        _mintCollateralAndApproveTokens(actor2, type(uint256).max);

        actor3 = makeAddr("actor3");
        _mintQuoteAndApproveTokens(actor3, type(uint256).max);
        _mintCollateralAndApproveTokens(actor3, type(uint256).max);

        actor4 = makeAddr("actor4");
        _mintQuoteAndApproveTokens(actor4, type(uint256).max);
        _mintCollateralAndApproveTokens(actor4, type(uint256).max);

        actor6 = makeAddr("actor6");
        _mintQuoteAndApproveTokens(actor6, type(uint256).max);
        _mintCollateralAndApproveTokens(actor6, type(uint256).max);

        actor7 = makeAddr("actor7");
        _mintQuoteAndApproveTokens(actor7, type(uint256).max);
        _mintCollateralAndApproveTokens(actor7, type(uint256).max);

        actor8 = makeAddr("actor8");
        _mintQuoteAndApproveTokens(actor8, type(uint256).max);
        _mintCollateralAndApproveTokens(actor8, type(uint256).max);
    }

    function test_regression_settle_with_reserves() external tearDown {
        changePrank(actor2);
        _addInitialLiquidity({
            from:   actor2,
            amount: 112_807_891_516.8015826259279868 * 1e18,
            index:  2572
        });

        // no reserves
        (uint256 reserves, uint256 claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 5_151_045.274739797778316842 * 1e18);
        assertEq(claimableReserves, 5_150_932.471999326251474014 * 1e18);

        _drawDebtNoLupCheck({
            from:               actor2,
            borrower:           actor2,
            amountToBorrow:     56_403_945_758.4007913129639934 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 22_009_851.171858165566322122 * 1e18
        });

        // origination fee goes to reserves
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 59_385_608.503971353919526416 * 1e18);
        assertEq(claimableReserves, 59_385_495.701230882392683588 * 1e18);

        // skip some time to make actor2 undercollateralized
        skip(200 days);
        ERC20Pool(address(_pool)).updateInterest();
        // check reserves after interest accrual
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 294_613_108.667188773539633581 * 1e18);
        assertEq(claimableReserves, 294_612_994.531492467754559135 * 1e18);

        // kick actor2
        changePrank(actor4);
        _kick({
            from:           actor4,
            borrower:       actor2,
            debt:           58_026_363_656.051471906282127718 * 1e18,
            collateral:     22_009_851.171858165566322122 * 1e18,
            bond:           648_754_468.110271558372325568 * 1e18,
            transferAmount: 648_754_468.110271558372325568 * 1e18
        });
        // ensure reserves did not increase as result of kick
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 294_613_108.667188773539633581 * 1e18);
        assertEq(claimableReserves, 294_612_994.531492467754559135 * 1e18);

        changePrank(actor7);
        _drawDebtNoLupCheck({
            from:               actor7,
            borrower:           actor7,
            amountToBorrow:     1_000_000 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 390.489032271806320214 * 1e18
        });

        // skip some time to make actor7 undercollateralized
        skip(200 days);
        (uint256 borrowerDebt, , , ) = _poolUtils.borrowerInfo(address(_pool), actor2);
        assertEq(borrowerDebt, 59_474_936_428.593370593619524964 * 1e18);

        // reserves increase slightly due to interest accrual
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 294_613_974.051804158154633582 * 1e18);
        assertEq(claimableReserves, 294_613_859.916107852369559136 * 1e18);

        // test reserves auction cannot be kicked until auction settled
        _assertReserveAuctionUnsettledLiquidation();

        // settle auction with reserves
        changePrank(actor6);
        _settle({
            from:        actor6,
            borrower:    actor2,
            maxDepth:    2,
            settledDebt: 59_474_936_428.593370593619524963 * 1e18
        });

        // almost all the reserves are used to settle debt
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 374_644_181.841827555572267504 * 1e18);
        assertEq(claimableReserves, 374_644_125.812500127979859369 * 1e18);

        // test reserves auction can be kicked after auction settled
        _pool.kickReserveAuction();
        _assertReserveAuction({
            reserves:                   56.029327427592408135 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 374_644_125.812500127979859369 * 1e18,
            auctionPrice:               2.669199731428525342 * 1e18,
            timeRemaining:              3 days
        });
    }
}

contract ERC20PoolLiquidationSettleFuzzyTest is ERC20FuzzyHelperContract {
    address internal _lender;
    address internal _kicker;
    address internal _borrower;

    uint256[3] internal _buckets = [2550, 2551, 2552];
    function setUp() external {
        _startTest();
        _lender   = makeAddr("lender");
        _kicker   = makeAddr("kicker");
        _borrower = makeAddr("borrower");

        _mintQuoteAndApproveTokens(_lender, 1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_kicker, 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000 * 1e18);

        // lender deposits all liquidity in 3 buckets
        for(uint i = 0; i < 3; i++) {
            _addInitialLiquidity({
                from:    _lender,
                amount:  100_000 * 1e18,
                index:   _buckets[i]
            });

            _assertBucket({
                index:        _buckets[i],
                lpBalance:    99_995.433789954337900000 * 1e18,
                collateral:   0,
                deposit:      99_995.433789954337900000 * 1e18,
                exchangeRate: 1 * 1e18
            });
        }

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     280_000 * 1e18,
            indexLimit: 7_388,
            newLup:     2981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              280_269.230769230769360000 * 1e18,
            borrowerCollateral:        100 * 1e18,
            borrowert0Np:              3_240.684547040819349457 * 1e18,
            borrowerCollateralization: 1.022714224915763456 * 1e18
        });

        // skip to make borrower undercollateralized
        skip(400 days);

        _kick({
            from:           _kicker,
            borrower:       _borrower,
            debt:           296_054.985884857245508279 * 1e18,
            collateral:     100 * 1e18,
            bond:           3_309.995367581407494354 * 1e18,
            transferAmount: 3_309.995367581407494354 * 1e18
        });
    }

    function testSettleWithDepositFuzzy(uint256 quoteAmount, uint256 bucketIndex, uint256 wait) external {
        quoteAmount = bound(quoteAmount, 1 * 1e18, 500_000 * 1e18);
        bucketIndex = bound(bucketIndex, 1, 7388);
        wait        = bound(wait, 0, 3600 * 6); // 0-6 hours

        // decrease the auction price
        skip(wait);

        // prevent trying to deposit into a bucket priced higher than the auction price
        (,,,, uint256 auctionPrice,,,,) = _poolUtils.auctionStatus(address(_pool), _borrower);
        if (_priceAt(bucketIndex) > auctionPrice ) {
            if (auctionPrice > MIN_PRICE) bucketIndex = _indexOf(auctionPrice) + 1;
            else bucketIndex = 7388;
        }
            
        // add some deposits to be used to settle auction
        _addLiquidityNoEventCheck({
            from:   _lender,
            amount: quoteAmount,
            index:  bucketIndex
        });

        // skip some time to make auction settleable
        skip(73 hours);

        (uint256 beforeDebt, uint256 beforeCollateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // settle auction with deposits
        _pool.settle(_borrower, 2);

        (uint256 afterDebt, uint256 afterCollateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // ensure some borrower debt is settled
        assertLt(afterDebt, beforeDebt);

        // ensure some collateral is used to settle debt
        assertLt(afterCollateral, beforeCollateral);
    }
}
