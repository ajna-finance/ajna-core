// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import { ERC20Pool } from 'src/ERC20Pool.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/PoolInfoUtils.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolCollateralTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _bidder;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        _mintCollateralAndApproveTokens(_borrower,  150 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 100 * 1e18);

        _mintQuoteAndApproveTokens(_lender, 200_000 * 1e18);
        _mintQuoteAndApproveTokens(_bidder, 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower test pledgeCollateral, borrow, and pullCollateral.
     */
    function testPledgeAndPullCollateral() external tearDown {
        // lender deposits 10000 Quote into 3 buckets

        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        assertEq(_collateral.balanceOf(_borrower), 150 * 1e18);

        // borrower pledge 100 collateral and get a 21_000 Quote loan
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     21_000 * 1e18,
            indexLimit: 3_000,
            newLup:     2_981.007422784467321543 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  210.201923076923077020 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                poolDebt:             21_020.192307692307702000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_102.019230769230770200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_020.192307692307702000 * 1e18,
            borrowerCollateral:        100 * 1e18,
            borrowert0Np:              220.712019230769230871 * 1e18,
            borrowerCollateralization: 14.181637252165253251 * 1e18
        });

        assertEq(_collateral.balanceOf(_borrower), 50 * 1e18);

        // pass time to allow interest to accrue
        skip(10 days);

        // remove some of the collateral
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 50 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  420.980136462780058369 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_024.492338129690910000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.061038044473493202 * 1e18,
                poolDebt:             21_049.0068231390029184310 * 1e18,
                actualUtilization:    0.700672854184962757 * 1e18,
                targetUtilization:    0.070513720116999886 * 1e18,
                minDebtAmount:        2_104.900682313900291843 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_049.006823139002918431 * 1e18,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              441.424038461538461742 * 1e18,
            borrowerCollateralization: 7.081111825921092812 * 1e18
        });

        assertEq(_collateral.balanceOf(_borrower), 100 * 1e18);

        // remove all of the remaining claimable collateral
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 50 * 1e18 - _encumberance(21_049.006823139002918431 * 1e18, _lup())
        });

        _assertPool(
            PoolParams({
                htp:                  2_981.007422784467321393 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_024.492338129690910000 * 1e18,
                pledgedCollateral:    7.061038044473493202 * 1e18,
                encumberedCollateral: 7.061038044473493202 * 1e18,
                poolDebt:             21_049.0068231390029184310 * 1e18,
                actualUtilization:    0.700672854184962757 * 1e18,
                targetUtilization:    0.070513720116999886 * 1e18,
                minDebtAmount:        2_104.900682313900291843 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_049.006823139002918431 * 1e18,
            borrowerCollateral:        7.061038044473493202 * 1e18,
            borrowert0Np:              3_140.657612229160876676 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        assertEq(_collateral.balanceOf(_borrower), 142.938961955526506798 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower test pledgeCollateral, borrow, pull and transfer collateral to a different recipient.
     */
    function testPledgeAndPullCollateralToDifferentRecipient() external tearDown {
        // lender deposits 10000 Quote into 3 buckets

        address collateralReceiver = makeAddr("receiver");

        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });

        assertEq(_collateral.balanceOf(collateralReceiver), 0);
        assertEq(_collateral.balanceOf(_borrower),          150 * 1e18);

        // borrower pledge 100 collateral and get a 21_000 Quote loan
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     21_000 * 1e18,
            indexLimit: 3_000,
            newLup:     2_981.007422784467321543 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  210.201923076923077020 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                poolDebt:             21_020.192307692307702000 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        2_102.019230769230770200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_020.192307692307702000 * 1e18,
            borrowerCollateral:        100 * 1e18,
            borrowert0Np:              220.712019230769230871 * 1e18,
            borrowerCollateralization: 14.181637252165253251 * 1e18
        });

        assertEq(_collateral.balanceOf(collateralReceiver), 0);
        assertEq(_collateral.balanceOf(_borrower),          50 * 1e18);

        // pass time to allow interest to accrue
        skip(10 days);

        // remove some of the collateral and transfer to recipient
        _repayDebtAndPullToRecipient({
            from:             _borrower,
            borrower:         _borrower,
            recipient:        collateralReceiver,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 50 * 1e18,
            newLup:           2_981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_049.006823139002918431 * 1e18,
            borrowerCollateral:        50 * 1e18,
            borrowert0Np:              441.424038461538461742 * 1e18,
            borrowerCollateralization: 7.081111825921092812 * 1e18
        });

        assertEq(_collateral.balanceOf(collateralReceiver), 50 * 1e18);
        assertEq(_collateral.balanceOf(_borrower),          50 * 1e18);

        // remove all of the remaining claimable collateral
        _repayDebtAndPullToRecipient({
            from:             _borrower,
            borrower:         _borrower,
            recipient:        collateralReceiver,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 50 * 1e18 - _encumberance(21_049.006823139002918431 * 1e18, _lup()),
            newLup:           2_981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21_049.006823139002918431 * 1e18,
            borrowerCollateral:        7.061038044473493202 * 1e18,
            borrowert0Np:              3_140.657612229160876676 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        assertEq(_collateral.balanceOf(collateralReceiver), 92.938961955526506798 * 1e18);
        assertEq(_collateral.balanceOf(_borrower),          50 * 1e18);
    }

    /**
     *  @notice 1 borrower tests reverts in pullCollateral.
     *          Reverts:
     *              Attempts to remove more than available claimable collateral.
     */
    function testPullCollateralRequireEnoughCollateral() external tearDown {
        _assertPullInsufficientCollateralRevert({
            from:   _borrower,
            amount: 100 * 1e18
        });

        // borrower deposits 100 collateral
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });

        // should be able to now remove collateral
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 100 * 1e18
        });
    }

    /**
     *  @notice 1 actor tests addCollateral and removeCollateral.
     */
    function testRemoveCollateral() external tearDown {
        // test setup
        _mintCollateralAndApproveTokens(_bidder,  100 * 1e18);

        // should revert if adding collateral at index 0
        _assertAddCollateralAtIndex0Revert({
            from:   _bidder,
            amount: 4 * 1e18
        });

        // actor deposits collateral into a bucket
        _addCollateral({
            from:    _bidder,
            amount:  4 * 1e18,
            index:   2550,
            lpAward: 12_043.56808879152623138 * 1e18
        });

        // check bucket state and bidder's LP
        _assertBucket({
            index:        2550,
            lpBalance:    12_043.56808879152623138 * 1e18,
            collateral:   4 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2550,
            lpBalance:   12_043.56808879152623138 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_collateral.balanceOf(_bidder),        96 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 4 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws some of their collateral
        _removeCollateral({
            from:     _bidder,
            amount:   1.53 * 1e18,
            index:    2550,
            lpRedeem: 4_606.664793962758783503 * 1e18
        });

        // check bucket state and bidder's LP
        _assertBucket({
            index:        2550,
            lpBalance:    7_436.903294828767447877 * 1e18,
            collateral:   2.47 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2550,
            lpBalance:   7_436.903294828767447877 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_collateral.balanceOf(_bidder),        97.53 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 2.47 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws remainder of their _collateral
        _removeCollateral({
            from:     _bidder,
            amount:   2.47 * 1e18,
            index:    2550,
            lpRedeem: 7_436.903294828767447877 * 1e18
        });

        // check bucket state and bidder's LP
        _assertBucket({
            index:        2550,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2550,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check balances
        assertEq(_collateral.balanceOf(_bidder),        100 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);
    }

    function testRemoveHalfCollateral() external tearDown {
        // test setup
        _mintCollateralAndApproveTokens(_bidder,  1 * 1e18);

        // actor deposits collateral into a bucket
        _addCollateral({
            from:    _bidder,
            amount:  1 * 1e18,
            index:   1530,
            lpAward: 487616.252661175041981841 * 1e18
        });

        _removeCollateral({
            from:     _bidder,
            amount:   0.5 * 1e18,
            index:    1530,
            lpRedeem: 243_808.126330587520990921 * 1e18
        });

        // check bucket state and bidder's LP
        _assertBucket({
            index:        1530,
            lpBalance:    243_808.126330587520990920 * 1e18,
            collateral:   0.5 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       1530,
            lpBalance:   243_808.126330587520990920 * 1e18,
            depositTime: _startTime
        });

        // check balances
        assertEq(_collateral.balanceOf(_bidder),        0.5 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0.5 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws remainder of their _collateral
        _removeAllCollateral({
            from:     _bidder,
            amount:   0.5 * 1e18,
            index:    1530,
            lpRedeem: 243_808.126330587520990920 * 1e18
        });

        // check bucket state and bidder's LP
        _assertBucket({
            index:        1530,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       1530,
            lpBalance:   0,
            depositTime: _startTime
        });

        // check balances
        assertEq(_collateral.balanceOf(_bidder),        1 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);
    }

    function testRemoveCollateralReverts() external tearDown {
        uint256 testIndex = 6348;

        // should revert if no collateral in the bucket
        _assertRemoveInsufficientCollateralRevert({
            from:  _lender,
            amount: 3.50 * 1e18,
            index:  testIndex
        });

        // another actor deposits some collateral
        deal(address(_collateral), _bidder,  100 * 1e18);

        changePrank(_bidder);
        _collateral.approve(address(_pool), 100 * 1e18);

        _addCollateral({
            from:    _bidder,
            amount:  0.65 * 1e18,
            index:   testIndex,
            lpAward: 0.000011611972172012 * 1e18
        });

        // should revert if actor has no LPB in the bucket
        _assertRemoveAllCollateralNoClaimRevert({
            from:  _lender,
            index: testIndex
        });

        // should revert if actor does not have LP
        _assertRemoveAllCollateralNoClaimRevert({
            from:  _lender,
            index: testIndex
        });

        // should revert if expiration passed
        _assertAddCollateralExpiredRevert({
            from:   _lender,
            amount: 0.5 * 1e18,
            index:  testIndex,
            expiry: block.timestamp - 2 minutes
        });
    }

    function testPledgeCollateralFromDifferentActor() external tearDown {
        // check initial pool state
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        assertEq(_collateral.balanceOf(_borrower),  150 * 1e18);
        assertEq(_collateral.balanceOf(_borrower2), 100 * 1e18);

        // borrower deposits 100 collateral
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   100 * 1e18
        });

        // check pool state collateral accounting updated properly
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        assertEq(_collateral.balanceOf(_borrower),  150 * 1e18);
        assertEq(_collateral.balanceOf(_borrower2), 0);
    }

    function testAddRemoveCollateralBucketExchangeRateInvariantDifferentActor() external tearDown {
        _mintCollateralAndApproveTokens(_lender,  50000000000 * 1e18);

        _addInitialLiquidity({
            from:   _bidder,
            amount: 6879,
            index:  2570
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   6879,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    6879,
            collateral:   0,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _addCollateral({
            from:    _lender,
            amount:  3642907759.282013932739218713 * 1e18,
            index:   2570,
            lpAward: 9927093687851.086595628225711617 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   9927093687851.086595628225711617 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   6879,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    9927093687851.086595628225718496 * 1e18,
            collateral:   3642907759.282013932739218713 * 1e18,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _removeAllCollateral({
            from:     _lender,
            amount:   3642907759.282013932739218713 * 1e18,
            index:    2570,
            lpRedeem: 9927093687851.086595628225711617 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0, // LP should get back to same value as before add / remove collateral
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   6879, // LP should get back to same value as before add / remove collateral
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    6879,
            collateral:   0,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });
    }

    function testAddRemoveCollateralBucketExchangeRateInvariantSameActor() external tearDown {
        _mintCollateralAndApproveTokens(_lender,  50000000000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 6879,
            index:  2570
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   6879,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    6879,
            collateral:   0,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _addCollateral({
            from:    _lender,
            amount:  3642907759.282013932739218713 * 1e18,
            index:   2570,
            lpAward: 9927093687851.086595628225711617 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   9927093687851.086595628225718496 * 1e18,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    9927093687851.086595628225718496 * 1e18,
            collateral:   3642907759.282013932739218713 * 1e18,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _removeAllCollateral({
            from:     _lender,
            amount:   3642907759.282013932739218713 * 1e18,
            index:    2570,
            lpRedeem: 9927093687851.086595628225711617 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   6879, // LP should get back to same value as before add / remove collateral
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    6879,
            collateral:   0,
            deposit:      6879,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });
    }

    function testAddRemoveCollateralSmallAmountsBucketExchangeRateInvariantDifferentActor() external tearDown {
        _mintCollateralAndApproveTokens(_lender,  50000000000 * 1e18);

        _addInitialLiquidity({
            from:   _bidder,
            amount: 304,
            index:  2570
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   304,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    304,
            collateral:   0,
            deposit:      304,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _addCollateral({
            from:    _lender,
            amount:  1,
            index:   2570,
            lpAward: 2725
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   2725,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   304,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    3029,
            collateral:   1,
            deposit:      304,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        // lender should not be able to remove any collateral as LP balance is 304 < 2725
        _assertRemoveAllCollateralInsufficientLPRevert({
            from:  _bidder,
            index: 2570
        });

        _removeAllCollateral({
            from:     _lender,
            amount:   1,
            index:    2570,
            lpRedeem: 2725
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   304,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    304,
            collateral:   0,
            deposit:      304,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });
    }

    function testSwapSmallAmountsBucketExchangeRateInvariantDifferentActor() external tearDown {
        _mintCollateralAndApproveTokens(_lender,  50000000000 * 1e18);

        _addInitialLiquidity({
            from:   _bidder,
            amount: 2725,
            index:  2570
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   2725,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    2725,
            collateral:   0,
            deposit:      2725,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        _addCollateral({
            from:    _lender,
            amount:  1,
            index:   2570,
            lpAward: 2725
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   2725,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   2725,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    5450,
            collateral:   1,
            deposit:      2725,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        uint256 snapshot = vm.snapshot();

        // bucket should be cleaned out if collateral swap happens first
        _removeAllCollateral({
            from:     _bidder,
            amount:   1,
            index:    2570,
            lpRedeem: 2725
        });
        _removeAllLiquidity({
            from:     _lender,
            amount:   2725,
            index:    2570,
            newLup:   MAX_PRICE,
            lpRedeem: 2725
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });

        vm.revertTo(snapshot);

        // bucket should be cleaned out if quote token swap happens first
        _removeAllLiquidity({
            from:     _lender,
            amount:   2725,
            index:    2570,
            newLup:   MAX_PRICE,
            lpRedeem: 2725
        });
        _removeAllCollateral({
            from:     _bidder,
            amount:   1,
            index:    2570,
            lpRedeem: 2725
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _bidder,
            index:       2570,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertBucket({
            index:        2570,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18 // exchange rate should not change
        });
    }

    function testAddRemoveCollateralBucketExchangeRateInvariantDifferentActor2() external tearDown {
        _mintCollateralAndApproveTokens(_lender,  1000000000000000000 * 1e18);
        _mintCollateralAndApproveTokens(_bidder,  50000000000 * 1e18);

        _addCollateral({
            from:    _bidder,
            amount:  15200,
            index:   2570,
            lpAward: 41420710
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 2,
            index:  2570
        });
        _addCollateral({
            from:    _lender,
            amount:  883976901103343226.563974622543668416 * 1e18,
            index:   2570,
            lpAward: 2408878317819033617340.926215832879088040 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       2570,
            lpBalance:   2408878317819033617340.926215832879088042 * 1e18,
            depositTime: _startTime
        });

        _removeAllCollateral({
            from:     _lender,
            amount:   883976901103343226.563974622543668416 * 1e18,
            index:    2570,
            lpRedeem: 2408878317819033617340.926215832879088042 * 1e18
        });
        _assertBucket({
            index:        2570,
            lpBalance:    41420710,
            collateral:   15200,
            deposit:      2,
            exchangeRate: 1.000000048285024569 * 1e18
        });

    }

    function testPullBorrowerCollateralLessThanEncumberedCollateral() external {
        address actor = makeAddr("actor");

        _mintCollateralAndApproveTokens(actor, 1000000000 * 1e18);
        _mintQuoteAndApproveTokens(actor, 1000000000000 * 1e18);

        changePrank(actor);
        _pool.addQuoteToken(913597152782868931694946846442, 2572, block.timestamp + 100);
        ERC20Pool(address(_pool)).drawDebt(actor, 456798576391434465847473423221, 7388, 170152459663184217402759609);

        vm.warp(1689742127);
        // borrower is undercollateralized and pledged collateral is lower than encumbered collateral, tx should revert with InsufficientCollateral
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC20Pool(address(_pool)).repayDebt(actor, 0, 149220, actor, 7388);
    }

    function testPullBorrowerWithDebtCollateralEncumberedCalculatedAsZero() external {
        address actor = makeAddr("actor");

        _mintCollateralAndApproveTokens(actor, 1000000000 * 1e18);
        _mintQuoteAndApproveTokens(actor, 1000000000000 * 1e18);

        changePrank(actor);
        _pool.addQuoteToken(200, 2572, block.timestamp + 100);
        ERC20Pool(address(_pool)).drawDebt(actor, 100, 7388, 1);

        // actor should not be able to pull his collateral without repaying the debt
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC20Pool(address(_pool)).repayDebt(actor, 0, 1, actor, 7388);

        // borrower should be able to repay and pull collateral
        ERC20Pool(address(_pool)).repayDebt(actor, 120, 1, actor, 7388);
    }
}
