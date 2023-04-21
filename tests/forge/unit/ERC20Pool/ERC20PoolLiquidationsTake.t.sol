// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

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
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 1.009034539679184679 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.471136974495192174 * 1e18,
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

    function testTakeCoolDownPeriod() external tearDown {

        // should revert if there's no auction started
        _assertTakeNoAuctionRevert({
            from:          _lender,
            borrower:      _borrower,
            maxCollateral: 10 * 1e18
        });

        /********************/
        /*** Kick Auction ***/
        /********************/

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
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.229512113654856365 * 1e18,
            transferAmount: 98.229512113654856365 * 1e18
        });

        /********************/
        /*** Take Auction ***/
        /********************/

        skip(30 minutes);

        // should revert if still in cool down period
        _assertTakeAuctionInCooldownRevert({
            from:          _lender,
            borrower:      _borrower2,
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
            borrowert0Np:              1_575.326150647652569911 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636462* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           2_946.885363409645690939 * 1e18,
            transferAmount: 2_946.885363409645690939 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    2_946.885363409645690939 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.738101507554206918 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977433325291186371 * 1e18
        });
        _assertReserveAuction({
            reserves:                   179.552281242188325467 * 1e18,
            claimableReserves :         83.959896655448350900 * 1e18,
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
                encumberedCollateral: 1_966.805856622794362479 * 1e18,
                poolDebt:             19_119.901641307458013950 * 1e18,
                actualUtilization:    0.230343095389734878 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        1_911.990164130745801395 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_946.885363409645690939 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                kickMomp:          1505.263728469068226832 * 1e18,
                totalBondEscrowed: 2_946.885363409645690939 * 1e18,
                auctionPrice:      12.005655124053999200 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.946479265745114634 * 1e18,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_946.479265745114634611 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977360491617486321 * 1e18
        });
 
        // BPF Positive, Loan Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      3_598.602237971309466520* 1e18,
            givenAmount:     12_005.655124053999200000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          6_545.487601380955157459 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 47000 seconds,
                kickMomp:          1_505.263728469068226832 * 1e18,
                totalBondEscrowed: 6_545.487601380955157459 * 1e18,
                auctionPrice:      12.005655124053999200 * 1e18,
                debtInAuction:     2_235.679928264582926033 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        // Bad debt remains
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              2_235.679928264582926033 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0
        });

        _assertPool(
            PoolParams({
                htp:                  9.155112151259823732 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             83_220.903511207268524311 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 1_150.437597356925322190 * 1e18,
                poolDebt:             11_409.102303826926305373 * 1e18,
                actualUtilization:    0.230020694596419217 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        1_140.910230382692630537 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // borrower recollateralizes themselves by pleding collateral
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_000 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 6_545.487601380955157459 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    2.235679928264582926 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              2_235.679928264582926033 * 1e18,
            borrowerCollateral:        1_000.0 * 1e18,
            borrowert0Np:              351.432169383213758786 * 1e18,
            borrowerCollateralization: 4.435869695862053063 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  9.155112151259823732 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             83_220.903511207268524311 * 1e18,
                pledgedCollateral:    2_002.0 * 1e18,
                encumberedCollateral: 1_150.437597356925322190 * 1e18,
                poolDebt:             11_409.102303826926305373 * 1e18,
                actualUtilization:    0.230020694596419217 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        570.455115191346315269 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
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
            borrowerDebt:              9_689.307692307692312160* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636462* 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           2_946.885363409645690939 * 1e18,
            transferAmount: 2_946.885363409645690939 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    2_946.885363409645690939 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.738101507554206918 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977433325291186371 * 1e18
        });
        _assertReserveAuction({
            reserves:                   179.552281242188325467 * 1e18,
            claimableReserves :         83.959896655448350900 * 1e18,
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
                encumberedCollateral: 1_966.793383261429981984 * 1e18,
                poolDebt:             19_119.780384071203414682 * 1e18,
                actualUtilization:    0.230343095389734878 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        1_911.978038407120341468 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_946.885363409645690939 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                kickMomp:          1505.263728469068226832 * 1e18,
                totalBondEscrowed: 2_946.885363409645690939 * 1e18,
                auctionPrice:      25.933649477033750336 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.946416185787442558 * 1e18,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_946.416185787442558740 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977366690016717763 * 1e18
        });

        // BPF Positive, caller collateral is constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10 * 1e18,
            bondChange:      77.051046618010115327 * 1e18,
            givenAmount:     259.336494770337503360 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        true
        });

        // Residual is not collateralized, auction is active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            address(0xb012341CA6E91C00A290F658fbaA5211F2559fB1),
                bondSize:          3_023.936410027655806266 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                kickMomp:          1_505.263728469068226832 * 1e18,
                totalBondEscrowed: 3_023.936410027655806266 * 1e18,
                auctionPrice:      25.933649477033750336 * 1e18,
                debtInAuction:     10_460.379870640236149821 * 1e18,
                thresholdPrice:    10.566040273373975908 * 1e18,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              10_460.379870640236149821 * 1e18,
            borrowerCollateral:        990 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.920050994839483961 * 1e18
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
            borrowert0Np:              1_575.326150647652569911 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636462 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           2_946.885363409645690939 * 1e18,
            transferAmount: 2_946.885363409645690939 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    2_946.885363409645690939 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.738101507554206918 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977433325291186371 * 1e18
        });
        _assertReserveAuction({
            reserves:                   179.552281242188325467 * 1e18,
            claimableReserves :         83.959896655448350900 * 1e18,
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
                encumberedCollateral: 1_966.793383261429981984 * 1e18,
                poolDebt:             19_119.780384071203414682 * 1e18,
                actualUtilization:    0.230343095389734878 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        1_911.978038407120341468 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_946.885363409645690939 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                kickMomp:          1505.263728469068226832 * 1e18,
                totalBondEscrowed: 2_946.885363409645690939 * 1e18,
                auctionPrice:      25.933649477033750336 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.946416185787442558 * 1e18,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_946.416185787442558740 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977366690016717763 * 1e18
        });
 
        // BPF Positive, Caller Col constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   577 * 1e18,
            bondChange:      4_445.845389859183654387 * 1e18,
            givenAmount:     14_963.715748248473943872 * 1e18,
            collateralTaken: 577 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 7_392.730753268829345326 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0.295023547052655433 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              124.794960403273248520 * 1e18,
            borrowerCollateral:        423.000000000000000000 * 1e18,
            borrowert0Np:              0.305539336585968822 * 1e18,
            borrowerCollateralization: 5_102.181651284975713837 * 1e18
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
            borrowert0Np:              10.275765152019230606 * 1e18,
            borrowerCollateralization: 1.003301388885552947 * 1e18
        });

        skip(100 days);

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.229512113654856365 * 1e18,
            transferAmount: 98.229512113654856365 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.229512113654856365 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.229512113654856365 * 1e18,
                auctionPrice:      333.359923587916662112 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.945738101507554206 * 1e18,
                neutralPrice:      10.417497612122395691 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.229512113654856365 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.738101507554206918 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.275765152019230606 * 1e18,
            borrowerCollateralization: 0.977433325291186371 * 1e18
        });
        _assertReserveAuction({
            reserves:                   152.199485178078897491 * 1e18,
            claimableReserves :         102.373123280655390094 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        skip(2 hours);

        _assertPool(
            PoolParams({
                htp:                  9.767138988573636287 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_113.822894306622582000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_025.109990820819378515 * 1e18,
                poolDebt:             9_965.397514969196970863 * 1e18,
                actualUtilization:    0.553626243304705638 * 1e18,
                targetUtilization:    0.001969479191890912 * 1e18,
                minDebtAmount:        996.539751496919697086 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.229512113654856365 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.229512113654856365 * 1e18,
                auctionPrice:      166.679961793958331072 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.945862991697064688 * 1e18,
                neutralPrice:      10.417497612122395691 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.862991697064688926 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              10.275765152019230606 * 1e18,
            borrowerCollateralization: 0.977421051662107488 * 1e18
        });

        // BPF Negative, Caller collateral constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   10.0 * 1e18,
            bondChange:      16.667996179395833107 * 1e18,
            givenAmount:     1_666.799617939583310720 * 1e18,
            collateralTaken: 10.0 * 1e18,
            isReward:        false
        });

        _assertPool(
            PoolParams({
                htp:                  9.767261636066140969 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_113.933684656668798000 * 1e18,
                pledgedCollateral:    992.0 * 1e18,
                encumberedCollateral: 925.268444796891645955 * 1e18,
                poolDebt:             8_994.808306448408188367 * 1e18,
                actualUtilization:    0.414995088417021354 * 1e18,
                targetUtilization:    0.001969479191890912 * 1e18,
                minDebtAmount:        449.740415322420409418 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   block.timestamp - 2 hours
            })
        );
        // Residual is collateralized, auction is not active
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 81.561515934259023258 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.065933114319470612 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_975.273783176275906430 * 1e18,
            borrowerCollateral:        990.000000000000000000 * 1e18,
            borrowert0Np:              9.528891915274728851 * 1e18,
            borrowerCollateralization: 1.072288504939130410 * 1e18
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
            borrowert0Np:              1_575.326150647652569911 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.822951211365485636 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_822.951211365485636462 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.989651241857326201 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           2_946.885363409645690939 * 1e18,
            transferAmount: 2_946.885363409645690939 * 1e18
        });

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    2_946.885363409645690939 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_945.738101507554206918 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977433325291186371 * 1e18
        });
        _assertReserveAuction({
            reserves:                   179.552281242188325467 * 1e18,
            claimableReserves :         83.959896655448350900 * 1e18,
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
                encumberedCollateral: 1_966.793383261429981984 * 1e18,
                poolDebt:             19_119.780384071203414682 * 1e18,
                actualUtilization:    0.230343095389734878 * 1e18,
                targetUtilization:    0.451806923386623777 * 1e18,
                minDebtAmount:        1_911.978038407120341468 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          2_946.885363409645690939 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          block.timestamp - 43000 seconds,
                kickMomp:          1505.263728469068226832 * 1e18,
                totalBondEscrowed: 2_946.885363409645690939 * 1e18,
                auctionPrice:      25.933649477033750336 * 1e18,
                debtInAuction:     9_945.738101507554206918 * 1e18,
                thresholdPrice:    9.946416185787442558 * 1e18,
                neutralPrice:      1_597.054445085392479852 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_946.416185787442558740 * 1e18,
            borrowerCollateral:        1_000.000000000000000 * 1e18,
            borrowert0Np:              1_575.326150647652569911 * 1e18,
            borrowerCollateralization: 0.977366690016717763 * 1e18
        });
 
        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      4_498.595526577118719269 * 1e18,
            givenAmount:     15_141.260845369682257120 * 1e18,
            collateralTaken: 583.846128512627511609 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 7_445.480889986764410208 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        416.153871487372488391 * 1e18,
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
            borrowerDebt:              9_853.394241979221645666 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      334.393063846970122880 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.533942419792216457 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_976.561670003961916237 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.974413448899967463 * 1e18
        });
        _assertReserveAuction({
            reserves:                   152.670996883580244810 * 1e18,
            claimableReserves :         102.690517143674698866 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        uint256 preTakeSnapshot = vm.snapshot();

        skip(364 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 364 minutes,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      9.977887794379977376 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976941682501173528 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_976.941682501173528637 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.974376334391351811 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      99.778877943799773760 * 1e18,
            givenAmount:     9_977.887794379977376000 * 1e18,
            collateralTaken: 1000.0 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          198.312820363591990217 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 364 minutes,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 198.312820363591990217 * 1e18,
                auctionPrice:      9.977887794379977376 * 1e18,
                debtInAuction:     797.218683840078073642 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              797.218683840078073642 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    198.312820363591990217 * 1e18
        });

        vm.revertTo(preTakeSnapshot);

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      0.653111452826113536 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.977188071964833915 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_977.188071964833915171 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.974352271893912411 * 1e18
        });

        // partial take for 20 collateral
        // Collateral amount is restrained by taker
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   20 * 1e18,
            bondChange:      0.130622290565222707 * 1e18,
            givenAmount:     13.062229056522270720 * 1e18,
            collateralTaken: 20 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.664564710357439164 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.664564710357439164 * 1e18,
                auctionPrice:      0.653111452826113536 * 1e18,
                debtInAuction:     10_662.659630236415241212 * 1e18,
                thresholdPrice:    10.880264928812668613 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              10_662.659630236415241212 * 1e18,
            borrowerCollateral:        980 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.893479701885589664 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.664564710357439164 * 1e18 // locked bond + reward, auction is not yet finished
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   851.146019130720564512 * 1e18,
            claimableReserves :         797.735043457124114400 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // take remaining collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   981 * 1e18,
            bondChange:      6.400492237695912653 * 1e18,
            givenAmount:     640.049223769591265280 * 1e18,
            collateralTaken: 980 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.065056948053351817 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 105.065056948053351817 * 1e18,
                auctionPrice:      0.653111452826113536 * 1e18,
                debtInAuction:     10_029.010898704519888232 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              10_029.010898704519888232 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    105.065056948053351817 * 1e18 // locked bond + reward, auction is not yet finalized
        });
        // reserves should increase after take action
        _assertReserveAuction({
            reserves:                   851.146019130720564159 * 1e18,
            claimableReserves :         800.903287114783590811 * 1e18,
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
            deposit:      2_012.747858039391834000 * 1e18,
            exchangeRate: 1.006373929019695917 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 9_891.942801061873188724 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 105.065056948053351817 * 1e18,
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
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 105.065056948053351817 * 1e18,
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
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_81,
            lpBalance:   0, // bucket is bankrupt
            depositTime: _startTime
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      8_936.865842780727181926 * 1e18,
            exchangeRate: 0.812442349343702471 * 1e18
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
 
        vm.revertTo(postTakeSnapshot);

        _assertReserveAuction({
            reserves:                   851.146019130720564159 * 1e18,
            claimableReserves :         800.903287114783590811 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        // partial clears / debt settled - max buckets to use is 0, settle only from reserves
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    0,
            settledDebt: 839.513270214929712159 * 1e18
        });
        _assertReserveAuction({
            reserves:                   0,
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
            settledDebt: 1_985.239310813522517867 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          105.065056948053351817 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 105.065056948053351817 * 1e18,
                auctionPrice:      0.653111452826113536 * 1e18,
                debtInAuction:     7_165.117021534407490074 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      10.449783245217816340  * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_165.117021534407490074 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    105.065056948053351817 * 1e18 // locked bond + reward, auction is not yet finalized
        });

        // clear remaining debt
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    5,
            settledDebt: 7_067.190220033420958698 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 105.065056948053351817 * 1e18,
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
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 105.065056948053351817 * 1e18,
            locked:    0
        });

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 46_248.354604754094247543 * 1e18);

        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_lender), 46_353.419661702147599360 * 1e18);

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
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      334.393063846970122880 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_976.561670003961916237 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.974413448899967463 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.533942419792216457 * 1e18
        });
        _assertReserveAuction({
            reserves:                   152.670996883580244810 * 1e18,
            claimableReserves :         102.690517143674698866 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.915429506968330175 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.830859013936660351 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.980421055709173463 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           20.103533325378289431 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.198308590139366604 * 1e18,
            transferAmount: 0.198308590139366604 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.198308590139366604 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.732251009931583061 * 1e18,
                auctionPrice:      333.158431434135893856 * 1e18,
                debtInAuction:     10_148.135301540522920718 * 1e18,
                thresholdPrice:    10.051766662689144715 * 1e18,
                neutralPrice:      10.411200982316746683 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.732251009931583061 * 1e18
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

    function testTakeAfterSettleReverts() external tearDown {
        // Borrower draws debt
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized and kick auction
        skip(100 days);
        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        // Take everything
        skip(10 hours);
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      6.531114528261135360 * 1e18,
            givenAmount:     653.111452826113536000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // Partially settle the auction, such that it is not removed from queue
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 2_824.752581028452230026 * 1e18
        });

        // Borrower draws more debt
        _drawDebt({
            from:               _borrower2,
            borrower:           _borrower2,
            amountToBorrow:     1_000 * 1e18,
            limitIndex:         _i9_72,
            collateralToPledge: 1_000 * 1e18,
            newLup:             9.721295865031779605 * 1e18
        });

        // Take should revert
        _assertTakeNoAuctionRevert(_borrower2, _borrower2, 1_000 * 1e18);
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
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      334.393063846970122880 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18,
                thresholdPrice:    9.976561670003961916 * 1e18,
                neutralPrice:      10.449783245217816340 * 1e18
            })
        );
        assertEq(_poolUtils.momp(address(_pool)), 9.818751856078723036 * 1e18);
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_976.561670003961916237 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.974413448899967463 * 1e18
        });
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    98.533942419792216457 * 1e18
        });

        skip(3 hours);

        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_001 * 1e18, 
            collateral:   0,
            deposit:      2_013.691743633473441469 * 1e18,
            exchangeRate: 1.006342700466503469 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      98.533942419792216457 * 1e18,
            givenAmount:     10_675.122057515096837734 * 1e18,
            collateralTaken: 127.695496248694959327 * 1e18,
            isReward:        false
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        872.304503751305040673 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
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
            debt:           9_945.738101507554206918 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           2_946.885363409645690939 * 1e18,
            transferAmount: 2_946.885363409645690939 * 1e18
        });

        skip(43000 seconds); // 11.94 hrs
        
        // force pool state update
        _updateInterest();

        (uint256 borrowerDebt, ,) = _poolUtils.borrowerInfo(address(_pool), _borrower2);

        (uint256 reservesBeforeTake, , , , ) = _poolUtils.poolReservesInfo(address(_pool));

        // BPF Positive, Loan Debt constraint
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_001 * 1e18,
            bondChange:      4_498.595526577118719269 * 1e18,
            givenAmount:     15_141.260845369682257120 * 1e18,
            collateralTaken: 583.846128512627511609 * 1e18,
            isReward:        true
        });

        (uint256 reservesAfterTake, , , , ) = _poolUtils.poolReservesInfo(address(_pool));

        // reserves should only increase by 7% of the borrower debt on first take and settle auction
        assertEq(reservesAfterTake, reservesBeforeTake + Maths.floorWmul(borrowerDebt, 0.07 * 1e18));
    }
}

contract ERC20PoolLiquidationsTakeAndRepayAllDebtInPoolTest is ERC20HelperContract {

    address internal _lender;
    address internal _borrower;
    address internal _kicker;
    address internal _taker;

    function setUp() external {
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
            debt:           104.162540773774892916 * 1e18,
            collateral:     0.067433366047580170 * 1e18,
            bond:           1.028765834802714992 * 1e18,
            transferAmount: 1.028765834802714992  * 1e18
        });

        skip(964);
        skip(3600 * 3);

        // the calculated repaid amount is with 1 WAD greater than the pool debt
        // check that take works and doesn't overflow
        _take({
            from:            _taker,
            borrower:        _borrower,
            maxCollateral:   0.067433366047580170 * 1e18,
            bondChange:      1.028765834802714992 * 1e18,
            givenAmount:     111.456205336913048951 * 1e18,
            collateralTaken: 0.010471102621651343 * 1e18,
            isReward:        false
        });

    }
}
