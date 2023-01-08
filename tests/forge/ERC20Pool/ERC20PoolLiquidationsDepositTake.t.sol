// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsDepositTakeTest is ERC20HelperContract {

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
        _assertDepositTakeNoAuctionRevert(
            {
                from:     _lender,
                borrower: _borrower,
                index:    _i9_91
            }
        );

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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.969909752188970169 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.939819504377940339 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.975063576969429891 * 1e18
            }
        );
        
        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           20.189067248182664593 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.199398195043779403 * 1e18,
                transferAmount: 0.199398195043779403 * 1e18
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.199398195043779403 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.199398195043779403 * 1e18,
                auctionPrice:      334.988967673549397664 * 1e18,
                debtInAuction:     20.189067248182664592 * 1e18,
                thresholdPrice:    10.094533624091332296 * 1e18,
                neutralPrice:      10.468405239798418677 * 1e18
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.199398195043779403 * 1e18
            }
        );
    }

    function testDepositTakeCollateralRestrict() external tearDown {
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
               deposit:      2_000 * 1e18,
               exchangeRate: 1 * 1e27
           }
        );
        _assertBorrower(
           {
               borrower:                  _borrower,
               borrowerDebt:              20.189741380689676442 * 1e18,
               borrowerCollateral:        2 * 1e18,
               borrowert0Np:              10.115967548076923081 * 1e18,
               borrowerCollateralization: 0.962993599742653326 * 1e18
           }
        );

        // add liquidity to accrue interest and update reserves before deposit take
        _addLiquidity(
           {
               from:    _lender1,
               amount:  1 * 1e18,
               index:   _i9_52,
               lpAward: 0.999996755983514720095749768 * 1e27,
               newLup:  9.721295865031779605 * 1e18
           }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000 * 1e27,
               collateral:   0,
               deposit:      2_000.006488054017914000 * 1e18,
               exchangeRate: 1.000003244027008957000000000 * 1e27
           }
        );
        _assertReserveAuction(
           {
               reserves:                   286.940475866492567343 * 1e18,
               claimableReserves :         245.508339417301835201 * 1e18,
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
               bondSize:          0.199398195043779403 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6.5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.199398195043779403 * 1e18,
               auctionPrice:      7.402280333270247968 * 1e18,
               debtInAuction:     20.189741380689676442 * 1e18,
               thresholdPrice:    10.094870690344838221 * 1e18,
               neutralPrice:      10.468405239798418677 * 1e18
           })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              20.189741380689676442 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.962993599742653326 * 1e18
            }
        );

        // Amount is restricted by the collateral in the loan
        _depositTake(
           {
               from:             _taker,
               borrower:         _borrower,
               kicker:           _lender,
               index:            _i9_91,
               collateralArbed:  2 * 1e18,
               quoteTokenAmount: 19.834369686871824148 * 1e18,
               bondChange:       0.198343696868718241 * 1e18,
               isReward:         true,
               lpAwardTaker:     0,
               lpAwardKicker:    0.198343053438495848000000000 * 1e27
           }
        );

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
               lpBalance:   2_000.198343053438495848000000000 * 1e27,
               depositTime: _startTime + 250 days + 6.5 hours
        }
        );
        _assertBucket(
           {
               index:        _i9_91,
               lpBalance:    2_000.198343053438495848000000000 * 1e27,
               collateral:   2 * 1e18,
               deposit:      1_980.370462064014808094 * 1e18,
               exchangeRate: 1.000003244027008957000258924 * 1e27
           }
        );
        // reserves should remain the same after deposit take
        _assertReserveAuction(
           {
               reserves:                   288.353757763140844694 * 1e18,
               claimableReserves :         247.012735034416886695 * 1e18,
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
               bondSize:          0.199398195043779403 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 6.5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.199398195043779403 * 1e18,
               auctionPrice:      7.402280333270247968 * 1e18,
               debtInAuction:     1.966997287334847886 * 1e18,
               thresholdPrice:    0,
               neutralPrice:      10.468405239798418677 * 1e18
           })
        ); 
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              1.966997287334847886 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0
            }
        );

        // deposit take should fail on an auction without any remaining collateral to auction
        _assertDepositTakeInsufficentCollateralRevert(
           {
               from:     _taker,
               borrower: _borrower,
               index:    _i9_91
           }
        );
    }

    function testDepositTakeDebtRestrict() external tearDown {

        skip(5 hours);

        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.199398195043779403 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.199398195043779403 * 1e18,
               auctionPrice:      20.936810479596837344 * 1e18,
               debtInAuction:     20.189067248182664592 * 1e18,
               thresholdPrice:    10.094792904825850359 * 1e18,
               neutralPrice:      10.468405239798418677 * 1e18
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
                borrowerDebt:              20.189585809651700719 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 149.112888462473727465 * 1e18
            }
        );

        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    25_000 * 1e27,
                collateral:   0.0 * 1e18,
                deposit:      25_000 * 1e18,
                exchangeRate: 1.0 * 1e27
            }
        );

        // Amount is restricted by the debt in the loan
        _depositTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i1505_26,
                collateralArbed:  0.014351542794629452 * 1e18,
                quoteTokenAmount: 21.602856816327319769 * 1e18,
                bondChange:       0.199398195043779403 * 1e18,
                isReward:         false,
                lpAwardTaker:     0,
                lpAwardKicker:    0
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.985648457205370548 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   0,
                depositTime: 0
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
                lpBalance:    25_000 * 1e27,
                collateral:   0.014351542794629452 * 1e18,
                deposit:      24_978.397143183672680231 * 1e18,
                exchangeRate: 1.000000000000000000010323898 * 1e27
            }
        );

        _assertReserveAuction(
            {
                reserves:                   288.543944498908261870 * 1e18,
                claimableReserves :         247.213075232011850972 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );
    }

    function testDepositTakeDepositRestrict() external tearDown {

        skip(5 hours);

        _assertAuction(
           AuctionParams({
               borrower:          _borrower,
               active:            true,
               kicker:            _lender,
               bondSize:          0.199398195043779403 * 1e18,
               bondFactor:        0.01 * 1e18,
               kickTime:          block.timestamp - 5 hours,
               kickMomp:          9.818751856078723036 * 1e18,
               totalBondEscrowed: 0.199398195043779403 * 1e18,
               auctionPrice:      20.936810479596837344 * 1e18,
               debtInAuction:     20.189067248182664592 * 1e18,
               thresholdPrice:    10.094792904825850359 * 1e18,
               neutralPrice:      10.468405239798418677 * 1e18
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
                borrowerDebt:              20.189585809651700719 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.963001020098637267 * 1e18
            }
        );

        // Amount is restricted by the deposit in the bucket in the loan
        _depositTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i1505_26,
                collateralArbed:  0.009965031187761219 * 1e18,
                quoteTokenAmount: 15.0 * 1e18,
                bondChange:       0.15 * 1e18,
                isReward:         false,
                lpAwardTaker:     0,
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
               thresholdPrice:    3.317960196583009903 * 1e18,
               neutralPrice:      0
           })
        );

        _assertBucket(
            {
                index:        _i1505_26,
                lpBalance:    15 * 1e27,
                collateral:   0.009965031187761219 * 1e18,
                deposit:      0,
                exchangeRate: 0.999999999999999999688877723 * 1e27
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              6.602856816327319769 * 1e18,
                borrowerCollateral:        1.990034968812238781 * 1e18,
                borrowert0Np:              3.417963776167124997 * 1e18,
                borrowerCollateralization: 2.929901291475173000 * 1e18
            }
        );

        _assertLenderLpBalance(
            {
                lender:      _taker,
                index:       _i1505_26,
                lpBalance:   0,
                depositTime: 0
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

    function testDepositTakeGTNeutralPrice() external tearDown {

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
                borrowerDebt:              20.189378383465778990 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.963010913995558897 * 1e18
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.199398195043779403 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.199398195043779403 * 1e18,
                auctionPrice:      83.747241918387349408 * 1e18,
                debtInAuction:     20.189378383465778990 * 1e18,
                thresholdPrice:    10.094689191732889495 * 1e18,
                neutralPrice:      10.468405239798418677 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              20.189378383465778990 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.115967548076923081 * 1e18,
                borrowerCollateralization: 0.963010913995558897 * 1e18
            }
        );

        _depositTake(
            {
                from:             _taker,
                borrower:         _borrower,
                kicker:           _lender,
                index:            _i10016,
                collateralArbed:  0.002156704581707556 * 1e18,
                quoteTokenAmount: 21.602634870308383519 * 1e18,
                bondChange:       0.199398195043779403 * 1e18,
                isReward:         false,
                lpAwardTaker:     0,
                lpAwardKicker:    0
            }
        );
        
        // deposit taker wasn't rewarded any LPBs in arbed bucket
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
                depositTime: _startTime + 250 days + 3 hours
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
                lpBalance:    1_000 * 1e27,      // LP balance in arbed bucket increased with LPs awarded for deposit taker
                collateral:   0.002156704581707556 * 1e18,          // arbed collateral added to the arbed bucket
                deposit:      978.397365129691616481* 1e18,        // quote token amount is diminished in arbed bucket
                exchangeRate: 0.999999999999999999966005802 * 1e27
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.997843295418292444 * 1e18,
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

    function testDepositTakeReverts() external tearDown {

        // should revert if auction in grace period
        _assertDepositTakeAuctionInCooldownRevert(
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
                bondSize:          0.199398195043779403 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 2.5 hours,
                kickMomp:          9.818751856078723036 * 1e18, 
                totalBondEscrowed: 0.199398195043779403 * 1e18,
                auctionPrice:      118.436485332323967968 * 1e18,
                debtInAuction:     20.189067248182664592 * 1e18,
                thresholdPrice:    10.094663263626140337 * 1e18,
                neutralPrice:      10.468405239798418677 * 1e18
            })
        );

        // should revert if bucket deposit is 0
        _assertDepositTakeAuctionInsufficientLiquidityRevert(
            {
                from:     _taker,
                borrower: _borrower,
                index:    _i100_33
            }
        );

        // should revert if auction price is greater than the bucket price
        _assertDepositTakeAuctionPriceGreaterThanBucketPriceRevert(
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
        _assertDepositTakeDebtUnderMinPoolDebtRevert(
            {
                from:     _taker,
                borrower: _borrower,
                index:    _i9_91
            }
        );
    }
}
