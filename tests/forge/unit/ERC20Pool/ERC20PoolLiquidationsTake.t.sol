// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsTakeTest is ERC20HelperContract {

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

        _mintCollateralAndApproveTokens(_borrower,  1_100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 2_000 * 1e18);
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
        _assertTakeNoAuctionRevert({
            from:          _lender,
            borrower:      _borrower,
            maxCollateral: 10 * 1e18
        });
    }

    function testTakeLoanColConstraintBpfPosNoResidual() external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 10_000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_020 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });
        
        // calling borrow stamps loan with new t0NeutralPrice
        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_927.443577377932263894 * 1e18,
                poolDebt:             18_737.249278846153854794 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        936.862463942307692740 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.028587437074993946 * 1e18,
                poolDebt:             18_995.690027205926343012 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        949.784501360296317151 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp - 100 days
            })
        );
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
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.115738086847591203 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   56.765391100119755012 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(47000 seconds); // 13.05 hrs

        _assertPool(
            PoolParams({
                htp:                  9.154429955928583539 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_219.674636105806588000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.159641123343178119 * 1e18,
                poolDebt:             18_996.964038864342413928 * 1e18,
                actualUtilization:    0.225749991311399444 * 1e18,
                targetUtilization:    0.963953858271529038 * 1e18,
                minDebtAmount:        1_899.696403886434241393 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 47000 seconds
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      0.980964776869723804 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.823610021566400073 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.610021566400073017 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989584871924882640 * 1e18
        });
 
        // BPF Positive, Loan Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      14.891378730546973678 * 1e18,
            givenAmount:     980.964776869723804000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          164.007116817394564881 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 164.007116817394564881 * 1e18,
                auctionPrice:      0.980964776869723804 * 1e18,
                debtInAuction:     8_857.536623427223243018 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        // Bad debt remains
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_857.536623427223243018 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertPool(
            PoolParams({
                htp:                  9.155043929439064212 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_220.773168797860489236 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 1_854.782622714283711888 * 1e18,
                poolDebt:             18_030.890640725165583929 * 1e18,
                actualUtilization:    0.175476347926803679 * 1e18,
                targetUtilization:    0.962794543732489691 * 1e18,
                minDebtAmount:        1_803.089064072516558393 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
    }

    function testTakeCallerColConstraintBpfPosNoResidual() external tearDown {
 
        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 10_000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_020 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });
        
        // calling borrow stamps loan with new t0NeutralPrice
        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_927.443577377932263894 * 1e18,
                poolDebt:             18_737.249278846153854794 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        936.862463942307692740 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.028587437074993946 * 1e18,
                poolDebt:             18_995.690027205926343012 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        949.784501360296317151 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp - 100 days
            })
        );
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
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.115738086847591203 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   56.765391100119755012 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(43000 seconds); // 11.94 hrs

        _assertPool(
            PoolParams({
                htp:                  9.154429955928583539 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_219.674636105806588000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.148487275944809732 * 1e18,
                poolDebt:             18_996.855609013749459851 * 1e18,
                actualUtilization:    0.225749991311399444 * 1e18,
                targetUtilization:    0.963953858271529038 * 1e18,
                minDebtAmount:        1_899.685560901374945985 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 43000 seconds
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      1.441757768272869640 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.823553950892962846 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.553950892962846875 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989590520256481315 * 1e18
        });

        // BPF Positive, caller collateral is constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10 * 1e18,
            bondChange:      0.218863729578241083 * 1e18,
            givenAmount:     14.417577682728696400 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          149.334601816425832286 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.334601816425832286 * 1e18,
                auctionPrice:      1.441757768272869640 * 1e18,
                debtInAuction:     9_809.355236939812391565 * 1e18,
                thresholdPrice:    9.908439633272537769 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_809.355236939812391565 * 1e18,
            borrowerCollateral:        990 * 1e18,
            borrowert0Np:              11.256613027484040114 * 1e18,
            borrowerCollateralization: 0.981112690275436564 * 1e18
        });
    }

    function testTakeCallerColConstraintBpfPosResidual () external tearDown {    
        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 10_000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_020 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });
        
        // calling borrow stamps loan with new t0NeutralPrice
        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_927.443577377932263894 * 1e18,
                poolDebt:             18_737.249278846153854794 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        936.862463942307692740 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.028587437074993946 * 1e18,
                poolDebt:             18_995.690027205926343012 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        949.784501360296317151 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp - 100 days
            })
        );
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
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.115738086847591203 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   56.765391100119755012 * 1e18,
            claimableReserves :         0.000000000000000000 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(22000 seconds);

        _assertPool(
            PoolParams({
                htp:                  9.154429955928583539 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_219.674636105806588000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.089930621571444937 * 1e18,
                poolDebt:             18_996.286362451719573593 * 1e18,
                actualUtilization:    0.225749991311399444 * 1e18,
                targetUtilization:    0.963953858271529038 * 1e18,
                minDebtAmount:        1_899.628636245171957359 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 22000 seconds
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      10.886704980656377540 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.823259585107984853 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.259585107984853687 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989620174526306750 * 1e18
        });
 
        // BPF Positive, Caller Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   577 * 1e18,
            bondChange:      27.337468146252670459 * 1e18,
            givenAmount:     6_281.628773838729840580 * 1e18,
            collateralTaken: 577 * 1e18,
            isReward:        true
        });

        // Residual is collateralized, auction remains active.
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          176.453206233100261662 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 176.453206233100261662 * 1e18,
                auctionPrice:      10.886704980656377540 * 1e18,
                debtInAuction:     3_653.993019025148320626 * 1e18,
                thresholdPrice:    8.638281368853778535 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              3_653.993019025148320626 * 1e18,
            borrowerCollateral:        423.000000000000000000 * 1e18,
            borrowert0Np:              9.813927120521769770 * 1e18,
            borrowerCollateralization: 1.136655711572588218 * 1e18
        });
    }

    function testTakeCallerColConstraintBpfNegResidual () external tearDown {

        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_000.000000000000000000 * 1e18,
                pledgedCollateral:    1_002.000000000000000000 * 1e18,
                encumberedCollateral: 998.691567123838268658 * 1e18,
                poolDebt:             9_708.576201923076927554 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        485.428810096153846378 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      2_896.411799611894166272 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.115738086847591203 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   29.412595036010327036 * 1e18,
            claimableReserves :         0 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(80 minutes);

        _assertPool(
            PoolParams({
                htp:                  9.767138988573636287 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_113.822894306622582000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_012.473341055493309162 * 1e18,
                poolDebt:             9_842.552903857677844743 * 1e18,
                actualUtilization:    0.539365344551282052 * 1e18,
                targetUtilization:    0.996698234880015451 * 1e18,
                minDebtAmount:        984.255290385767784474 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 80 minutes
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 80 minutes,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      181.025737475743385344 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.823018492083647863 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.018492083647863197 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989644463447376554 * 1e18
        });

        // BPF Negative, Caller collateral constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10.0 * 1e18,
            bondChange:      27.480322232669404372 * 1e18,
            givenAmount:     1_810.257374757433853440 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        false
        });

        _assertPool(
            PoolParams({
                htp:                  9.767205887014990773 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_113.882499196138656000 * 1e18,
                pledgedCollateral:    992.0 * 1e18,
                encumberedCollateral: 830.497921731842609849 * 1e18,
                poolDebt:             8_073.516012449248097864 * 1e18,
                actualUtilization:    0.539405362783948025 * 1e18,
                targetUtilization:    0.996698410914855915 * 1e18,
                minDebtAmount:        807.351601244924809786 * 1e18,
                loans:                1,  // TODO: is this test still relevant like this?
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 80 minutes
            })
        );
        // take recollateralized borrower however once in auction, always in auction...
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          121.635415854178186831 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 80 minutes,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 121.635415854178186831 * 1e18,
                auctionPrice:      181.025737475743385344 * 1e18,
                debtInAuction:     8_053.981600675218116317 * 1e18,
                thresholdPrice:    8.135334950176987996 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_053.981600675218116317 * 1e18,
            borrowerCollateral:        990.000000000000000000 * 1e18,
            borrowert0Np:              9.242757957291237631 * 1e18,
            borrowerCollateralization: 1.194947217854906920 * 1e18
        });
    }

    function testTakeLoanDebtConstraintBpfPosResidual() external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 10_000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_020 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });
        
        // calling borrow stamps loan with new t0NeutralPrice
        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_927.443577377932263894 * 1e18,
                poolDebt:             18_737.249278846153854794 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        936.862463942307692740 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.689307692307692312 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.000000000000000000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.028587437074993946 * 1e18,
                poolDebt:             18_995.690027205926343012 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        949.784501360296317151 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp - 100 days
            })
        );
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
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.115738086847591203 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   56.765391100119755012 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(22000 seconds); // 6.11s hrs

        _assertPool(
            PoolParams({
                htp:                  9.154429955928583539 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_219.674636105806588000 * 1e18,
                pledgedCollateral:    2_002.000000000000000000 * 1e18,
                encumberedCollateral: 1_954.089930621571444937 * 1e18,
                poolDebt:             18_996.286362451719573593 * 1e18,
                actualUtilization:    0.225749991311399444 * 1e18,
                targetUtilization:    0.963953858271529038 * 1e18,
                minDebtAmount:        1_899.628636245171957359 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 22000 seconds
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.115738086847591203 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    11.314108592233961587 * 1e18,
                totalBondEscrowed: 149.115738086847591203 * 1e18,
                auctionPrice:      10.886704980656377540 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                thresholdPrice:    9.823259585107984853 * 1e18,
                neutralPrice:      11.314108592233961587 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.259585107984853687 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              11.160177532745580804 * 1e18,
            borrowerCollateralization: 0.989620174526306750 * 1e18
        });
 
        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      43.529168844258845077 * 1e18,
            givenAmount:     10_002.172770738542860841 * 1e18,
            collateralTaken: 918.751154597329341626 * 1e18,
            isReward:        true
        });

        // Residual is collateralized, auction is not active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 192.644906931106436280 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        81.248845402670658374 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testTakeAndSettle() external tearDown {

        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.577873638769639523 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertReserveAuction({
            reserves:                   29.503568858839974240 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        uint256 preTakeSnapshot = vm.snapshot();

        skip(500 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 500 minutes,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      5.055481829190032044 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853816057268096589 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.816057268096589430 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986551383599395369 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      76.743932462179586888 * 1e18,
            givenAmount:     5_055.481829190032044 * 1e18,
            collateralTaken: 1000.0 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          226.321806100949226411 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 500 minutes,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 226.321806100949226411 * 1e18,
                auctionPrice:      5.055481829190032044 * 1e18,
                debtInAuction:     4_875.078160540244132430 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.34917297836691808 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              4_875.078160540244132430 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    226.321806100949226411 * 1e18
        });

        vm.revertTo(preTakeSnapshot);

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    11.34917297836691808 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853900422492752583 * 1e18,
                neutralPrice:      11.34917297836691808 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.900422492752583093 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986542937133981323 * 1e18
        });

        // partial take for 20 collateral
        // Collateral amount is restrained by taker
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   20 * 1e18,
            bondChange:      0.861421516268142809 * 1e18,
            givenAmount:     56.745864891834590400 * 1e18,
            collateralTaken: 20 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          150.439295155037782332 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 150.439295155037782332 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     9_798.015979117186135514 * 1e18,
                thresholdPrice:    9.997975488895087893 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_798.015979117186135514 * 1e18,
            borrowerCollateral:        980 * 1e18,
            borrowert0Np:              11.358444866850947120 * 1e18,
            borrowerCollateralization: 0.972326435069717785 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    150.439295155037782332 * 1e18 // locked bond + reward, auction is not yet finished
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   29.562252507398080560 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // take remaining collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   981 * 1e18,
            bondChange:      42.209654297138997644 * 1e18,
            givenAmount:     2_780.547379699894929600 * 1e18,
            collateralTaken: 980 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          192.648949452176779976 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 192.648949452176779976 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     7_059.678253714430204094 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_059.678253714430204094 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    192.648949452176779976 * 1e18 // locked bond + reward, auction is not yet finalized
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   29.562252507398081096 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // should revert if there's no more collateral to be auctioned
        _assertTakeInsufficentCollateralRevert({
            from:          _lender,
            borrower:      _borrower2,
            maxCollateral: 10 * 1e18
        });

        // full clear / debt settle
        uint256 postTakeSnapshot = vm.snapshot();

        _assertBucket({
            index:        3_696,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_012.735939051273346000 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 6_963.271989687033445102 * 1e18
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
                totalBondEscrowed: 192.648949452176779976 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
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
        _assertKicker({
            kicker:    _lender,
            claimable: 192.648949452176779976 * 1e18,
            locked:    0
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   0, // bucket is bankrupt
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    5_000 * 1e18,
            collateral:   0,
            deposit:      14.459712357801136539 * 1e18,
            exchangeRate: 0.002891942471560228 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_81,
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      11_070.047664782003403 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_72,
            lpBalance:   11_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_62,
            lpBalance:   25_000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_52,
            lpBalance:    30_000 * 1e18,
            collateral:   0,
            deposit:      30_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_52,
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime
        });
        // done
 
        vm.revertTo(postTakeSnapshot);

        _assertReserveAuction({
            reserves:                   29.562252507398081096 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        // partial clears / debt settled - max buckets to use is 0, settle only from reserves
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    0,
            settledDebt: 29.158481211449497738 * 1e18
        });
        _assertReserveAuction({
            reserves:                   0.000073114623451463 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // partial clears / debt settled with max buckets to use is 1
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 1_985.25021726848337055 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          192.648949452176779976 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 192.648949452176779976 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     5_017.380135270382228461 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.349172978366918080  * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_017.380135270382228461 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    192.648949452176779976 * 1e18 // locked bond + reward, auction is not yet finalized
        });

        // clear remaining debt
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    5,
            settledDebt: 4_948.863291207100576814 * 1e18
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
                totalBondEscrowed: 192.648949452176779976 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
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
        _assertKicker({
            kicker:    _lender,
            claimable: 192.648949452176779976 * 1e18,
            locked:    0
        });

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 44_013.128881769500840477 * 1e18);

        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_lender), 44_205.777831221677620453 * 1e18);

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0
        });
    }

    function testTakeReverts() external tearDown {

        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.577873638769639523 * 1e18
        });
        _assertReserveAuction({
            reserves:                   29.503568858839974240 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
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
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.888301125810259647 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.776602251620519295 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.983110823724556080 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.776602251620519294 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.300215543999476476 * 1e18,
            transferAmount: 0.300215543999476476 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.300215543999476476 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.389378845807642064 * 1e18,
                totalBondEscrowed: 149.878089182769115999 * 1e18,
                auctionPrice:      2_915.680984526756368384 * 1e18,
                debtInAuction:     9_995.402984757347394196 * 1e18,
                thresholdPrice:    9.888301125810259647 * 1e18,
                neutralPrice:      11.389378845807642064 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.878089182769115999 * 1e18
        });

        skip(2 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, MAX_FENWICK_INDEX);
        }

        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertTakeDebtUnderMinPoolDebtRevert({
            from:          _lender,
            borrower:      _borrower,
            maxCollateral: 0.1 * 1e18
        });
    }

    function testTakeAuctionPriceLtNeutralPrice() external tearDown {
        _addLiquidity({
            from:    _lender1,
            amount:  1 * 1e18,
            index:   _i9_91,
            lpAward: 1 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    149.577873638769639523 * 1e18
        });

        // after 6 hours, auction price should equal neutral price
        skip(6 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      11.349172978366918080 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853697947167044034 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );

        // skip another hour, and then take auction below neutral price
        skip(1 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 7 hours,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      8.025077173862374200 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853748565608429470 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );

        // confirm kicker is rewarded
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      121.823399122640329123 * 1e18,
            givenAmount:     8_025.0771738623742 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // borrower left with bad debt to be settled
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              1950.49479086869560036 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
    }

    function testReservesAfterTakeSettlesAuction() external tearDown {
        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 10_000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     9_020 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });
        
        // calling borrow stamps loan with new t0NeutralPrice
        _borrow({
            from:       _borrower2,
            amount:     1_700.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     _p9_72
        });

        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.115738086847591203 * 1e18,
            transferAmount: 149.115738086847591203 * 1e18
        });

        skip(43000 seconds); // 11.94 hrs
        
        // force pool state update
        _updateInterest();

        (uint256 reservesBeforeTake, , , , ) = _poolUtils.poolReservesInfo(address(_pool));

        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      21.886372957824108251 * 1e18,
            givenAmount:     1_441.75776827286964 * 1e18,
            collateralTaken: 1000 * 1e18,
            isReward:        true
        });

        (uint256 reservesAfterTake, , , , ) = _poolUtils.poolReservesInfo(address(_pool));

        // reserves should increase by borrower take penalty
        assertGt(reservesAfterTake, reservesBeforeTake);
    }
}

contract ERC20PoolLiquidationsLowPriceCollateralTest is ERC20HelperContract {
    
    address internal _lender;
    address internal _borrower;
    uint256 internal _p0_00016 = 0.000016088121329146 * 1e18;
    uint256 internal _i0_00016 = 6369;

    function setUp() external {
        assertEq(_priceAt(_i0_00016), _p0_00016);
        _startTest();

        _lender   = makeAddr("lender");
        _borrower = makeAddr("borrower");

        _mintQuoteAndApproveTokens(_lender,   1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower, 1_000_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower, 50_000_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  _i0_00016
        });
    }

    function testTakeRevertsOnZeroPrice() external tearDown {
        // Borrower borrows
        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     750 * 1e18,
            limitIndex:         _i0_00016+1,
            collateralToPledge: Maths.wmul(Maths.wdiv(750 * 1e18, _p0_00016), 1.01 * 1e18),
            newLup:             _p0_00016
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           761.075765343400230098 * 1e18,
            collateral:     47_084_428.598115880943744161 * 1e18,
            bond:           11.553388798051207996 * 1e18,
            transferAmount: 11.553388798051207996 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          11.553388798051207996 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    0.000018617825030991 * 1e18,
                totalBondEscrowed: 11.553388798051207996 * 1e18,
                auctionPrice:      0.004766163207933696 * 1e18,
                debtInAuction:     761.075765343400230098 * 1e18,
                thresholdPrice:    0.000016164065021144 * 1e18,
                neutralPrice:      0.000018617825030991 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              761.075765343400230098 * 1e18,
            borrowerCollateral:        47_084_428.598115880943744161 * 1e18,
            borrowert0Np:              0.000018364525223142 * 1e18,
            borrowerCollateralization: 0.995301695959551634 * 1e18
        });

        // should revert if take occurs at 0 price
        skip(71 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          11.553388798051207996 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    0.000018617825030991 * 1e18,
                totalBondEscrowed: 11.553388798051207996 * 1e18,
                auctionPrice:      0 * 1e18,
                debtInAuction:     761.075765343400230098 * 1e18,
                thresholdPrice:    0.000016169961551610 * 1e18,
                neutralPrice:      0.000018617825030991 * 1e18
            })
        );
        _assertTakeZeroBidRevert({
            from:          _lender,
            borrower:      _borrower,
            maxCollateral: 2_000_0000 * 1e18
        });
    }
}

contract ERC20PoolLiquidationsTakeAndRepayAllDebtInPoolTest is ERC20HelperContract {

    address internal _lender;
    address internal _borrower;
    address internal _kicker;
    address internal _taker;

    function setUp() external {
        _startTest();

        _lender   = makeAddr("lender");
        _borrower = makeAddr("borrower");
        _kicker   = makeAddr("kicker");
        _taker    = makeAddr("taker");

        _mintQuoteAndApproveTokens(_lender,   1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower, 1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_kicker,   1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_taker,    1_000_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower, 150_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  2690
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  2700
        });
    }

    function testTakeAuctionRepaidAmountGreaterThanPoolDebt() external tearDown {
        _updateInterest();

        _drawDebtNoLupCheck({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     635.189921955815900534 * 1e18,
            limitIndex:         7000,
            collateralToPledge: 0.428329945169804100 * 1e18
        });

        skip(3276);

        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     635.803983894118939950 * 1e18,
            collateralToPull: 0.428329945169804100 * 1e18
        });

        _drawDebtNoLupCheck({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     100 * 1e18,
            limitIndex:         7000,
            collateralToPledge: 0.067433366047580170 * 1e18
        });

        skip(964);
        skip(86400 * 200);

        _kick({
            from:           _kicker,
            borrower:       _borrower,
            debt:           102.876583480271499176 * 1e18,
            collateral:     0.067433366047580170 * 1e18,
            bond:           1.561701503695180782 * 1e18,
            transferAmount: 1.561701503695180782  * 1e18
        });

        skip(964);
        skip(3600 * 3);
        
        // the calculated repaid amount is with 1 WAD greater than the pool debt
        // check that take works and doesn't overflow
        _take({
            from:            _taker,
            borrower:        _borrower,
            maxCollateral:   0.067433366047580170 * 1e18,
            bondChange:      1.561701503695180782 * 1e18,
            givenAmount:     105.275486946083517714 * 1e18,
            collateralTaken: 0.023241640918094312 * 1e18,
            isReward:        false
        });

    }
}

contract ERC20PoolLiquidationTakeFuzzyTest is ERC20FuzzyHelperContract {
    address internal _lender;
    address internal _taker;
    address internal _borrower;

    uint256[5] internal _buckets = [2550, 2551, 2552, 2553, 2554];
    function setUp() external {
        _startTest();
        _lender   = makeAddr("lender");
        _taker    = makeAddr("taker");
        _borrower = makeAddr("borrower");

        _mintQuoteAndApproveTokens(_lender, 500_000 * 1e18);
        _mintQuoteAndApproveTokens(_taker, 500_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000 * 1e18);

        // lender deposits all liquidity in 5 buckets
        for(uint i = 0; i < 5; i++) {
            _addLiquidity({
                from:    _lender,
                amount:  100_000 * 1e18,
                index:   _buckets[i],
                lpAward: 100_000 * 1e18,
                newLup:  MAX_PRICE
            });
        }

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });

        _borrow({
            from:       _borrower,
            amount:     290_000 * 1e18,
            indexLimit: 7_388,
            newLup:     2981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              290_278.84615384615398 * 1e18,
            borrowerCollateral:        100 * 1e18,
            borrowert0Np:              3_343.441616215101687356 * 1e18,
            borrowerCollateralization: 1.026946145846449373 * 1e18
        });

        // skip to make borrower undercollateralized
        skip(400 days);

        _kick({
            from:           _taker,
            borrower:       _borrower,
            debt:           306_628.378237887861419289 * 1e18,
            collateral:     100 * 1e18,
            bond:           4_654.723000803723493401 * 1e18,
            transferAmount: 4_654.723000803723493401 * 1e18
        });
    }

    function testTakeCollateralFuzzy(uint256 takeAmount, uint256 skipTimeToTake) external tearDown {
        skipTimeToTake = bound(skipTimeToTake, 1.1 hours, 71 hours);

        // skip some time to make auction takeable
        skip(skipTimeToTake);
        (,,,, uint256 auctionPrice, ) = _poolUtils.auctionStatus(address(_pool), _borrower);

        uint256 minCollateralTakeAmount = Maths.max(Maths.wdiv(1, auctionPrice), 1);

        takeAmount = bound(takeAmount, minCollateralTakeAmount, 100 * 1e18);

        uint256 quoteTokenRequired = Maths.ceilWmul(auctionPrice, takeAmount);

        // return when collateral price is too low and quote token required to take that collateral is 0
        if (quoteTokenRequired == 0) return;

        // calculate and mint quote tokens to buy collateral
        _mintQuoteAndApproveTokens(_taker, quoteTokenRequired);

        uint256 beforeTakerQuoteBalance = _quote.balanceOf(_taker);

        (, uint256 beforeCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // taker takes fuzzed amount of collateral
        _pool.take(_borrower, takeAmount, _taker, bytes(""));

        (, uint256 afterCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // ensure borrower collateral is reduced after take
        assertLt(afterCollateral, beforeCollateral);

        uint256 takerCollateralBalance = _collateral.balanceOf(_taker);

        // ensure borrower collateral is reduced same as taker gets colletaral
        assertEq(beforeCollateral - afterCollateral, takerCollateralBalance);

        // ensure taker gets collateral
        assertGt(takerCollateralBalance, 0);

        // ensure taker quote tokens are used to buy collateral
        assertLe(_quote.balanceOf(_taker), beforeTakerQuoteBalance);
    }
}
