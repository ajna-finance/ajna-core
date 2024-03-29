// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsLenderKickAuctionTest is ERC20HelperContract {

    address internal _borrower1;
    address internal _borrower2;
    address internal _borrower3;
    address internal _borrower4;
    address internal _borrower5;
    address internal _lender1;
    address internal _lender2;
    address internal _lender3;
    address internal _lender4;

    function setUp() external {
        _startTest();

        _borrower1 = makeAddr("borrower1");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _borrower4 = makeAddr("borrower4");
        _borrower5 = makeAddr("borrower5");
        _lender1   = makeAddr("lender1");
        _lender2   = makeAddr("lender2");
        _lender3   = makeAddr("lender3");
        _lender4   = makeAddr("lender4");

        _mintQuoteAndApproveTokens(_lender1, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender2, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender3, 150_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender4, 5_000 * 1e18);

        _mintCollateralAndApproveTokens(_lender1,   1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender3,   1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower1, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower3, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower4, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower5, 1_000 * 1e18);

        // Lender 1 adds Quote token accross 2 buckets
        _addInitialLiquidity({
            from:   _lender1,
            amount: 50_000 * 1e18,
            index:  2500
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 50_000 * 1e18,
            index:  2501
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 1_000 * 1e18,
            index:  2502
        });

        // all 5 borrowers draw debt from pool
        _drawDebt({
            from:               _borrower1,
            borrower:           _borrower1,
            amountToBorrow:     20_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower2,
            borrower:           _borrower2,
            amountToBorrow:     20_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_863.654368867279344664 * 1e18
        });
        _drawDebt({
            from:               _borrower3,
            borrower:           _borrower3,
            amountToBorrow:     20_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_844.432207828138682757 * 1e18
        });
        _drawDebt({
            from:               _borrower4,
            borrower:           _borrower4,
            amountToBorrow:     20_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_844.432207828138682757 * 1e18
        });
        _drawDebt({
            from:               _borrower5,
            borrower:           _borrower5,
            amountToBorrow:     20_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 1_000 * 1e18,
            newLup:             3_825.305679430983794766 * 1e18
        });

        // Lender 2 adds Quote token to top bucket
        _addLiquidity({
            from:    _lender2,
            amount:  10_000 * 1e18,
            index:   2500,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  3_844.432207828138682757 * 1e18
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  20.820000000000000010 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             110_994.931506849315069 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 27.078120869976251528 * 1e18,
                poolDebt:             100_096.153846153846200000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_001.923076923076924000 * 1e18,
                loans:                5,
                maxBorrower:          address(_borrower1),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 11_000 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // assert lender cannot remove desired amount of 15000 quote tokens as LUP moves below HTP
        _assertRemoveLiquidityLupBelowHtpRevert({
            from:   _lender1,
            amount: 15_000 * 1e18,
            index:  2500
        });
    }
    
    function testLenderKickAuctionAmountHigherThanAuctionBond() external tearDown {

        /**
            - kick with deposit amount lower than deposit available (lender can redeem less LP from bucket than deposit)
            - auction bond is covered entirely from lender deposit (bucket still contains LP)
         */

        // assert bucket state pre kick with deposit
        _assertBucket({
            index:        2500,
            lpBalance:    59_997.26027397260274 * 1e18,
            collateral:   0,
            deposit:      59_997.26027397260274 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // should revert if NP goes below limit
        _assertLenderKickAuctionNpUnderLimitRevert({
            from:  _lender1,
            index: 2500
        });

        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower1,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.820000000000000010 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             110_994.931506849315069 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 27.078120869976251528 * 1e18,
                poolDebt:             100_096.153846153846200000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_502.403846153846155000 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // assert balances - no change, bond was covered from deposit
        assertEq(_quote.balanceOf(address(_pool)), 11_223.821804286277016796 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       48_776.178195713722983204 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // assert lenders LP in bucket used to kick
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       2500,
            lpBalance:   49_997.71689497716895 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       2500,
            lpBalance:   9_999.54337899543379 * 1e18,
            depositTime: _startTime
        });
        // assert bucket LP
        _assertBucket({
            index:        2500,
            lpBalance:    59_997.26027397260274 * 1e18,
            collateral:   0,
            deposit:      59_997.26027397260274 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // assert lender1 as a kicker
        _assertKicker({
            kicker:    _lender1,
            claimable: 0,
            locked:    223.821804286277016796 * 1e18
        });
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 223.821804286277016796 * 1e18,
                auctionPrice:      5_925.823171731783953152 * 1e18,
                debtInAuction:     20_019.230769230769240000 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

    }

    function testLenderKickAuctionAmountLowerThanAuctionBond() external tearDown {
        /**
            - kick with deposit amount lower than deposit available (lender can redeem less LP from bucket than deposit)
            - bond auction is not covered entirely by removed deposit (bucket still contains LP), difference to cover bond is sent by lender
         */

        // borrower 1 draws more debt from pool, bond size will increase from 303.8987273632000937560 in prev scenario to 324.541616215101674353 * 1e18
        _drawDebt({
            from:               _borrower1,
            borrower:           _borrower1,
            amountToBorrow:     9_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 0,
            newLup:             3_844.432207828138682757 * 1e18
        });

        // Lender 3 adds collateral to top bucket
        _addCollateral({
            from:    _lender3,
            amount:  1 * 1e18,
            index:   2500,
            lpAward: 3_863.654368867279344664 * 1e18 // less than bond size
        });

        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 2_000 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_lender3),       150_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     29_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);


        // should revert if NP goes below limit
        _assertLenderKickAuctionNpUnderLimitRevert({
            from:  _lender3,
            index: 2500
        });

        _lenderKick({
            from:       _lender3,
            index:      2500,
            borrower:   _borrower1,
            debt:       29_027.884615384615398000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       324.541616215101674353 * 1e18
        });

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.820000000000000010 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             110_994.931506849315069 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 29.515151748274114165 * 1e18,
                poolDebt:             109_104.807692307692358000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_727.620192307692308950 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 2_324.541616215101674353 * 1e18);   // increased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_lender3),       149_675.458383784898325647 * 1e18); // decreased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_borrower1),     29_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // assert lenders LP in bucket used
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       2500,
            lpBalance:   49_997.71689497716895 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender3,
            index:       2500,
            lpBalance:   3_863.654368867279344664 * 1e18,
            depositTime: _startTime
        });
        // assert bucket LP
        _assertBucket({
            index:        2500,
            lpBalance:    63_860.914642839882084664 * 1e18,
            collateral:   1 * 1e18,
            deposit:      59_997.26027397260274 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // assert lender3 as a kicker
        _assertKicker({
            kicker:    _lender3,
            claimable: 0,
            locked:    324.541616215101674353 * 1e18
        });
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender3,
                bondSize:          324.541616215101674353 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    33.564232808637057547 * 1e18,
                totalBondEscrowed: 324.541616215101674353 * 1e18,
                auctionPrice:      8_592.443599011086732032 * 1e18,
                debtInAuction:     29_027.884615384615398000 * 1e18,
                debtToCollateral:  29.027884615384615398 * 1e18,
                neutralPrice:      33.564232808637057547 * 1e18
            })
        );
    }

    function testLenderKickAuctionUsingAllLpsWithinBucket() external tearDown {
        /**
            - kick using entire deposit / LP from bucket
            - bond auction is not covered entirely by deposit, deposit is obliterated and difference to cover bond is sent by lender
         */

        // lender 2 adds liquidity in new top bucket 2499
        _addLiquidity({
            from:    _lender2,
            amount:  10_000 * 1e18,
            index:   2499,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  3_844.432207828138682757 * 1e18
        });

        // borrower draws more debt consuming entire deposit from bucket 2499
        _drawDebt({
            from:               _borrower1,
            borrower:           _borrower1,
            amountToBorrow:     15_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 0,
            newLup:             3_844.432207828138682757 * 1e18
        });

        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       130_000 * 1e18);
        assertEq(_quote.balanceOf(_lender3),       150_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     35_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // should revert if NP goes below limit
        _assertLenderKickAuctionNpUnderLimitRevert({
            from:  _lender2,
            index: 2500
        });

        // lender 2 kicks using bucket 2499
        _lenderKick({
            from:       _lender2,
            index:      2499,
            borrower:   _borrower1,
            debt:       35_033.653846153846170000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       391.688157500984779392 * 1e18
        });

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.820000000000000010 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             120_994.474885844748859 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 31.139839000472689257 * 1e18,
                poolDebt:             115_110.576923076923130000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_877.764423076923078250 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 6_391.688157500984779392 * 1e18);   // increased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       129_608.311842499015220608 * 1e18); // decreased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender3),       150_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     35_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // assert lenders LP in bucket used
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       2499,
            lpBalance:   9_999.54337899543379 * 1e18,
            depositTime: _startTime
        });
        // assert bucket - LP and deposit obliterated
        _assertBucket({
            index:        2499,
            lpBalance:    9_999.54337899543379 * 1e18,
            collateral:   0,
            deposit:      9_999.54337899543379 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // assert lender2 as a kicker
        _assertKicker({
            kicker:    _lender2,
            claimable: 0,
            locked:    391.688157500984779392 * 1e18
        });
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender2,
                bondSize:          391.688157500984779392 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    40.508556838010241868 * 1e18,
                totalBondEscrowed: 391.688157500984779392 * 1e18,
                auctionPrice:      10_370.190550530621918208 * 1e18,
                debtInAuction:     35_033.653846153846170000 * 1e18,
                debtToCollateral:  35.033653846153846170 * 1e18,
                neutralPrice:      40.508556838010241868 * 1e18
            })
        );
    }

    function testLenderKickAuctionAmountHigherThanAvailableDeposit() external tearDown {

        /**
            - kick with deposit amount higher than deposit available (lender can redeem more LP from bucket than deposit)
            - auction bond is covered entirely from lender deposit
         */

        // lender1 adds collateral to bucket to be entitled to higher deposit than available
        _addCollateral({
            from:    _lender1,
            amount:  10 * 1e18,
            index:   2500,
            lpAward: 38_636.54368867279344664 * 1e18
        });

        // assert lender and bucket LP balances pre kick
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       2500,
            lpBalance:   88_634.26058364996239664 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2500,
            lpBalance:    98_633.80396264539618664 * 1e18,
            collateral:   10 * 1e18,
            deposit:      59_997.26027397260274 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // should revert if NP goes below limit
        _assertLenderKickAuctionNpUnderLimitRevert({
            from:  _lender1,
            index: 2500
        });

        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower1,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.820000000000000010 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             110_994.931506849315069 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 27.078120869976251528 * 1e18,
                poolDebt:             100_096.153846153846200000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_502.403846153846155000 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // assert balances - no change, bond was covered from deposit
        assertEq(_quote.balanceOf(address(_pool)), 11_223.821804286277016796 * 1e18); // increased by amount used to cover auction bond
        assertEq(_quote.balanceOf(_lender1),       48_776.178195713722983204 * 1e18); // reduced by amount used to cover auction bond
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);

        // assert lenders LP in bucket used
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       2500,
            lpBalance:   88_634.260583649962396640 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       2500,
            lpBalance:   9_999.54337899543379 * 1e18,
            depositTime: _startTime
        });
        // assert bucket LP
        _assertBucket({
            index:        2500,
            lpBalance:    98_633.803962645396186640 * 1e18,
            collateral:   10 * 1e18,
            deposit:      59_997.26027397260274 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // assert lender1 as a kicker
        _assertKicker({
            kicker:    _lender1,
            claimable: 0,
            locked:    223.821804286277016796 * 1e18
        });
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 223.821804286277016796 * 1e18,
                auctionPrice:      5_925.823171731783953152 * 1e18,
                debtInAuction:     20_019.230769230769240000 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

    }

    function testLenderKickAuctionAllBorrowersAndSettle() external tearDown {
        // assert loans positions in heap
        address borrower;
        uint256 t0DebtToCollateral;
        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, _borrower1);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, _borrower4);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, _borrower5);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);

        // kick borrower 1
        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower1,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, _borrower5);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, _borrower4);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);

        address head;
        address next;
        address prev;
        (, , , , , , , head, next, prev) = _pool.auctionInfo(address(0));
        assertEq(head, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // kick borrower 5
        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower5,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, _borrower4);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower1);

        // kick borrower 4
        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower4,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, _borrower3);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);

        // kick borrower 3
        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower3,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, _borrower2);
        assertEq(t0DebtToCollateral, 20.019230769230769240 * 1e18);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower4);

        // kick borrower 2
        _lenderKick({
            from:       _lender1,
            index:      2500,
            borrower:   _borrower2,
            debt:       20_019.230769230769240000 * 1e18,
            collateral: 1_000 * 1e18,
            bond:       223.821804286277016796 * 1e18
        });

        (borrower, t0DebtToCollateral) = _pool.loanInfo(1);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(2);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);
        (borrower, t0DebtToCollateral) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(t0DebtToCollateral, 0);

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, _borrower2);
        assertEq(prev, _borrower4);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower3);

        // assert pool after kicking all borrowers
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             110_994.931506849315069 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 27.078120869976251528 * 1e18,
                poolDebt:             100_096.153846153846200000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // skip to make loans clearable
        skip(80 hours);

        // settle borrower 2
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     100_096.153846153846200000 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

        _settle({
            from:        _lender1,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 20_028.374057845207515293 * 1e18
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
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     80_113.496231380830061171 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower4);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 4
        _assertAuction(
            AuctionParams({
                borrower:          _borrower4,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     80_113.496231380830061171 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

        _settle({
            from:        _lender1,
            borrower:    _borrower4,
            maxDepth:    5,
            settledDebt: 20_028.374057845207515293 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower4,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     60_085.122173535622545879 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower1);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 1
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     60_085.122173535622545879 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

        _settle({
            from:        _lender1,
            borrower:    _borrower1,
            maxDepth:    5,
            settledDebt: 20_028.374057845207515293 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     40_056.748115690415030586 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower5);
        assertEq(next, _borrower3);
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 5
        _assertAuction(
            AuctionParams({
                borrower:          _borrower5,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     40_056.748115690415030586 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

        _settle({
            from:        _lender1,
            borrower:    _borrower5,
            maxDepth:    5,
            settledDebt: 20_028.374057845207515293 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower5,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     20_028.374057845207515293 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 3
        _assertAuction(
            AuctionParams({
                borrower:          _borrower3,
                active:            true,
                kicker:            _lender1,
                bondSize:          223.821804286277016796 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    23.147746764577281067 * 1e18,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     20_028.374057845207515293 * 1e18,
                debtToCollateral:  20.019230769230769240 * 1e18,
                neutralPrice:      23.147746764577281067 * 1e18
            })
        );

        _settle({
            from:        _lender1,
            borrower:    _borrower3,
            maxDepth:    5,
            settledDebt: 20_028.374057845207515293 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower3,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 1_119.109021431385083980 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // assert pool after settle
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             10_891.920194234640150529 * 1e18,
                pledgedCollateral:    4_974.029124053231774906 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 80 hours
            })
        );
        // assert lender1 after settle
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       2500,
            lpBalance:   49_997.716894977168950000 * 1e18,
            depositTime: _startTime
        });
        // assert lender1 as a kicker
        _assertKicker({
            kicker:    _lender1,
            claimable: 1_119.109021431385083980 * 1e18,
            locked:    0
        });
        // assert borrowers after settle
        _assertBorrower({
            borrower:                  _borrower1,
            borrowerDebt:              0,
            borrowerCollateral:        994.816123174870376622 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        994.816209695351969626 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower3,
            borrowerDebt:              0,
            borrowerCollateral:        994.790290743828729516 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower4,
            borrowerDebt:              0,
            borrowerCollateral:        994.816209695351969626 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower5,
            borrowerDebt:              0,
            borrowerCollateral:        994.790290743828729516 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testLenderKickAuctionReverts() external tearDown {
        // assert lender cannot kick with a bucket without deposit
        _assertKickWithInsufficientLiquidityRevert({
            from:   _lender3,
            index:  2_500
        });

        // assert lender cannot kick a loan if the proposed LUP doesn't render borrower uncollateralized
        _assertKickWithBadProposedLupRevert({
            from:   _lender2,
            index:  2_500
        });

        // Lender 2 adds Quote token at a much lower price the tries to kick with deposit
        _addLiquidityWithPenalty({
            from:        _lender3,
            amount:      150_000 * 1e18,
            amountAdded: 149_993.150684931506850000 * 1e18,
            index:       7000,
            lpAward:     149_993.150684931506850000 * 1e18,
            newLup:      3_844.432207828138682757 * 1e18
        });

        _assertKickPriceBelowLupRevert({
            from:   _lender3,
            index:  7000
        });

        // asert failure when lender has LP but insufficient quote token balance to post remaining bond
        _addLiquidity({
            from:    _lender4,
            amount:  5_000 * 1e18,
            index:   2499,
            lpAward: 4_999.771689497716895000 * 1e18,
            newLup:  3_844.432207828138682757 * 1e18
        });

        // borrower draws more debt consuming entire deposit from bucket 2499
        _drawDebt({
            from:               _borrower1,
            borrower:           _borrower1,
            amountToBorrow:     15_000 * 1e18,
            limitIndex:         5000,
            collateralToPledge: 0,
            newLup:             3_825.305679430983794766 * 1e18
        });

        changePrank(_lender4);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        _pool.lenderKick(2499, MAX_FENWICK_INDEX);
    }
}
