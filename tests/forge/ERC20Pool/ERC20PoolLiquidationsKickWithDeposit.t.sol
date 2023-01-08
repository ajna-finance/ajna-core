// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsKickWithDepositTest is ERC20HelperContract {

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
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 50_000 * 1e18,
                index:  2500
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 50_000 * 1e18,
                index:  2501
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 1_000 * 1e18,
                index:  2502
            }
        );

        // all 5 borrowers draw debt from pool
        _drawDebt(
            {
                from:               _borrower1,
                borrower:           _borrower1,
                amountToBorrow:     20_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 1_000 * 1e18,
                newLup:             3_863.654368867279344664 * 1e18
            }
        );
        _drawDebt(
            {
                from:               _borrower2,
                borrower:           _borrower2,
                amountToBorrow:     20_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 1_000 * 1e18,
                newLup:             3_863.654368867279344664 * 1e18
            }
        );
        _drawDebt(
            {
                from:               _borrower3,
                borrower:           _borrower3,
                amountToBorrow:     20_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 1_000 * 1e18,
                newLup:             3_844.432207828138682757 * 1e18
            }
        );
        _drawDebt(
            {
                from:               _borrower4,
                borrower:           _borrower4,
                amountToBorrow:     20_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 1_000 * 1e18,
                newLup:             3_844.432207828138682757 * 1e18
            }
        );
        _drawDebt(
            {
                from:               _borrower5,
                borrower:           _borrower5,
                amountToBorrow:     20_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 1_000 * 1e18,
                newLup:             3_825.305679430983794766 * 1e18
            }
        );

        // Lender 2 adds Quote token to top bucket
        _addLiquidity(
            {
                from:    _lender2,
                amount:  10_000 * 1e18,
                index:   2500,
                lpAward: 10_000 * 1e27,
                newLup:  3_844.432207828138682757 * 1e18
            }
        );

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             111_000 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 26.036654682669472623 * 1e18,
                poolDebt:             100_096.153846153846200000 * 1e18,
                actualUtilization:    0.901767151767151768 * 1e18,
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
        _assertRemoveLiquidityLupBelowHtpRevert(
            {
                from:   _lender1,
                amount: 15_000 * 1e18,
                index:  2500
            }
        );
    }
    
    function testKickWithDepositAmountHigherThanAuctionBond() external tearDown {

        /**
            - kick with deposit amount lower than deposit available (lender can redeem less LPs from bucket than deposit)
            - auction bond is covered entirely from lender deposit (bucket still contains LPs)
         */

        // assert bucket state pre kick with deposit
        _assertBucket(
            {
                index:        2500,
                lpBalance:    60_000 * 1e27,
                collateral:   0,
                deposit:      60_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower1,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                3_844.432207828138682757 * 1e18
            }
        );

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             104_994.230769230769228000 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 26.101746319376146305 * 1e18,
                poolDebt:             100_346.394230769230815500 * 1e18,
                actualUtilization:    0.955732457827353152 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_508.659855769230770388 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        // assert balances - no change, bond was covered from deposit
        assertEq(_quote.balanceOf(address(_pool)), 11_000 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);
        // assert lenders LPs in bucket used
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2500,
                lpBalance:   43_994.230769230769228 * 1e27, // reduced by amount used to cover auction bond
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       2500,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        // assert bucket LPs
        _assertBucket(
            {
                index:        2500,
                lpBalance:    53_994.230769230769228 * 1e27,    // reduced by amount used to cover auction bond
                collateral:   0,
                deposit:      53_994.230769230769228000 * 1e18, // reduced by amount used to cover auction bond
                exchangeRate: 1 * 1e27
            }
        );
        // assert lender1 as a kicker
        _assertKicker(
            {
                kicker:    _lender1,
                claimable: 0,
                locked:    6_005.769230769230772000 * 1e18
            }
        );
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 6_005.769230769230772000 * 1e18,
                auctionPrice:      123_636.939803752939029248 * 1e18,
                debtInAuction:     20_269.471153846153855500 * 1e18,
                thresholdPrice:    20.269471153846153855 * 1e18,
                neutralPrice:      21.020192307692307702 * 1e18
            })
        );

    }

    function testKickWithDepositAmountLowerThanAuctionBond() external tearDown {
        /**
            - kick with deposit amount lower than deposit available (lender can redeem less LPs from bucket than deposit)
            - bond auction is not covered entirely by removed deposit (bucket still contains LPs), difference to cover bond is sent by lender
         */

        // borrower 1 draws more debt from pool, bond size will increase from 6_005.769230769230772000 in prev scenario to 8_708.365384615384619400
        _drawDebt(
            {
                from:               _borrower1,
                borrower:           _borrower1,
                amountToBorrow:     9_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 0,
                newLup:             3_844.432207828138682757 * 1e18
            }
        );

        // Lender 3 adds collateral to top bucket
        _addCollateral(
            {
                from:    _lender3,
                amount:  1 * 1e18,
                index:   2500,
                lpAward: 3_863.654368867279344664 * 1e27 // less than bond size
            }
        );
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

        _kickWithDeposit(
            {
                from:               _lender3,
                index:              2500,
                borrower:           _borrower1,
                debt:               29_390.733173076923090475 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               8_708.365384615384619400 * 1e18,
                removedFromDeposit: 3_863.654368867279344664 * 1e18,
                transferAmount:     4_844.711015748105274736 * 1e18,
                lup:                99836282890
            }
        );

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  99836282890,
                poolSize:             107_136.345631132720655336 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 1096471674237.029479718793645083 * 1e18,
                poolDebt:             109_467.656250000000050475 * 1e18,
                actualUtilization:    1.021760221567514661 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_736.691406250000001262 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 6_844.711015748105274736 * 1e18);   // increased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_lender3),       145_155.288984251894725264 * 1e18); // decreased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_borrower1),     29_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);
        // assert lenders LPs in bucket used
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2500,
                lpBalance:   50_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender3,
                index:       2500,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        // assert bucket LPs
        _assertBucket(
            {
                index:        2500,
                lpBalance:    60_000 * 1e27,
                collateral:   1 * 1e18,
                deposit:      56_136.345631132720655336 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        // assert lender3 as a kicker
        _assertKicker(
            {
                kicker:    _lender3,
                claimable: 0,
                locked:    8_708.365384615384619400 * 1e18
            }
        );
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender3,
                bondSize:          8_708.365384615384619400 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 8_708.365384615384619400 * 1e18,
                auctionPrice:      123_636.939803752939029248 * 1e18,
                debtInAuction:     29_390.733173076923090475 * 1e18,
                thresholdPrice:    29.390733173076923090 * 1e18,
                neutralPrice:      30.631675240384615148 * 1e18
            })
        );
    }

    function testKickWithDepositUsingAllLpsWithinBucket() external tearDown {
        /**
            - kick using entire deposit / LPs from bucket
            - bond auction is not covered entirely by deposit, deposit is obliterated and difference to cover bond is sent by lender
         */

        // lender 2 adds liquidity in new top bucket 2499
        _addLiquidity(
            {
                from:    _lender2,
                amount:  10_000 * 1e18,
                index:   2499,
                lpAward: 10_000 * 1e27,
                newLup:  3_844.432207828138682757 * 1e18
            }
        );
        // borrower draws more debt consuming entire deposit from bucket 2499
        _drawDebt(
            {
                from:               _borrower1,
                borrower:           _borrower1,
                amountToBorrow:     15_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 0,
                newLup:             3_844.432207828138682757 * 1e18
            }
        );

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

        // lender 2 kicks using all LPs from bucket 2499 (10_000) and sending additional quote tokens to cover auction bond (510.096153846153851000)
        _kickWithDeposit(
            {
                from:               _lender2,
                index:              2499,
                borrower:           _borrower1,
                debt:               35_471.574519230769247125 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               10_510.096153846153851000 * 1e18,
                removedFromDeposit: 10_000 * 1e18,
                transferAmount:     510.096153846153851000 * 1e18,
                lup:                99836282890
            }
        );

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  99836282890,
                poolSize:             111_000 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 1157379804729.565349777467060503 * 1e18,
                poolDebt:             115_548.497596153846207125 * 1e18,
                actualUtilization:    1.040977455821205822 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_888.712439903846155178 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        // assert balances
        assertEq(_quote.balanceOf(address(_pool)), 6_510.096153846153851000 * 1e18);   // increased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       129_489.903846153846149000 * 1e18); // decreased with the amount sent to cover bond
        assertEq(_quote.balanceOf(_lender3),       150_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     35_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);
        // assert lenders LPs in bucket used
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       2499,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        // assert bucket - LPs and deposit obliterated
        _assertBucket(
            {
                index:        2499,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        // assert lender2 as a kicker
        _assertKicker(
            {
                kicker:    _lender2,
                claimable: 0,
                locked:    10_510.096153846153851000 * 1e18
            }
        );
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender2,
                bondSize:          10_510.096153846153851000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 10_510.096153846153851000 * 1e18,
                auctionPrice:      123_636.939803752939029248 * 1e18,
                debtInAuction:     35_471.574519230769247125 * 1e18,
                thresholdPrice:    35.471574519230769247 * 1e18,
                neutralPrice:      37.154109537259614798 * 1e18
            })
        );
    }

    function testKickWithDepositAmountHigherThanAvailableDeposit() external tearDown {

        /**
            - kick with deposit amount higher than deposit available (lender can redeem more LPs from bucket than deposit)
            - auction bond is covered entirely from lender deposit
         */

        // lender1 adds collateral to bucket to be entitled to higher deposit than available
        _addCollateral(
            {
                from:    _lender1,
                amount:  10 * 1e18,
                index:   2500,
                lpAward: 38636.54368867279344664 * 1e27
            }
        );
        // assert lender and bucket LP balances pre kick
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2500,
                lpBalance:   88_636.54368867279344664 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        2500,
                lpBalance:    98_636.54368867279344664 * 1e27,
                collateral:   10 * 1e18,
                deposit:      60_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower1,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                3_844.432207828138682757 * 1e18
            }
        );

        /******************************/
        /*** Assert post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  20.019230769230769240 * 1e18,
                lup:                  3_844.432207828138682757 * 1e18,
                poolSize:             104_994.230769230769228000 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 26.101746319376146305 * 1e18,
                poolDebt:             100_346.394230769230815500 * 1e18,
                actualUtilization:    0.955732457827353152 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_508.659855769230770388 * 1e18,
                loans:                4,
                maxBorrower:          address(_borrower5),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        // assert balances - no change, bond was covered from deposit
        assertEq(_quote.balanceOf(address(_pool)), 11_000 * 1e18);
        assertEq(_quote.balanceOf(_lender1),       49_000 * 1e18);
        assertEq(_quote.balanceOf(_lender2),       140_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower1),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower3),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower4),     20_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower5),     20_000 * 1e18);
        // assert lenders LPs in bucket used
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2500,
                lpBalance:   82_630.77445790356267464 * 1e27, // reduced by amount used to cover auction bond
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       2500,
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        // assert bucket LPs
        _assertBucket(
            {
                index:        2500,
                lpBalance:    92_630.77445790356267464 * 1e27,  // reduced by amount used to cover auction bond
                collateral:   10 * 1e18,
                deposit:      53_994.230769230769228000 * 1e18, // reduced by amount used to cover auction bond
                exchangeRate: 1 * 1e27
            }
        );
        // assert lender1 as a kicker
        _assertKicker(
            {
                kicker:    _lender1,
                claimable: 0,
                locked:    6_005.769230769230772000 * 1e18
            }
        );
        // assert kicked auction
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 6_005.769230769230772000 * 1e18,
                auctionPrice:      123_636.939803752939029248 * 1e18,
                debtInAuction:     20_269.471153846153855500 * 1e18,
                thresholdPrice:    20.269471153846153855 * 1e18,
                neutralPrice:      21.020192307692307702 * 1e18
            })
        );

    }

    function testKickWithDepositAllBorrowersAndSettle() external tearDown {
        // assert loans positions in heap
        address borrower;
        uint256 thresholdPrice;
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, _borrower1);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, _borrower4);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, _borrower5);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);

        // kick borrower 1
        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower1,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                3_844.432207828138682757 * 1e18
            }
        );
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, _borrower5);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, _borrower4);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);

        address head;
        address next;
        address prev;
        (, , , , , , head, next, prev) = _pool.auctionInfo(address(0));
        assertEq(head, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // kick borrower 5
        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower5,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                99836282890
            }
        );
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, _borrower4);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, _borrower3);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);

        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower1);

        // kick borrower 4
        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower4,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                99836282890
            }
        );
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, _borrower3);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, _borrower2);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);

        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);

        // kick borrower 3
        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower3,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                99836282890
            }
        );
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, _borrower2);
        assertEq(thresholdPrice, 20.019230769230769240 * 1e18);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);

        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower4);

        // kick borrower 2
        _kickWithDeposit(
            {
                from:               _lender1,
                index:              2500,
                borrower:           _borrower2,
                debt:               20_269.471153846153855500 * 1e18,
                collateral:         1_000 * 1e18,
                bond:               6_005.769230769230772000 * 1e18,
                removedFromDeposit: 6_005.769230769230772000 * 1e18,
                transferAmount:     0,
                lup:                99836282890
            }
        );
        (borrower, thresholdPrice) = _pool.loanInfo(1);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(2);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(3);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(4);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);
        (borrower, thresholdPrice) = _pool.loanInfo(5);
        assertEq(borrower, address(0));
        assertEq(thresholdPrice, 0);

        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, _borrower2);
        assertEq(prev, _borrower4);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower3);

        // assert pool after kicking all borrowers
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  99836282890,
                poolSize:             80_971.153846153846140000 * 1e18,
                pledgedCollateral:    5_000 * 1e18,
                encumberedCollateral: 1015135508208.931167644556923668 * 1e18,
                poolDebt:             101_347.355769230769277500 * 1e18,
                actualUtilization:    1.251647666547915925 * 1e18,
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
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 30_028.846153846153860000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     101_347.355769230769277500 * 1e18,
                thresholdPrice:    20.278728733568272609 * 1e18,
                neutralPrice:      21.020192307692307702 * 1e18
            })
        );
        _settle(
            {
                from:        _lender1,
                borrower:    _borrower2,
                maxDepth:    1,
                settledDebt: 20_269.471153846153855500 * 1e18
            }
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
                totalBondEscrowed: 24_023.076923076923088000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     81_114.914934273090436935 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower4);
        assertEq(prev, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower5);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower4);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 4
        _assertAuction(
            AuctionParams({
                borrower:          _borrower4,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 24_023.076923076923088000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     81_114.914934273090436935 * 1e18,
                thresholdPrice:    20.278728733568272609 * 1e18,
                neutralPrice:      21.125293269230769068 * 1e18
            })
        );
        _settle(
            {
                from:        _lender1,
                borrower:    _borrower4,
                maxDepth:    5,
                settledDebt: 20_269.471153846153855500 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower4,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 18_017.307692307692316000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     60_836.186200704817827702 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower1);
        assertEq(next, _borrower5);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower1);
        assertEq(next, _borrower3);
        assertEq(prev, _borrower1);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower1);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 1
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 18_017.307692307692316000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     60_836.186200704817827702 * 1e18,
                thresholdPrice:    20.278728733568272609 * 1e18,
                neutralPrice:      21.020192307692307702 * 1e18
            })
        );
        _settle(
            {
                from:        _lender1,
                borrower:    _borrower1,
                maxDepth:    5,
                settledDebt: 20_269.471153846153855500 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower1,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 12_011.538461538461544000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     40_557.457467136545218468 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower5);
        assertEq(next, _borrower3);
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, _borrower5);
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower5);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 5
        _assertAuction(
            AuctionParams({
                borrower:          _borrower5,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 12_011.538461538461544000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     40_557.457467136545218468 * 1e18,
                thresholdPrice:    20.278728733568272609 * 1e18,
                neutralPrice:      21.230919735576922742 * 1e18
            })
        );
        _settle(
            {
                from:        _lender1,
                borrower:    _borrower5,
                maxDepth:    5,
                settledDebt: 20_269.471153846153855500 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower5,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 6_005.769230769230772000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     20_278.728733568272609234 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, _borrower3);
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // settle borrower 3
        _assertAuction(
            AuctionParams({
                borrower:          _borrower3,
                active:            true,
                kicker:            _lender1,
                bondSize:          6_005.769230769230772000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 6_005.769230769230772000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     20_278.728733568272609234 * 1e18,
                thresholdPrice:    20.278728733568272609 * 1e18,
                neutralPrice:      21.125293269230769068 * 1e18
            })
        );
        _settle(
            {
                from:        _lender1,
                borrower:    _borrower3,
                maxDepth:    5,
                settledDebt: 20_269.471153846153855500 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower3,
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
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower1);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower5);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower4);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower3);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));
        (, , , , , , head, next, prev) = _pool.auctionInfo(_borrower2);
        assertEq(head, address(0));
        assertEq(next, address(0));
        assertEq(prev, address(0));

        // assert pool after settle
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0,
                pledgedCollateral:    2_984.214316325106204943 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    162666617.400895523288640654 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 80 hours
            })
        );
        // assert lender1 after settle
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       2500,
                lpBalance:   19_971.15384615384614 * 1e27,
                depositTime: _startTime
            }
        );
        // assert lender1 as a kicker
        _assertKicker(
            {
                kicker:    _lender1,
                claimable: 30_028.846153846153860000 * 1e18,
                locked:    0
            }
        );
        // assert borrowers after settle
        _assertBorrower(
            {
                borrower:                  _borrower1,
                borrowerDebt:              0,
                borrowerCollateral:        994.725169378126588636 * 1e18,
                borrowert0Np:              21.020192307692307702 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        994.751412316543869246 * 1e18,
                borrowert0Np:              21.020192307692307702 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower3,
                borrowerDebt:              0,
                borrowerCollateral:        0, // last borrower settled
                borrowert0Np:              21.125293269230769068 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower4,
                borrowerDebt:              0,
                borrowerCollateral:        994.737734630435747061 * 1e18,
                borrowert0Np:              21.125293269230769068 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower5,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              21.230919735576922742 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
    }

    function testKickWithDepositReverts() external tearDown {
        // assert lender cannot kick with a bucket without deposit
        _assertKickWithInsufficientLiquidityRevert(
            {
                from:   _lender1,
                index:  2_503
            }
        );
        // assert lender cannot kick a loan if the proposed LUP doesn't render borrower uncollateralized
        _assertKickWithBadProposedLupRevert(
            {
                from:   _lender2,
                index:  2_500
            }
        );

        // Lender 2 adds Quote token at a much lower price the tries to kick with deposit
        _addLiquidity(
            {
                from:    _lender3,
                amount:  150_000 * 1e18,
                index:   7000,
                lpAward: 150_000 * 1e27,
                newLup:  3_844.432207828138682757 * 1e18
            }
        );
        _assertKickPriceBelowProposedLupRevert(
            {
                from:   _lender3,
                index:  7000
            }
        );

        // asert failure when lender has LPs but insufficient quote token balance to post remaining bond
        _addLiquidity(
            {
                from:    _lender4,
                amount:  5_000 * 1e18,
                index:   2499,
                lpAward: 5_000 * 1e27,
                newLup:  3_844.432207828138682757 * 1e18
            }
        );
        // borrower draws more debt consuming entire deposit from bucket 2499
        _drawDebt(
            {
                from:               _borrower1,
                borrower:           _borrower1,
                amountToBorrow:     15_000 * 1e18,
                limitIndex:         5000,
                collateralToPledge: 0,
                newLup:             3_825.305679430983794766 * 1e18
            }
        );
        changePrank(_lender4);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        _pool.kickWithDeposit(2499);
    }
}