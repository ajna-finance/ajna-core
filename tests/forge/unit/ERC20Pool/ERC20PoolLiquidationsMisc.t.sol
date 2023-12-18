// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

contract ERC20PoolLiquidationsMiscTest is ERC20HelperContract {

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
                poolSize:             47_997.808219178082192000 * 1e18,
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
            reserves:                   9.882790437302427076 * 1e18,
            claimableReserves :         9.882742439494207898 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 72_000 * 1e18);

        // should revert if there's no auction started
        _assertTakeNoAuctionRevert({
            from:          _lender,
            borrower:      _borrower,
            maxCollateral: 10 * 1e18
        });
    }


    function testLenderForcedExit() external tearDown {

        skip(25 hours);
        
        // Lender attempts to withdraw entire position
        _removeLiquidity({
            from:     _lender,
            amount:   1_999.935282868211813754 * 1e18,
            index:    _i9_91,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 1_999.827380807531781086 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   4_999.838207170529534384 * 1e18,
            index:    _i9_81,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 4_999.568452018829452712 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   2_980 * 1e18,
            index:    _i9_72,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 2_979.839220727000051551 * 1e18
        });

        // Lender amount to withdraw is restricted by HTP 
        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:     _lender,
            index:    _i9_72
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_019.658496167977117449 * 1e18,
            collateral:   0,
            deposit:      8_020.091202353516607669 * 1e18,
            exchangeRate: 1.000053955687233597 * 1e18
        });

        skip(400 hours);

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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.709000367642488138 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.979503487849002840 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.709000367642488138 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.209172983065585793 * 1e18,
            transferAmount: 0.209172983065585793 * 1e18
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_019.658496167977117449 * 1e18,
            collateral:   0,          
            deposit:      8_034.234589314746482090 * 1e18,
            exchangeRate: 1.001817545367266480 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.209172983065585793 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.816379703115139992 * 1e18,
                totalBondEscrowed: 0.209172983065585793 * 1e18,
                auctionPrice:      2_768.993203997475837952 * 1e18,
                debtInAuction:     18.709000367642488138 * 1e18,
                debtToCollateral:  9.354500183821244069 * 1e18,
                neutralPrice:      10.816379703115139992 * 1e18
            })
        );

        // lender cannot withdraw - deposit in buckets within liquidation debt from the top-of-book down are frozen
        _assertRemoveDepositLockedByAuctionDebtRevert({
            from:     _lender,
            amount:   10.0 * 1e18,
            index:    _i9_72
        });

        // lender cannot move funds
        _assertMoveDepositLockedByAuctionDebtRevert({
            from:      _lender,
            amount:    10.0 * 1e18,
            fromIndex: _i9_72,
            toIndex:   _i9_81 
        });

        uint256 snapshot = vm.snapshot();
        skip(73 hours);

        // lender cannot move funds if auction not cleared
        _assertMoveDepositAuctionNotClearedRevert({
            from:      _lender,
            amount:    10.0 * 1e18,
            fromIndex: _i9_72,
            toIndex:   _i9_81 
        });

        vm.revertTo(snapshot);

        // lender can add / remove liquidity in buckets that are not within liquidation debt
        changePrank(_lender1);
        _pool.addQuoteToken(2_000 * 1e18, 5000, block.timestamp + 1 minutes);
        _pool.removeQuoteToken(2_000 * 1e18, 5000);

        skip(3 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.209172983065585793 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                referencePrice:    10.816379703115139992 * 1e18,
                totalBondEscrowed: 0.209172983065585793 * 1e18,
                auctionPrice:      30.593341743845004656 * 1e18,
                debtInAuction:     18.709000367642488138 * 1e18,
                debtToCollateral:  9.354500183821244069 * 1e18,
                neutralPrice:      10.816379703115139992 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.709259860714273064 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.999227114253786894 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2.0 * 1e18,
            bondChange:      0.209172983065585793 * 1e18,
            givenAmount:     19.028375417729999837 * 1e18,
            collateralTaken: 0.621977670077779898 * 1e18,
            isReward:        false
        });
        
        // Borrower is removed from auction, keeps collateral in system
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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1.378022329922220102 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  8.325570479144230295 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             38_033.245639566817177597 * 1e18,
                pledgedCollateral:    1_001.378022329922220102 * 1e18,
                encumberedCollateral: 856.425994510867961912 * 1e18,
                poolDebt:             8_005.356229946375284147 * 1e18,
                actualUtilization:    0.210612566139746491 * 1e18,
                targetUtilization:    0.822141283593523235 * 1e18,
                minDebtAmount:        800.535622994637528415 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 3 hours
            })
        );

        _removeAllLiquidity({
            from:     _lender,
            amount:   8_034.254839833419530359 * 1e18,
            index:    _i9_72,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 8_019.658496167977117449 * 1e18
        });
        
        _assertBucket({
            index:        _i9_72,
            lpBalance:    0,
            collateral:   0,          
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        _removeLiquidity({
            from:     _lender,
            amount:   21_000 * 1e18,
            index:    _i9_52,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 20_999.947069031215483677 * 1e18
        });

        _assertBucket({
            index:        _i9_52,
            lpBalance:    8_998.683067955085886323 * 1e18,
            collateral:   0,          
            deposit:      8_998.705749393805991615 * 1e18,
            exchangeRate: 1.000002520528676122 * 1e18
        });

        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:  _lender,
            index: _i9_52
        });

        skip(25 hours);

        _assertPool(
            PoolParams({
                htp:                  8.326532822441837927 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_998.990799733397644463 * 1e18,
                pledgedCollateral:    1_001.378022329922220102 * 1e18,
                encumberedCollateral: 873.784395127733970987 * 1e18,
                poolDebt:             8_006.281560040228775697 * 1e18,
                actualUtilization:    0.210612566139746491 * 1e18,
                targetUtilization:    0.822141283593523235 * 1e18,
                minDebtAmount:        800.628156004022877570 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 28 hours
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_006.281560040228775697 * 1e18,
            borrowerCollateral:        1_000.00 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.144447080510994053 * 1e18
        });

        // trigger accrual of pool interest that will push the lup back up
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  8.326532822441837927 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_999.787852072874979370 * 1e18,
                pledgedCollateral:    1_001.378022329922220102 * 1e18,
                encumberedCollateral: 873.784395127733970987 * 1e18,
                poolDebt:             8_006.281560040228775697 * 1e18,
                actualUtilization:    0.505203542638556630 * 1e18,
                targetUtilization:    0.825505559884289307 * 1e18,
                minDebtAmount:        800.628156004022877570 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.03645 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        skip(117 days);

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_100.375358686460903420 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.131153206043881494 * 1e18
        });

        // kick borrower 2
        changePrank(_lender);
        _pool.lenderKick(_i9_52, MAX_FENWICK_INDEX);

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             9_082.718302945104923507 * 1e18,
                pledgedCollateral:    1_001.378022329922220102 * 1e18,
                encumberedCollateral: 884.053543460678137147 * 1e18,
                poolDebt:             8_100.375358686460903420 * 1e18,
                actualUtilization:    0.889607809832559887 * 1e18,
                targetUtilization:    0.840177303006175138 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.03645 * 1e18,
                interestRateUpdate:   block.timestamp - 117 days
            })
        );

        _assertRemoveDepositLockedByAuctionDebtRevert({
            from:   _lender,
            amount: 10.0 * 1e18,
            index:  _i9_52
        });

        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          90.564949726435836850 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    9.366265850188852076 * 1e18,
                totalBondEscrowed: 90.564949726435836850 * 1e18,
                auctionPrice:      2.341566462547213020 * 1e18,
                debtInAuction:     8_100.375358686460903420 * 1e18,
                debtToCollateral:  8.100375358686460903 * 1e18,
                neutralPrice:      9.366265850188852076 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_100.712418988636152518 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.131106140203037430 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000.0 * 1e18,
            bondChange:      26.179508920446417251 * 1e18,
            givenAmount:     2_341.566462547213020000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             9_083.031109529777711575 * 1e18,
                pledgedCollateral:    1.378022329922220102 * 1e18,
                encumberedCollateral: 631.395120751024022658 * 1e18,
                poolDebt:             5_785.325465361869550519 * 1e18,
                actualUtilization:    0.819662267320821453 * 1e18,
                targetUtilization:    0.840177303006175138 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.03645 * 1e18,
                interestRateUpdate:   block.timestamp - 117 days - 10 hours
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_785.325465361869550519 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 7_990 * 1e18,
            index:  _i9_52
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 5_785.325465361869550518 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             3_300.544788087832541103 * 1e18,
                pledgedCollateral:    1.378022329922220102 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.819662267320821453 * 1e18,
                targetUtilization:    0.840177303006175138 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.032805 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0,
            collateral:   0,          
            deposit:      0,
            exchangeRate: 1 * 1e18
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
            lpBalance:    0,
            collateral:   0,          
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_52,
            lpBalance:    8_998.683067955085886323 * 1e18,
            collateral:   0,          
            deposit:      3_300.544788087832540727 * 1e18,
            exchangeRate: 0.366780868174065821 * 1e18
        });
    }
 }
