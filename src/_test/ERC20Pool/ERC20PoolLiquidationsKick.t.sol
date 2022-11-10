// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolLiquidationsKickTest is ERC20HelperContract {

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

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender1,   4 * 1e18);

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
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 1.009034539679184679 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_987.673076923076926760 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
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

    }
    
    function testKick() external {
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0
            })
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.778456451861613480 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolState({
                htp:                  8.209538814158655264 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_094.502279691716022000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 835.035237319063220561 * 1e18,
                poolDebt:             8_117.624599705640061720 * 1e18,
                actualUtilization:    0.111056568504208946 * 1e18,
                targetUtilization:    0.833368500318426368 * 1e18,
                minDebtAmount:        811.762459970564006172 * 1e18,
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
                borrowerCollateralization: 0.983018658578564579 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              8_097.846143253778448241 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 1.200479200648987171 * 1e18
            }
        );
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18
            })
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
                reserves:                   23.872320013924039720 * 1e18,
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

        _assertDepositLockedByAuctionDebtRevert({
            operator:  _lender,
            amount:    100 * 1e18,
            index:     _i9_91
        });
    }

    function testKickAndSaveByRepay() external {

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0
            })
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.778456451861613480 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18
            })
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
                from:      _borrower,
                borrower:  _borrower,
                amount:    15 * 1e18,
                repaid:    15 * 1e18,
                newLup:    9.721295865031779605 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     4.778456451861613480 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0.195342779771472726 * 1e18,
                locked:    0
            }
        );

        // kicker withdraws his auction bonds
        changePrank(_lender);
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0
            }
        );
    }

    function testKickAndSaveByPledgeCollateral() external {

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0
            })
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:        _lender,
                borrower:    _borrower,
                debt:        19.778456451861613480 * 1e18,
                collateral:  2 * 1e18,
                bond:        0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18
            })
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
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0.195342779771472726 * 1e18,
                locked:    0
            }
        );

        // kicker withdraws his auction bonds
        changePrank(_lender);
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0
            }
        );
    }

    function testKickActiveAuctionReverts() external {

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0
            })
        );

        // Skip to make borrower undercollateralized
        skip(100 days);

        _kick(
            {
                from:        _lender,
                borrower:    _borrower,
                debt:        19.778456451861613480 * 1e18,
                collateral:  2 * 1e18,
                bond:        0.195342779771472726 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     19.778456451861613480 * 1e18
            })
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

    function testInterestsAccumulationWithAllLoansAuctioned() external {
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
                borrower:                  _borrower,
                borrowerDebt:              19.534277977147272573 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 0.995306391810796636 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );
        _assertLoans(
            {
                noOfLoans:         2,
                maxBorrower:       _borrower2,
                maxThresholdPrice: 9.719336538461538466 * 1e18
            }
        );

        // kick first loan
        _kick(
            {
                from:       _lender,
                borrower:   _borrower2,
                debt:       9_976.561670003961916237 * 1e18,
                collateral: 1_000 * 1e18,
                bond:       98.533942419792216457 * 1e18
            }
        );
        _assertLoans(
            {
                noOfLoans:         1,
                maxBorrower:       _borrower,
                maxThresholdPrice: 9.767138988573636287 * 1e18
            }
        );

        // kick 2nd loan
        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.534277977147272573 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.195342779771472726 * 1e18
            }
        );
        _assertLoans(
            {
                noOfLoans:         0,
                maxBorrower:       address(0),
                maxThresholdPrice: 0
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_118.781595119199960000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.267844818693957410 * 1e18,
                poolDebt:             9_996.095947981109188810 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.026215413990712532 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 100 days
            })
        );

        // force pool interest accumulation 
        skip(14 hours);

        _addLiquidity(
            {
                from:   _lender1,
                amount: 1 * 1e18,
                index:  _i9_91,
                newLup: 9.721295865031779605 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_120.392679807500549985 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.341798247607959833 * 1e18,
                poolDebt:             9_996.814871143815802222 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.026254142489845669 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 100 days + 14 hours
            })
        );
    }
}