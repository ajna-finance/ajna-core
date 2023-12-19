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
            amount:     19 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_040 * 1e18
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
                htp:                  9.889500000000000005 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             72_996.666666666666667000 * 1e18,
                pledgedCollateral:    1_042 * 1e18,
                encumberedCollateral: 856.568827408358955944 * 1e18,
                poolDebt:             8_006.691346153846157538 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.334567307692307877 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.018269230769230778 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.982991644171270499 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 1.217037273735858713 * 1e18
        });
        _assertReserveAuction({
            reserves:                   11.024679487179490538 * 1e18,
            claimableReserves :         11.024606490512823871 * 1e18,
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
            lpAward: 9_999.543378995433790000 * 1e18,
            newLup:  _p1505_26
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   1_040 * 1e18
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
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_082.000000000000000000 * 1e18,
                encumberedCollateral: 2_004.514549350802762384 * 1e18,
                poolDebt:             18_736.999038461538470178 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        936.849951923076923509 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.822951211365485637 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_082.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.162590561266668491 * 1e18,
                poolDebt:             18_995.436335284145209602 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        949.771816764207260480 * 1e18,
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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    109.823933241385648657 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   60.554587322829041789 * 1e18,
            claimableReserves :         60.554504106947293828 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(47000 seconds); // 13.05 hrs

        _assertPool(
            PoolParams({
                htp:                  9.155493589919282477 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_215.881747961316167813 * 1e18,
                pledgedCollateral:    2_082.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.298884574722565768 * 1e18,
                poolDebt:             18_996.710329927835017232 * 1e18,
                actualUtilization:    0.225757284918829265 * 1e18,
                targetUtilization:    0.926900343290412163 * 1e18,
                minDebtAmount:        1_899.671032992783501723 * 1e18,
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
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      0.946897685981543764 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.610021566400073017 * 1e18,
            borrowerCollateral:        1_040.000000000000000 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989584871924882640 * 1e18
        });
 
        // BPF Positive, Loan Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_100 * 1e18,
            bondChange:      11.010103486678303484 * 1e18,
            givenAmount:     984.773593420805514560 * 1e18,
            collateralTaken: 1_040 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          120.834036728063952141 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 120.834036728063952141 * 1e18,
                auctionPrice:      0.946897685981543764 * 1e18,
                debtInAuction:     8_849.846531632272862778 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        // Bad debt remains
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_849.846531632272862778 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertPool(
            PoolParams({
                htp:                  9.155493589919282477 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_216.980266533218143247 * 1e18,
                pledgedCollateral:    1_042.0 * 1e18,
                encumberedCollateral: 1_928.124086935418161702 * 1e18,
                poolDebt:             18_022.946839993707806992 * 1e18,
                actualUtilization:    0.175481652108616020 * 1e18,
                targetUtilization:    0.925786822077092381 * 1e18,
                minDebtAmount:        1_802.294683999370780699 * 1e18,
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
            lpAward: 9_999.543378995433790000 * 1e18,
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
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_004.514549350802762384 * 1e18,
                poolDebt:             18_736.999038461538470178 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        936.849951923076923509 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.822951211365485637 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.162590561266668491 * 1e18,
                poolDebt:             18_995.436335284145209602 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        949.771816764207260480 * 1e18,
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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    109.823933241385648657 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   60.554587322829041789 * 1e18,
            claimableReserves :         60.554504106947293828 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(43000 seconds); // 11.94 hrs

        _assertPool(
            PoolParams({
                htp:                  9.520928012632416038 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_215.881747961316167813 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.287284728349016606 * 1e18,
                poolDebt:             18_996.601901525348298620 * 1e18,
                actualUtilization:    0.353544427325713755 * 1e18,
                targetUtilization:    0.944118073902160936 * 1e18,
                minDebtAmount:        1_899.660190152534829862 * 1e18,
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
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      1.391688189743023672 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.553950892962846875 * 1e18,
            borrowerCollateral:        1_040.000000000000000 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989590520256481315 * 1e18
        });

        // BPF Positive, caller collateral is constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10 * 1e18,
            bondChange:      0.155595469787451318 * 1e18,
            givenAmount:     13.916881897430236720 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          109.979528711173099975 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.979528711173099975 * 1e18,
                auctionPrice:      1.391688189743023672 * 1e18,
                debtInAuction:     9_809.792664465320061476 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_809.792664465320061476 * 1e18,
            borrowerCollateral:        1_030 * 1e18,
            borrowert0Np:              10.861956351927329673 * 1e18,
            borrowerCollateralization: 0.981450087238343546 * 1e18
        });
    }

    function testTakeCallerColConstraintBpfPosResidual () external tearDown {    
        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 9_999.543378995433790000 * 1e18,
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
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_004.514549350802762384 * 1e18,
                poolDebt:             18_736.999038461538470178 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        936.849951923076923509 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.822951211365485637 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.162590561266668491 * 1e18,
                poolDebt:             18_995.436335284145209602 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        949.771816764207260480 * 1e18,
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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    109.823933241385648657 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   60.554587322829041789 * 1e18,
            claimableReserves :         60.554504106947293828 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(22000 seconds);

        _assertPool(
            PoolParams({
                htp:                  9.520642715125814291 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_215.881747961316167813 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.226386621120168430 * 1e18,
                poolDebt:             18_996.032662565740545058 * 1e18,
                actualUtilization:    0.353544427325713755 * 1e18,
                targetUtilization:    0.944118073902160936 * 1e18,
                minDebtAmount:        1_899.603266256574054506 * 1e18,
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
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      10.508629868487414000 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.259585107984853687 * 1e18,
            borrowerCollateral:        1_040.000000000000000 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989620174526306750 * 1e18
        });
 
        // BPF Positive, Caller Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   577 * 1e18,
            bondChange:      18.948075348653218429 * 1e18,
            givenAmount:     6_063.479434117237878000 * 1e18,
            collateralTaken: 577 * 1e18,
            isReward:        true
        });

        // Residual is collateralized, auction remains active.
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          128.772008590038867086 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 128.772008590038867086 * 1e18,
                auctionPrice:      10.508629868487414000 * 1e18,
                debtInAuction:     3_839.782833371446802894 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              3_839.782833371446802894 * 1e18,
            borrowerCollateral:        463.000000000000000000 * 1e18,
            borrowert0Np:              9.458540661328534467 * 1e18,
            borrowerCollateralization: 1.138406255550587998 * 1e18
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
                htp:                  9.889500000000000005 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             72_996.666666666666667000 * 1e18,
                pledgedCollateral:    1_042.000000000000000000 * 1e18,
                encumberedCollateral: 1_038.612458686545007338 * 1e18,
                poolDebt:             9_708.325961538461542938 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.000000000000000000 * 1e18,
                minDebtAmount:        485.416298076923077147 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      2_795.824779207511593472 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    109.823933241385648657 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   32.745170254153414999 * 1e18,
            claimableReserves :         32.745097143666787832 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(80 minutes);

        _assertPool(
            PoolParams({
                htp:                  10.025973419606037281 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_110.486627166698360626 * 1e18,
                pledgedCollateral:    1_042 * 1e18,
                encumberedCollateral: 1_052.945134138528111945 * 1e18,
                poolDebt:             9_842.299210198274857970 * 1e18,
                actualUtilization:    0.539376071352046283 * 1e18,
                targetUtilization:    0.958413284343188833 * 1e18,
                minDebtAmount:        984.229921019827485797 * 1e18,
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
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 80 minutes,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      174.739048700469474560 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.018492083647863197 * 1e18,
            borrowerCollateral:        1_040.000000000000000 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989644463447376554 * 1e18
        });

        // BPF Negative, Caller collateral constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10.0 * 1e18,
            bondChange:      19.536419560894800810 * 1e18,
            givenAmount:     1_747.390487004694745600 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        false
        });

        _assertPool(
            PoolParams({
                htp:                  10.025973419606037281 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_110.546230580506993313 * 1e18,
                pledgedCollateral:    1_032.0 * 1e18,
                encumberedCollateral: 869.141522276742086572 * 1e18,
                poolDebt:             8_124.213352534922313590 * 1e18,
                actualUtilization:    0.539415570795639499 * 1e18,
                targetUtilization:    0.958414005019059000 * 1e18,
                minDebtAmount:        812.421335253492231359 * 1e18,
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
                bondSize:          90.287513680490847847 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 80 minutes,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 90.287513680490847847 * 1e18,
                auctionPrice:      174.739048700469474560 * 1e18,
                debtInAuction:     8_104.932634420295318817 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_104.932634420295318817 * 1e18,
            borrowerCollateral:        1_030.000000000000000000 * 1e18,
            borrowert0Np:              8.974728252382013189 * 1e18,
            borrowerCollateralization: 1.187896593420381978 * 1e18
        });
    }

    function testTakeLoanDebtConstraintBpfPosResidual() external tearDown {

        // Increase neutralPrice so it exceeds TP
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   _i1505_26,
            lpAward: 9_999.543378995433790000 * 1e18,
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
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_004.514549350802762384 * 1e18,
                poolDebt:             18_736.999038461538470178 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        936.849951923076923509 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower2),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);
        
        _assertPool(
            PoolParams({
                htp:                  9.822951211365485637 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             82_996.210045662100457000 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.162590561266668491 * 1e18,
                poolDebt:             18_995.436335284145209602 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        949.771816764207260480 * 1e18,
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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_822.951211365485636462 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    109.823933241385648657 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636463 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });
        _assertReserveAuction({
            reserves:                   60.554587322829041789 * 1e18,
            claimableReserves :         60.554504106947293828 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(22000 seconds); // 6.11s hrs

        _assertPool(
            PoolParams({
                htp:                  9.520642715125814291 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_215.881747961316167813 * 1e18,
                pledgedCollateral:    2_042.000000000000000000 * 1e18,
                encumberedCollateral: 2_032.226386621120168430 * 1e18,
                poolDebt:             18_996.032662565740545058 * 1e18,
                actualUtilization:    0.353544427325713755 * 1e18,
                targetUtilization:    0.944118073902160936 * 1e18,
                minDebtAmount:        1_899.603266256574054506 * 1e18,
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
                bondSize:          109.823933241385648657 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 22000 seconds,
                referencePrice:    10.921190543779342162 * 1e18,
                totalBondEscrowed: 109.823933241385648657 * 1e18,
                auctionPrice:      10.508629868487414000 * 1e18,
                debtInAuction:     9_822.951211365485636463 * 1e18,
                debtToCollateral:  9.445145395543736189 * 1e18,
                neutralPrice:      10.921190543779342162 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_823.259585107984853687 * 1e18,
            borrowerCollateral:        1_040.000000000000000 * 1e18,
            borrowert0Np:              10.772605225053273112 * 1e18,
            borrowerCollateralization: 0.989620174526306750 * 1e18
        });
 
        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      31.107643684582954716 * 1e18,
            givenAmount:     9_954.602473053939912630 * 1e18,
            collateralTaken: 947.278817279990525519 * 1e18,
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
                totalBondEscrowed: 140.931576925968603373 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        92.721182720009474481 * 1e18,
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
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.805991398271413421 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_040 * 1e18,
            bond:           110.164296670852752941 * 1e18,
            transferAmount: 110.164296670852752941 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      2_804.489525424063798784 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    110.164296670852752941 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.805991398271413421 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertReserveAuction({
            reserves:                   32.836144076983058586 * 1e18,
            claimableReserves :         32.836070966144374628 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      2.738759302171937304 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.900422492752583093 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.805991398271413421 * 1e18,
            borrowerCollateralization: 0.986542937133981323 * 1e18
        });

        // partial take for 20 collateral
        // Collateral amount is restrained by taker
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   20 * 1e18,
            bondChange:      0.612405197366633896 * 1e18,
            givenAmount:     54.775186043438746080 * 1e18,
            collateralTaken: 20 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.776701868219386837 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.776701868219386837 * 1e18,
                auctionPrice:      2.738759302171937304 * 1e18,
                debtInAuction:     9_799.737641646680470914 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_799.737641646680470914 * 1e18,
            borrowerCollateral:        1_020 * 1e18,
            borrowert0Np:              10.957312926703812841 * 1e18,
            borrowerCollateralization: 0.972918685813433277 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    110.776701868219386837 * 1e18 // locked bond + reward, auction is not yet finished
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   32.894825757206621408 * 1e18,
            claimableReserves :         32.894752645919448151 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // take remaining collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_021 * 1e18,
            bondChange:      31.232665065698328745 * 1e18,
            givenAmount:     2_793.534488215376050080 * 1e18,
            collateralTaken: 1_020 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          142.009366933917715582 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 142.009366933917715582 * 1e18,
                auctionPrice:      2.738759302171937304 * 1e18,
                debtInAuction:     7_037.435818497002749734 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_037.435818497002749734 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    142.009366933917715582 * 1e18 // locked bond + reward, auction is not yet finalized
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   32.894825757206621563 * 1e18,
            claimableReserves :         32.894752645919448306 * 1e18,
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
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      2_012.644287642503398926 * 1e18,
            exchangeRate: 1.006368096702379663 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 7_037.435818497002749733 * 1e18
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
                totalBondEscrowed: 142.009366933917715582 * 1e18,
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
        _assertKicker({
            kicker:    _lender,
            claimable: 142.009366933917715582 * 1e18,
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
            lpBalance:    4_999.771689497716895000 * 1e18,
            collateral:   0,
            deposit:      11.556640377957587523 * 1e18,
            exchangeRate: 0.002311433620505696 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_81,
            lpBalance:   4_999.771689497716895000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    10_999.497716894977169000 * 1e18,
            collateral:   0,
            deposit:      11_069.543582033768694092 * 1e18,
            exchangeRate: 1.006368096702379662 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_72,
            lpBalance:   10_999.497716894977169000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    24_998.858447488584475000 * 1e18,
            collateral:   0,
            deposit:      24_998.858447488584475000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_62,
            lpBalance:   24_998.858447488584475000 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_52,
            lpBalance:    29_998.630136986301370000 * 1e18,
            collateral:   0,
            deposit:      29_998.630136986301370000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_52,
            lpBalance:   29_998.630136986301370000 * 1e18,
            depositTime: _startTime
        });

        vm.revertTo(postTakeSnapshot);

        _assertReserveAuction({
            reserves:                   32.894825757206621563 * 1e18,
            claimableReserves :         32.894752645919448306 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // partial clears / debt settled - max buckets to use is 0, settle only from reserves
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    0,
            settledDebt: 4.737452126198441015 * 1e18
        });
        _assertReserveAuction({
            reserves:                   28.157373631008180548 * 1e18,
            claimableReserves :         28.157300519721007291 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // partial clears / debt settled with max buckets to use is 1
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 2_012.644287642503398926 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          142.009366933917715582 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 142.009366933917715582 * 1e18,
                auctionPrice:      2.738759302171937304 * 1e18,
                debtInAuction:     5_020.054078728300909793 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_020.054078728300909793 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    142.009366933917715582 * 1e18 // locked bond + reward, auction is not yet finalized
        });

        // clear remaining debt
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    5,
            settledDebt: 5_020.054078728300909792 * 1e18
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
                totalBondEscrowed: 142.009366933917715582 * 1e18,
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
        _assertKicker({
            kicker:    _lender,
            claimable: 142.009366933917715582 * 1e18,
            locked:    0
        });

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 44_041.526029070332450899 * 1e18);

        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_lender), 44_183.535396004250166481 * 1e18);

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
            collateral:     1_040 * 1e18,
            bond:           110.164296670852752941 * 1e18,
            transferAmount: 110.164296670852752941 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      2_804.489525424063798784 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.805991398271413421 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    110.164296670852752941 * 1e18
        });
        _assertReserveAuction({
            reserves:                   32.836144076983058586 * 1e18,
            claimableReserves :         32.836070966144374628 * 1e18,
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
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.519763261339733329 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.957737011978628772 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.519763261339733329 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.218237587785293172 * 1e18,
            transferAmount: 0.218237587785293172 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.218237587785293172 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.285112352380185868 * 1e18,
                totalBondEscrowed: 110.382534258638046113 * 1e18,
                auctionPrice:      2_888.988762209327582208 * 1e18,
                debtInAuction:     9_995.146145767066608231 * 1e18,
                debtToCollateral:  9.759881630669866665 * 1e18,
                neutralPrice:      11.285112352380185868 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    110.382534258638046113 * 1e18
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
            lpAward: 0.999954337899543379 * 1e18,
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
            collateral:     1_040 * 1e18,
            bond:           110.164296670852752941 * 1e18,
            transferAmount: 110.164296670852752941 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      2_804.489525424063798784 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_040 * 1e18,
            borrowert0Np:              10.805991398271413421 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    110.164296670852752941 * 1e18
        });

        // after 6 hours, auction price should equal neutral price
        skip(6 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      10.955037208687749216 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );

        // skip another hour, and then take auction below neutral price
        skip(1 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          110.164296670852752941 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 7 hours,
                referencePrice:    10.955037208687749214 * 1e18,
                totalBondEscrowed: 110.164296670852752941 * 1e18,
                auctionPrice:      7.746381098414054648 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                debtToCollateral:  9.474417540364636198 * 1e18,
                neutralPrice:      10.955037208687749214 * 1e18
            })
        );

        // confirm kicker is rewarded
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_041 * 1e18,
            bondChange:      90.071460521501231737 * 1e18,
            givenAmount:     8_056.236342350616833920 * 1e18,
            collateralTaken: 1_040 * 1e18,
            isReward:        true
        });

        // borrower left with bad debt to be settled
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              1_887.583683779313868200 * 1e18,
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
            lpAward: 9_999.543378995433790000 * 1e18,
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
            collateral:     1_040 * 1e18,
            bond:           109.823933241385648657 * 1e18,
            transferAmount: 109.823933241385648657 * 1e18
        });

        skip(43000 seconds); // 11.94 hrs
        
        // force pool state update
        _updateInterest();

        (uint256 reservesBeforeTake, , , , ) = _poolUtils.poolReservesInfo(address(_pool));

        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_041 * 1e18,
            bondChange:      16.181928857894937154 * 1e18,
            givenAmount:     1_447.355717332744618880 * 1e18,
            collateralTaken: 1040 * 1e18,
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
            collateralToPledge: Maths.wmul(Maths.wdiv(750 * 1e18, _p0_00016), 1.05 * 1e18),
            newLup:             _p0_00016
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           761.075765343400230098 * 1e18,
            collateral:     48_949_158.443585816822704326 * 1e18,
            bond:           8.509085736677607076 * 1e18,
            transferAmount: 8.509085736677607076 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          8.509085736677607076 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    0.000017978108625356 * 1e18,
                totalBondEscrowed: 8.509085736677607076 * 1e18,
                auctionPrice:      0.004602395808091136 * 1e18,
                debtInAuction:     761.075765343400230098 * 1e18,
                debtToCollateral:  0.000015548291115577 * 1e18,
                neutralPrice:      0.000017978108625356 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              761.075765343400230098 * 1e18,
            borrowerCollateral:        48_949_158.443585816822704326 * 1e18,
            borrowert0Np:              0.000017733512306898 * 1e18,
            borrowerCollateralization: 0.994922677796581507 * 1e18
        });

        // should revert if take occurs at 0 price
        skip(71 hours);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          8.509085736677607076 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    0.000017978108625356 * 1e18,
                totalBondEscrowed: 8.509085736677607076 * 1e18,
                auctionPrice:      0 * 1e18,
                debtInAuction:     761.075765343400230098 * 1e18,
                debtToCollateral:  0.000015548291115577 * 1e18,
                neutralPrice:      0.000017978108625356 * 1e18
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
            collateralToPledge: 0.448329945169804100 * 1e18
        });

        skip(3276);

        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     635.803983894118939950 * 1e18,
            collateralToPull: 0.448329945169804100 * 1e18
        });

        _drawDebtNoLupCheck({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     100 * 1e18,
            limitIndex:         7000,
            collateralToPledge: 0.07 * 1e18
        });

        skip(964);
        skip(86400 * 200);

        _kick({
            from:           _kicker,
            borrower:       _borrower,
            debt:           102.876583480271499176 * 1e18,
            collateral:     0.070000000000000000 * 1e18,
            bond:           1.150195169774094785 * 1e18,
            transferAmount: 1.150195169774094785  * 1e18
        });

        skip(964);
        skip(3600 * 3);
        
        // the calculated repaid amount is with 1 WAD greater than the pool debt
        // check that take works and doesn't overflow
        _take({
            from:            _taker,
            borrower:        _borrower,
            maxCollateral:   0.067433366047580170 * 1e18,
            bondChange:      1.150195169774094785 * 1e18,
            givenAmount:     104.633060200351870411 * 1e18,
            collateralTaken: 0.023886288632228204 * 1e18,
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
            _addInitialLiquidity({
                from:    _lender,
                amount:  100_000 * 1e18,
                index:   _buckets[i]
            });
        }

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   102 * 1e18
        });

        _borrow({
            from:       _borrower,
            amount:     280_000 * 1e18,
            indexLimit: 7_388,
            newLup:     2_981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              280_269.230769230769360000 * 1e18,
            borrowerCollateral:        102 * 1e18,
            borrowert0Np:              3_177.141712785117009272 * 1e18,
            borrowerCollateralization: 1.043168509414078725 * 1e18
        });

        // skip to make borrower undercollateralized
        skip(400 days);

        _kick({
            from:           _taker,
            borrower:       _borrower,
            debt:           296_054.985884857245508279 * 1e18,
            collateral:     102 * 1e18,
            bond:           3_309.995367581407494354 * 1e18,
            transferAmount: 3_309.995367581407494354 * 1e18
        });
    }

    function testTakeCollateralFuzzy(uint256 takeAmount, uint256 skipTimeToTake) external tearDown {
        skipTimeToTake = bound(skipTimeToTake, 1.1 hours, 71 hours);

        // skip some time to make auction takeable
        skip(skipTimeToTake);
        (,,,, uint256 auctionPrice, , , , ) = _poolUtils.auctionStatus(address(_pool), _borrower);

        uint256 minCollateralTakeAmount = Maths.max(Maths.wdiv(1, auctionPrice), 1);

        takeAmount = bound(takeAmount, minCollateralTakeAmount, 100 * 1e18);

        uint256 quoteTokenRequired = Maths.ceilWmul(auctionPrice, takeAmount);

        // return when collateral price is too low and quote token required to take that collateral is 0
        if (quoteTokenRequired == 0) return;

        // calculate and mint quote tokens to buy collateral
        _mintQuoteAndApproveTokens(_taker, quoteTokenRequired);

        uint256 beforeTakerQuoteBalance = _quote.balanceOf(_taker);

        (, uint256 beforeCollateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // taker takes fuzzed amount of collateral
        _pool.take(_borrower, takeAmount, _taker, bytes(""));

        (, uint256 afterCollateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

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
