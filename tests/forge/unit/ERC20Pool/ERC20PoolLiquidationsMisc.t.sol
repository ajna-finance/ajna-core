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
            amount:     19.05 * 1e18,
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
                htp:                  9.534158653846153851 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             47_997.808219178082192000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 856.574181632808314357 * 1e18,
                poolDebt:             8_006.741394230769234461 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.337069711538461723 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.068317307692307701 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.600109996759548181 * 1e18,
            borrowerCollateralization: 0.980411613609141180 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 1.170228147822941070 * 1e18
        });
        _assertReserveAuction({
            reserves:                   9.883175052687042461 * 1e18,
            claimableReserves :         9.883127054878823283 * 1e18,
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
            lpRedeem: 1_999.827375411809313515 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   4_999.838207170529534384 * 1e18,
            index:    _i9_81,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 4_999.568438529523283785 * 1e18
        });
        _removeLiquidity({
            from:     _lender,
            amount:   2_990 * 1e18,
            index:    _i9_72,
            newLup:   9.721295865031779605 * 1e18,
            lpRedeem: 2_989.838673132372185520 * 1e18
        });

        // Lender amount to withdraw is restricted by HTP 
        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:     _lender,
            index:    _i9_72
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_009.659043762604983480 * 1e18,
            collateral:   0,
            deposit:      8_010.091232032797917459 * 1e18,
            exchangeRate: 1.000053958385473287 * 1e18
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
                thresholdPrice:    9.536302992275635967 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.072605984551271935 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.600109996759548181 * 1e18,
            borrowerCollateralization: 0.980191157704848339 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.072605984551271935 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.213238217447629730 * 1e18,
            transferAmount: 0.213238217447629730 * 1e18
        });

        _assertBucket({
            index:        _i9_72,
            lpBalance:    8_009.659043762604983480 * 1e18,
            collateral:   0,          
            deposit:      8_010.656438244246273059 * 1e18,
            exchangeRate: 1.000124523962404867 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.213238217447629730 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.602494079513784655 * 1e18,
                totalBondEscrowed: 0.213238217447629730 * 1e18,
                auctionPrice:      2_714.238484355528871680 * 1e18,
                debtInAuction:     19.072605984551271935 * 1e18,
                thresholdPrice:    9.536302992275635967 * 1e18,
                neutralPrice:      10.602494079513784655 * 1e18
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
                bondSize:          0.213238217447629730 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 3 hours,
                referencePrice:    10.602494079513784655 * 1e18,
                totalBondEscrowed: 0.213238217447629730 * 1e18,
                auctionPrice:      29.988381844457677324 * 1e18,
                debtInAuction:     19.072605984551271935 * 1e18,
                thresholdPrice:    9.536435260409064268 * 1e18,
                neutralPrice:      10.602494079513784655 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.072870520818128536 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.600109996759548181 * 1e18,
            borrowerCollateralization: 0.980177562682044505 * 1e18
        });

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2.0 * 1e18,
            bondChange:      0.213238217447629730 * 1e18,
            givenAmount:     19.398188023779325106 * 1e18,
            collateralTaken: 0.646856776880891094 * 1e18,
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
            borrowerCollateral:        1.353143223119108906 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  7.989580407145861718 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             38_009.666725806721180539 * 1e18,
                pledgedCollateral:    1_001.353143223119108906 * 1e18,
                encumberedCollateral: 854.738271398607714479 * 1e18,
                poolDebt:             7_989.580407145861717463 * 1e18,
                actualUtilization:    0.195509176991053034 * 1e18,
                targetUtilization:    0.822077328763715532 * 1e18,
                minDebtAmount:        798.958040714586171746 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 3 hours
            })
        );

        _removeAllLiquidity({
            from:     _lender,
            amount:   8_010.676578662675505263 * 1e18,
            index:    _i9_72,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 8_009.659043762604983480 * 1e18
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
            amount:   22_000 * 1e18,
            index:    _i9_52,
            newLup:   9.529276179422528643 * 1e18,
            lpRedeem: 21_999.944687667628067660 * 1e18
        });

        _assertBucket({
            index:        _i9_52,
            lpBalance:    7_998.685449318673302340 * 1e18,
            collateral:   0,          
            deposit:      7_998.705559639603302741 * 1e18,
            exchangeRate: 1.000002514203247200 * 1e18
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
                poolSize:             7_998.990147144045678219 * 1e18,
                pledgedCollateral:    1_001.353143223119108906 * 1e18,
                encumberedCollateral: 872.062464536834907097 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.195509176991053034 * 1e18,
                targetUtilization:    0.822077328763715532 * 1e18,
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
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 1.146706848036527502 * 1e18
        });

        // trigger accrual of pool interest that will push the lup back up
        _updateInterest();

        _assertPool(
            PoolParams({
                htp:                  7.990503913730158191 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             7_999.784817415678748744 * 1e18,
                pledgedCollateral:    1_001.353143223119108906 * 1e18,
                encumberedCollateral: 872.062464536834907097 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.522552675292960591 * 1e18,
                targetUtilization:    0.829008163836671133 * 1e18,
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
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 0
        });

        // kick borrower 2
        changePrank(_lender);
        _pool.lenderKick(_i9_52, MAX_FENWICK_INDEX);

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             8_082.683609996511125408 * 1e18,
                pledgedCollateral:    1_001.353143223119108906 * 1e18,
                encumberedCollateral: 84_215_763_384.614619914591653924 * 1e18,
                poolDebt:             8_084.412285638162564830 * 1e18,
                actualUtilization:    0.998839855833957451 * 1e18,
                targetUtilization:    0.838521600515825621 * 1e18,
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
                bondSize:          90.386477144106887514 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    8.988277057079231472 * 1e18,
                totalBondEscrowed: 90.386477144106887514 * 1e18,
                auctionPrice:      2.247069264269807868 * 1e18,
                debtInAuction:     8_084.412285638162564830 * 1e18,
                thresholdPrice:    8.084782322086612071 * 1e18,
                neutralPrice:      8.988277057079231472 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_084.782322086612071679 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.880722076025322255 * 1e18,
            borrowerCollateralization: 0
        });

        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000.0 * 1e18,
            bondChange:      25.122998125288647552 * 1e18,
            givenAmount:     2_247.069264269807868000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             8_083.047814146372012112 * 1e18,
                pledgedCollateral:    1.353143223119108906 * 1e18,
                encumberedCollateral: 639.854421613507497993 * 1e18,
                poolDebt:             5_862.836055942092851679 * 1e18,
                actualUtilization:    0.998839855833957451 * 1e18,
                targetUtilization:    0.838521600515825621 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.040095 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_862.836055942092851679 * 1e18,
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
            settledDebt: 5_792.415411176588073422 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             2_224.094938954560914482 * 1e18,
                pledgedCollateral:    1.353143223119108906 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.998839855833957451 * 1e18,
                targetUtilization:    0.838521600515825621 * 1e18,
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
            index:        _i9_52,
            lpBalance:    7_998.685449318673302340 * 1e18,
            collateral:   0,          
            deposit:      2_224.094938954560913750 * 1e18,
            exchangeRate: 0.278057557463271537 * 1e18
        });
    }
 }
