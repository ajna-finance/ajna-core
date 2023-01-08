// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

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
    function testAddPullCollateral() external tearDown {
        // lender deposits 10000 Quote into 3 buckets

        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
            }
        );

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
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     21_000 * 1e18,
                indexLimit: 3_000,
                newLup:     2_981.007422784467321543 * 1e18
            }
        );

        _assertPool(
            PoolParams({
                htp:                  210.201923076923077020 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    100 * 1e18,
                encumberedCollateral: 7.051372011699988577 * 1e18,
                poolDebt:             21_020.192307692307702000 * 1e18,
                actualUtilization:    0.700673076923076923 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        2_102.019230769230770200 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_020.192307692307702000 * 1e18,
                borrowerCollateral:        100 * 1e18,
                borrowert0Np:              220.712019230769230871 * 1e18,
                borrowerCollateralization: 14.181637252165253251 * 1e18
            }
        );
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
                htp:                  421.557216751451801727 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_025.923273028334880000 * 1e18,
                pledgedCollateral:    50 * 1e18,
                encumberedCollateral: 7.061038044473493202 * 1e18,
                poolDebt:             21_049.0068231390029184310 * 1e18,
                actualUtilization:    0.701027796272525944 * 1e18,
                targetUtilization:    0.141220760889469864 * 1e18,
                minDebtAmount:        2_104.900682313900291843 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_049.006823139002918431 * 1e18,
                borrowerCollateral:        50 * 1e18,
                borrowert0Np:              441.424038461538461742 * 1e18,
                borrowerCollateralization: 7.081111825921092812 * 1e18
            }
        );
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
                htp:                  2_985.093792841086761332 * 1e18,
                lup:                  2_981.007422784467321543 * 1e18,
                poolSize:             30_025.923273028334880000 * 1e18,
                pledgedCollateral:    7.061038044473493202 * 1e18,
                encumberedCollateral: 7.061038044473493202 * 1e18,
                poolDebt:             21_049.0068231390029184310 * 1e18,
                actualUtilization:    0.701027796272525944 * 1e18,
                targetUtilization:    0.141220760889469864 * 1e18,
                minDebtAmount:        2_104.900682313900291843 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              21_049.006823139002918431 * 1e18,
                borrowerCollateral:        7.061038044473493202 * 1e18,
                borrowert0Np:              3_140.657612229160876676 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        assertEq(_collateral.balanceOf(_borrower), 142.938961955526506798 * 1e18);
    }

    /**
     *  @notice 1 borrower tests reverts in pullCollateral.
     *          Reverts:
     *              Attempts to remove more than available claimable collateral.
     */
    function testPullCollateralRequireEnoughCollateral() external tearDown {
        _assertPullInsufficientCollateralRevert(
            {
                from:   _borrower,
                amount: 100 * 1e18
            }
        );

        // borrower deposits 100 collateral
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );

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
        _assertAddCollateralAtIndex0Revert(
            {
                from:   _bidder,
                amount: 4 * 1e18
            }
        );

        // actor deposits collateral into a bucket
        _addCollateral(
            {
                from:    _bidder,
                amount:  4 * 1e18,
                index:   2550,
                lpAward: 12_043.56808879152623138 * 1e27
            }
        );

        // check bucket state and bidder's LPs
        _assertBucket(
            {
                index:        2550,
                lpBalance:    12_043.56808879152623138 * 1e27,
                collateral:   4 * 1e18,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2550,
                lpBalance:   12_043.56808879152623138 * 1e27,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_collateral.balanceOf(_bidder),        96 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 4 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws some of their collateral
        _removeCollateral(
            {
                from:     _bidder,
                amount:   1.53 * 1e18,
                index:    2550,
                lpRedeem: 4_606.664793962758783502850000000 * 1e27
            }
        );
        // check bucket state and bidder's LPs
        _assertBucket(
            {
                index:        2550,
                lpBalance:    7_436.90329482876744787715 * 1e27,
                collateral:   2.47 * 1e18,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2550,
                lpBalance:   7_436.90329482876744787715 * 1e27,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_collateral.balanceOf(_bidder),        97.53 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 2.47 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws remainder of their _collateral
        _removeCollateral(
            {
                from:     _bidder,
                amount:   2.47 * 1e18,
                index:    2550,
                lpRedeem: 7_436.90329482876744787715 * 1e27
            }
        );
        // check bucket state and bidder's LPs
        _assertBucket(
            {
                index:        2550,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       2550,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_collateral.balanceOf(_bidder),        100 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
        assertEq(_quote.balanceOf(address(_pool)),      0);
    }

    function testRemoveHalfCollateral() external tearDown {
        // test setup
        _mintCollateralAndApproveTokens(_bidder,  1 * 1e18);

        // actor deposits collateral into a bucket
        _addCollateral(
            {
                from:    _bidder,
                amount:  1 * 1e18,
                index:   1530,
                lpAward: 487616.252661175041981841 * 1e27
            }
        );

        _removeCollateral(
            {
                from:     _bidder,
                amount:   0.5 * 1e18,
                index:    1530,
                lpRedeem: 243_808.1263305875209909205 * 1e27
            }
        );
        // check bucket state and bidder's LPs
        _assertBucket(
            {
                index:        1530,
                lpBalance:    243_808.1263305875209909205 * 1e27,
                collateral:   0.5 * 1e18,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       1530,
                lpBalance:   243_808.1263305875209909205 * 1e27,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_collateral.balanceOf(_bidder),        0.5 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0.5 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);

        // actor withdraws remainder of their _collateral
        _removeAllCollateral(
            {
                from:     _bidder,
                amount:   0.5 * 1e18,
                index:    1530,
                lpRedeem: 243_808.1263305875209909205 * 1e27
            }
        );
        // check bucket state and bidder's LPs
        _assertBucket(
            {
                index:        1530,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _bidder,
                index:       1530,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        // check balances
        assertEq(_collateral.balanceOf(_bidder),        1 * 1e18);
        assertEq(_collateral.balanceOf(address(_pool)), 0 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)),      0);
    }

    function testRemoveCollateralReverts() external tearDown {
        uint256 testIndex = 6348;

        // should revert if no collateral in the bucket
        _assertRemoveInsufficientCollateralRevert(
            {
                from:  _lender,
                amount: 3.50 * 1e18,
                index:  testIndex
            }
        );

        // another actor deposits some collateral
        deal(address(_collateral), _bidder,  100 * 1e18);
        changePrank(_bidder);
        _collateral.approve(address(_pool), 100 * 1e18);
        _addCollateral(
            {
                from:    _bidder,
                amount:  0.65 * 1e18,
                index:   testIndex,
                lpAward: 0.0000116119721720119 * 1e27
            }
        );

        // should revert if actor has no LPB in the bucket
        _assertRemoveAllCollateralNoClaimRevert(
            {
                from:  _lender,
                index: testIndex
            }
        );

        // should revert if actor does not have LP
        _assertRemoveAllCollateralNoClaimRevert(
            {
                from:  _lender,
                index: testIndex
            }
        );
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
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                amount:   100 * 1e18
            }
        );

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
}
