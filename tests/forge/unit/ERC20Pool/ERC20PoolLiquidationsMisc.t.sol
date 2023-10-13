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


    function testLenderForcedExit() external tearDown {

        skip(25 hours);
        
        // Lender attempts to withdraw entire position
        _removeLiquidity({
            from:     _lender,
            amount:   2_000.00 * 1e18,
            index:    _i9_91,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 1_999.892091281103336057 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   5_000 * 1e18,
            index:    _i9_81,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 4_999.730228202758340143 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   2_992.8 * 1e18,
            index:    _i9_72,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 2_992.638525393043032076 * 1e18
        });

        // Lender amount to withdraw is restricted by HTP 
        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:     _lender,
            index:    _i9_72
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_007.361474606956967924 * 1e18,
            collateral:   0,
            deposit:      8_007.793529977461399000 * 1e18,
            exchangeRate: 1.000053957270678310 * 1e18
        });

        skip(16 hours);

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
                thresholdPrice:    9.636421658861206949 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.272843317722413899 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.998794730435100100 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.272843317722413898 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.292568312161539120 * 1e18,
            transferAmount: 0.292568312161539120 * 1e18
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_007.361474606956967924 * 1e18,
            collateral:   0,          
            deposit:      8_008.356713096000609696 * 1e18,
            exchangeRate: 1.000124290441014779 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.292568312161539120 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    11.099263219668902589 * 1e18,
                totalBondEscrowed: 0.292568312161539120 * 1e18,
                auctionPrice:      2_841.411384235239062784 * 1e18,
                debtInAuction:     19.272843317722413899 * 1e18,
                thresholdPrice:    9.636421658861206949 * 1e18,
                neutralPrice:      11.099263219668902589 * 1e18
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
        _pool.addQuoteToken(2_000 * 1e18, 5000, block.timestamp + 1 minutes, false);
        _pool.removeQuoteToken(2_000 * 1e18, 5000);

        skip(3 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.292568312161539120 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                referencePrice:    11.099263219668902589 * 1e18,
                totalBondEscrowed: 0.292568312161539120 * 1e18,
                auctionPrice:      31.393457155209254668 * 1e18,
                debtInAuction:     19.272843317722413899 * 1e18,
                thresholdPrice:    9.636555315636456019 * 1e18,
                neutralPrice:      11.099263219668902589 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.273110631272912039 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 0.998780877385080338 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2.0 * 1e18,
            bondChange:      0.292568312161539120 * 1e18,
            givenAmount:     19.722195067961733839 * 1e18,
            collateralTaken: 0.628226288377708765 * 1e18,
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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1.371773711622291235 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  7.989580407145861718 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             63_008.829556315248414267 * 1e18,
                pledgedCollateral:    1_001.371773711622291235 * 1e18,
                encumberedCollateral: 821.863722498661263922 * 1e18,
                poolDebt:             7_989.580407145861717463 * 1e18,
                actualUtilization:    0.121389232097000537 * 1e18,
                targetUtilization:    0.822758145478171949 * 1e18,
                minDebtAmount:        798.958040714586171746 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 3 hours
            })
        );

        _removeLiquidity({
            from:     _lender,
            amount:   8_008.368802228565193289 * 1e18,
            index:    _i9_72,
            newLup:   9.624807173121239337 * 1e18,
            lpRedeem: 8_007.361474606956967924 * 1e18
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
            amount:   25_000.037739117392250000 * 1e18,
            index:    _i9_62,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 25_000.000000000000000000 * 1e18
        });

        _assertBucket({
            index:        _i9_62,
            lpBalance:    0.000000000000000000 * 1e18,
            collateral:   0,          
            deposit:      0.000000000000000000 * 1e18,
            exchangeRate: 1.000000000000000000 * 1e18
        });

        _removeLiquidity({
            from:     _lender,
            amount:   22_000 * 1e18,
            index:    _i9_52,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 21_999.966789626828026872 * 1e18
        });

        _assertBucket({
            index:        _i9_52,
            lpBalance:    8_000.033210373171973128 * 1e18,
            collateral:   0,          
            deposit:      8_000.045286940870700000 * 1e18,
            exchangeRate: 1.000001509564695691 * 1e18
        });

        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:  _lender,
            index: _i9_52
        });

        skip(25 hours);

        _assertPool(
            PoolParams({
                htp:                  7.989580407145861718 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_000.423014969290972838 * 1e18,
                pledgedCollateral:    1_001.371773711622291235 * 1e18,
                encumberedCollateral: 838.521600516187410670 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.121389232097000537 * 1e18,
                targetUtilization:    0.822758145478171949 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 28 hours
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_990.503913730158190391 * 1e18,
            borrowerCollateral:        1_000.00 * 1e18,
            borrowert0Np:              9.200228999102245332 * 1e18,
            borrowerCollateralization: 1.192575121957988603 * 1e18
        });

        // trigger accrual of pool interest that will push the lup back up
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  7.990503913730158191 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_001.213844211612533894 * 1e18,
                pledgedCollateral:    1_001.371773711622291235 * 1e18,
                encumberedCollateral: 838.521600516187410670 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.383637856267925676 * 1e18,
                targetUtilization:    0.829403289225492236 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.03645 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        skip(117 days);

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_084.412285638162564830 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.200228999102245332 * 1e18,
            borrowerCollateralization: 0.000000012349231999 * 1e18
        });

        // kick borrower 2
        changePrank(_lender);
        _pool.lenderKick(_i9_52, MAX_FENWICK_INDEX);

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             8_083.134377459926771461 * 1e18,
                pledgedCollateral:    1_001.371773711622291235 * 1e18,
                encumberedCollateral: 80_976_695_562.129442225570824234 * 1e18,
                poolDebt:             8_084.412285638162564830 * 1e18,
                actualUtilization:    0.998661461786925952 * 1e18,
                targetUtilization:    0.838521600515840801 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.040095 * 1e18,
                interestRateUpdate:   block.timestamp
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
                bondSize:          122.724126286659537773 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    9.311653548504757974 * 1e18,
                totalBondEscrowed: 122.724126286659537773 * 1e18,
                auctionPrice:      2.327913387126189492 * 1e18,
                debtInAuction:     8_084.412285638162564830 * 1e18,
                thresholdPrice:    8.084782322086612071 * 1e18,
                neutralPrice:      9.311653548504757974 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_084.782322086612071679 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.200228999102245332 * 1e18,
            borrowerCollateralization: 0.000000012348666781 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000.0 * 1e18,
            bondChange:      35.338516445234474376 * 1e18,
            givenAmount:     2_327.913387126189492000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_083.498296802166583218 * 1e18,
                pledgedCollateral:    1.371773711622291235 * 1e18,
                encumberedCollateral: 607.832887025912931068 * 1e18,
                poolDebt:             5_792.207451405657054680 * 1e18,
                actualUtilization:    0.998661461786925952 * 1e18,
                targetUtilization:    0.838521600515840801 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.040095 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_792.207451405657054680 * 1e18,
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
            settledDebt: 5_722.635152359337569948 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             2_312.355002439841726602 * 1e18,
                pledgedCollateral:    1.371773711622291235 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.998661461786925952 * 1e18,
                targetUtilization:    0.838521600515840801 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.040095 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
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
            index:        _i9_62,
            lpBalance:    0,
            collateral:   0,          
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_52,
            lpBalance:    8_000.033210373171973128 * 1e18,
            collateral:   0,          
            deposit:      2_312.355002439841725846 * 1e18,
            exchangeRate: 0.289043175401015481 * 1e18
        });
    }
 }
