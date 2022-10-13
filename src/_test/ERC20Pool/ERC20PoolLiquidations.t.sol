// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

contract ERC20PoolLiquidationsTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    uint256 internal _i9_91 = 3696;
    uint256 internal _i9_81 = 3698;
    uint256 internal _i9_72 = 3700;
    uint256 internal _i9_62 = 3702;
    uint256 internal _i9_52 = 3704;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);

        // Lender adds Quote token accross 5 prices
        _addLiquidity(
            {
                from:   _lender,
                amount: 2_000 * 1e18,
                index:  _i9_91,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  _i9_81,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  _i9_72,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i9_62,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  _i9_52,
                newLup: BucketMath.MAX_PRICE
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
            PoolState({
                htp:                  9.634254807692307697 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 823.649613971736296163 * 1e18,
                borrowerDebt:         8_006.941586538461542154 * 1e18,
                actualUtilization:    0.109684131322444679 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        400.347079326923077108 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   0
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.268509615384615394 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1.009034539679184679 * 1e18,
                borrowerPendingDebt:       19.268509615384615394 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1.217037273735858713 * 1e18,
                borrowerPendingDebt:       7_987.673076923076926760 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   7.691586538461542154 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              3 days
            }
        );
        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

    }

    function testKick() external {
        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolState({
                htp:                  8.097846143253778448 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_094.502279691716022000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 835.010119425512354679 * 1e18,
                borrowerDebt:         8_117.380421230925720814 * 1e18,
                actualUtilization:    0.111053227918158028 * 1e18,
                targetUtilization:    0.833343432560391572 * 1e18,
                minDebtAmount:        811.738042123092572081 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.778456451861613480 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerInflator:          1.013792886272348689 * 1e18,
                borrowerCollateralization: 0.983018658578564579 * 1e18,
                borrowerPendingDebt:       19.778456451861613480 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1.217037273735858713 * 1e18,
                borrowerPendingDebt:       8_097.846143253778448241 * 1e18
            }
        );
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);
        _assertAuction(
            {
                borrower:       _borrower,
                active:         true,
                kicker:         _lender,
                bondSize:       0.195342779771472726 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.195342779771472726 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   23.628141539209698814 * 1e18,
                claimableReserves :         0,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        // kick should fail if borrower properly collateralized
        _assertKickCollateralizedBorrowerRevert(
            {
                from:       _lender,
                borrower:   _borrower2
            }
        );
    }

    function testKickAndSaveByRepay() external {

        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         true,
                kicker:         _lender,
                bondSize:       0.195342779771472726 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.195342779771472726 * 1e18
            }
        );

        _repay(
            {
                from: _borrower,
                borrower: _borrower,
                amount: 15 * 1e18,
                repaid: 15 * 1e18,
                newLup: 9.721295865031779605 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0.195342779771472726 * 1e18,
                locked:    0
            }
        );
    }

    function testKickAndSaveByPledgeCollateral() external {

        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         true,
                kicker:         _lender,
                bondSize:       0.195342779771472726 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.195342779771472726 * 1e18
            }
        );

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   2 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0.195342779771472726 * 1e18,
                locked:    0
            }
        );
    }

    function testKickActiveAuctionReverts() external {

        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         true,
                kicker:         _lender,
                bondSize:       0.195342779771472726 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );

        // kick should fail if borrower in liquidation
        _assertKickAuctionActiveRevert(
            {
                from:       _lender,
                borrower:   _borrower
            }
        );

        // should not allow borrower to draw more debt if auction kicked
        _assertBorrowAuctionActiveRevert(
            {
                from:       _borrower,
                amount:     1 * 1e18,
                indexLimit: 7000
            }
        );
    }

    function testTakeGTNeutral() external {

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         true,
                kicker:         _lender,
                bondSize:       0.195342779771472726 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.195342779771472726 * 1e18
            }
        );

        skip(2 hours);

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2 * 1e18,
                bondChange:      0.195828313427972085 * 1e18,
                givenAmount:     19.582831342797208527 * 1e18,
                collateralTaken: 2 * 1e18,
                isReward:        false
            }
        );
        _assertAuction(
            {
                borrower:       _borrower,
                active:         false,
                kicker:         address(0),
                bondSize:       0,
                bondFactor:     0,
                kickTime:       0,
                kickPriceIndex: 0
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0, // the entire bond was penalized
                locked:    0
            }
        );
    }

    function testTakeLTNeutral() external {
         
        // Borrower2 borrows
        _borrow(
            {
                from:       _borrower2,
                amount:     1_730 * 1e18,
                indexLimit: _i9_72,
                newLup:     9.721295865031779605 * 1e18
            }
        );

        // Skip to make borrower undercollateralized
        skip(100 days);
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_719.336538461538466020 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1.000201590567677913 * 1e18,
                borrowerPendingDebt:       9_853.394241979221645666 * 1e18
            }
        );
        _kick(
            {
                from:       _lender,
                borrower:   _borrower2,
                debt:       9_853.394241979221645666 * 1e18,
                collateral: 1_000 * 1e18,
                bond:       98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            {
                borrower:       _borrower2,
                active:         true,
                kicker:         _lender,
                bondSize:       98.533942419792216457 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.533942419792216457 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerInflator:          1.013792886272348689 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18,
                borrowerPendingDebt:       9_976.561670003961916237 * 1e18
            }
        );

        //skip ahead so take can be called on the loan
        skip(5 hours);

        // perform partial take for 20 collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   20 * 1e18,
                bondChange:      1.239648105429489010 * 1e18,
                givenAmount:     123.964810542948901000 * 1e18,
                collateralTaken: 20 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            {
                borrower:       _borrower2,
                active:         true,
                kicker:         _lender,
                bondSize:       99.773590525221705467 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp - 5 hours,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    99.773590525221705467 * 1e18 // locked bond + reward, auction is not yet finished
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_854.149703630767216798 * 1e18,
                borrowerCollateral:        980 * 1e18,
                borrowerMompFactor:        9.684861431554868575 * 1e18,
                borrowerInflator:          1.013824712461823922 * 1e18,
                borrowerCollateralization: 0.966787620876204389 * 1e18,
                borrowerPendingDebt:       9_854.149703630767216798 * 1e18
            }
        );

        // take remaining collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   981 * 1e18,
                bondChange:      60.742757166044961490 * 1e18,
                givenAmount:     6_074.275716604496149000 * 1e18,
                collateralTaken: 980 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            {
                borrower:       _borrower2,
                active:         true,
                kicker:         _lender,
                bondSize:       160.516347691266666957 * 1e18,
                bondFactor:     0.01 * 1e18,
                kickTime:       block.timestamp - 5 hours,
                kickPriceIndex: 3696
            }
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    160.516347691266666957 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              3_840.616744192316029288 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.684861431554868575 * 1e18,
                borrowerInflator:          1.013824712461823922 * 1e18,
                borrowerCollateralization: 0,
                borrowerPendingDebt:       3_840.616744192316029288 * 1e18
            }
        );

        // should revert if there's no more collateral to be auctioned
        _assertTakeInsufficentCollateralRevert(
            {
                from:          _lender,
                borrower:      _borrower2,
                maxCollateral: 10 * 1e18
            }
        );
        
    }

    function testTakeReverts() external {
        // should revert if there's no auction started
        _assertTakeNoAuctionRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 10 * 1e18
            }
        );

        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );

        // should revert if auction in grace period
        _assertTakeAuctionInCooldownRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 10 * 1e18
            }
        );

        skip(2 hours);

        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertTakeDebtUnderMinPoolDebtRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 0.1 * 1e18
            }
        );

    }

    function testAuctionPrice() external {
        skip(6238);
        uint256 referencePrice = 8_678.5 * 1e18;
        uint256 kickTime = block.timestamp;
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);
        skip(1444); // price should not change in the first hour
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 86_785.0 * 1e18);

        skip(5756);     // 2 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 43_392.5 * 1e18);
        skip(2394);     // 2 hours, 39 minutes, 54 seconds
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 27_367.159606354998613290 * 1e18);
        skip(2586);     // 3 hours, 23 minutes
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 16_633.737549018910661740 * 1e18);
        skip(3);        // 3 seconds later
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 16_624.132299820494703920 * 1e18);
        skip(20153);    // 8 hours, 35 minutes, 53 seconds
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 343.207165783609045700 * 1e18);
        skip(97264);    // 36 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 0.00000252577588655 * 1e18);
        skip(129600);   // 72 hours
        assertEq(PoolUtils.auctionPrice(referencePrice, kickTime), 0);
    }

    // TODO: move to DSTestPlus?
    function _logBorrowerInfo(address borrower_) internal {
        (
            uint256 borrowerDebt,
            uint256 borrowerPendingDebt,
            uint256 collateralDeposited,
            uint256 mompFactor,
            uint256 borrowerInflator

        ) = _poolUtils.borrowerInfo(address(_pool), borrower_);

        emit log_named_uint("borrowerDebt        ", borrowerDebt);
        emit log_named_uint("borrowerPendingDebt ", borrowerPendingDebt);
        emit log_named_uint("collateralDeposited ", collateralDeposited);
        emit log_named_uint("mompFactor ",           mompFactor);
        emit log_named_uint("collateralEncumbered", PoolUtils.encumberance(borrowerDebt, _lup()));
        emit log_named_uint("collateralization   ", PoolUtils.collateralization(borrowerDebt, collateralDeposited, _lup()));
        emit log_named_uint("borrowerInflator    ", borrowerInflator);
    }
}
