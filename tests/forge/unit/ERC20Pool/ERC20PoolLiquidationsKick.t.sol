// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsKickTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;
    address internal _withdrawRecipient;

    function setUp() external {
        _borrower          = makeAddr("borrower");
        _borrower2         = makeAddr("borrower2");
        _lender            = makeAddr("lender");
        _lender1           = makeAddr("lender1");
        _withdrawRecipient = makeAddr("withdrawRecipient");

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
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 1.009034539679184679 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.471136974495192174 * 1e18,
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

    }
    
    function testKick() external tearDown {
        // Skip to make borrower undercollateralized
        skip(100 days);

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
                thresholdPrice:    9.767138988573636286 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.534277977147272573 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.995306391810796636 * 1e18
        });

        // should revert if NP goes below limit
        _assertKickNpUnderLimitRevert({
            from:     _lender,
            borrower: _borrower
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.778456451861613481 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195342779771472726 * 1e18,
            transferAmount: 0.195342779771472726 * 1e18
        });

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  8.097846143253778448 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_093.873009488594544000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 835.035237319063220561 * 1e18,
                poolDebt:             8_117.624599705640061721 * 1e18,
                actualUtilization:    0.109684131322444679 * 1e18,
                targetUtilization:    0.822075127292417292 * 1e18,
                minDebtAmount:        811.762459970564006172 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.778456451861613481 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.983018658578564579 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_097.846143253778448241 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              8.471136974495192174 * 1e18,
            borrowerCollateralization: 1.200479200648987171 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      328.175870016074179200 * 1e18,
                debtInAuction:     19.778456451861613481 * 1e18,
                thresholdPrice:    9.889228225930806740 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );
        assertEq(_poolUtils.momp(address(_pool)), 9.818751856078723036 * 1e18);
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.195342779771472726 * 1e18
        });
        _assertReserveAuction({
            reserves:                   24.501590217045517721 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick should fail if borrower properly collateralized
        _assertKickCollateralizedBorrowerRevert({
            from:       _lender,
            borrower:   _borrower2
        });

        _assertDepositLockedByAuctionDebtRevert({
            operator:  _lender,
            amount:    100 * 1e18,
            index:     _i9_91
        });

        skip(80 hours);

        // check locked pool actions if auction kicked for more than 72 hours and auction head not cleared
        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  _i9_91
        });
        _assertRemoveCollateralAuctionNotClearedRevert({
            from:   _lender,
            amount: 10 * 1e18,
            index:  _i9_91
        });
    }

    function testKickAndSaveByRepay() external tearDown {

        // Skip to make borrower undercollateralized
        skip(100 days);

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
                thresholdPrice:    9.767138988573636286 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.534277977147272573 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.995306391810796636 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.778456451861613481 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195342779771472726 * 1e18,
            transferAmount: 0.195342779771472726 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      328.175870016074179200 * 1e18,
                debtInAuction:     19.778456451861613481 * 1e18,
                thresholdPrice:    9.889228225930806740 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.195342779771472726 * 1e18
        });

        _repayAndSettleAuction({
            from:       _borrower,
            borrower:   _borrower,
            amount:     2 * 1e18,
            repaid:     2 * 1e18,
            collateral: 2 * 1e18,
            newLup:     9.721295865031779605 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    8.889228225930806740 * 1e18,
                neutralPrice:      0
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0.195342779771472726 * 1e18,
            locked:    0
        });

        // Skip to make borrower undercollateralized again
        skip(750 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.500754673204780611 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              9.254718877190426162 * 1e18,
            borrowerCollateralization: 0.997017400397270737 * 1e18
        });

        // Kick method only emit Kick event and doesn't call transfer method when kicker has enough bond amount in claimable
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.720138163278334393 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195007546732047806 * 1e18,
            transferAmount: 0
        });

        uint256 snapshot = vm.snapshot();

        // kicker not saved if partial debt paid only
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0.0001 * 1e18,
            amountRepaid:     0.0001 * 1e18,
            collateralToPull: 0,
            newLup:           9.721295865031779605 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          0.195007546732047806 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 850 days,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      329.321295632797165376 * 1e18,
                debtInAuction:     19.720038163278334393 * 1e18,
                thresholdPrice:    9.860019081639167196 * 1e18,
                neutralPrice:      10.291290488524911418 * 1e18
            })
        );

        vm.revertTo(snapshot);

        // kicker saved if enough debt paid
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    10 * 1e18,
            amountRepaid:     10 * 1e18,
            collateralToPull: 0,
            newLup:           9.721295865031779605 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    4.860069081639167196 * 1e18,
                neutralPrice:      0
            })
        );

        // kicker balance before withdraw auction bonds
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);

        // should revert if user without claimable amount tries to withdraw bond
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        _pool.withdrawBonds(_withdrawRecipient, type(uint256).max);

        snapshot = vm.snapshot();

        changePrank(_lender);

        // should revert if trying to withdraw 0 bond amount
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        _pool.withdrawBonds(_withdrawRecipient, 0);

        // kicker withdraws partial auction bonds and transfer to a different address
        vm.expectEmit(true, true, false, true);
        emit BondWithdrawn(_lender, _withdrawRecipient, 0.1 * 1e18);
        _pool.withdrawBonds(_withdrawRecipient, 0.1 * 1e18);

        // kicker withdraws remaining auction bonds
        vm.expectEmit(true, true, false, true);
        emit BondWithdrawn(_lender, _lender, 0.095342779771472726 * 1e18);
        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_withdrawRecipient), 0.1 * 1e18);
        assertEq(_quote.balanceOf(_lender), 46_999.9 * 1e18);

        vm.revertTo(snapshot);

        // kicker withdraws entire auction bonds
        vm.expectEmit(true, true, false, true);
        emit BondWithdrawn(_lender, _lender, 0.195342779771472726 * 1e18);
        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0
        });
    }

    function testKickAndSaveByPledgeCollateral() external tearDown {

        // Skip to make borrower undercollateralized
        skip(100 days);

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
                thresholdPrice:    9.767138988573636286 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.534277977147272573 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.995306391810796636 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.778456451861613481 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195342779771472726 * 1e18,
            transferAmount: 0.195342779771472726 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      328.175870016074179200 * 1e18,
                debtInAuction:     19.778456451861613481 * 1e18,
                thresholdPrice:    9.889228225930806740 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.195342779771472726 * 1e18
        });

        _pledgeCollateralAndSettleAuction({
            from:       _borrower,
            borrower:   _borrower,
            amount:     2 * 1e18,
            collateral: 4 * 1e18 // collateral after auction settled = 2 new pledged + initial 2 collateral pledged 
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    4.944614112965403370 * 1e18,
                neutralPrice:      0
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0.195342779771472726 * 1e18,
            locked:    0
        });

        // kicker withdraws his auction bonds
        changePrank(_lender);
        assertEq(_quote.balanceOf(_lender), 46_999.804657220228527274 * 1e18);

        _pool.withdrawBonds(_lender, type(uint256).max);

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0
        });
    }

    function testKickActiveAuctionReverts() external tearDown {

        // Skip to make borrower undercollateralized
        skip(100 days);

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
                thresholdPrice:    9.767138988573636286 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.534277977147272573 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.995306391810796636 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.778456451861613481 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195342779771472726 * 1e18,
            transferAmount: 0.195342779771472726 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.195342779771472726 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.818751856078723036 * 1e18,
                totalBondEscrowed: 0.195342779771472726 * 1e18,
                auctionPrice:      328.175870016074179200 * 1e18,
                debtInAuction:     19.778456451861613481 * 1e18,
                thresholdPrice:    9.889228225930806740 * 1e18,
                neutralPrice:      10.255495938002318100 * 1e18
            })
        );

        // should not allow borrower to draw more debt if auction kicked
        _assertBorrowAuctionActiveRevert({
            from:       _borrower,
            amount:     1 * 1e18,
            indexLimit: 7000
        });

        // should not allow borrower to restamp the Neutral Price of the loan if auction kicked
        _assertStampLoanAuctionActiveRevert({
            borrower: _borrower
        });
    }

    function testInterestsAccumulationWithAllLoansAuctioned() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.534277977147272573 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.115967548076923081 * 1e18,
            borrowerCollateralization: 0.995306391810796636 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645666 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.307611531622595991 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertLoans({
            noOfLoans:         2,
            maxBorrower:       _borrower2,
            maxThresholdPrice: 9.719336538461538466 * 1e18
        });

        // kick first loan
        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        _assertLoans({
            noOfLoans:         1,
            maxBorrower:       _borrower,
            maxThresholdPrice: 9.767138988573636287 * 1e18
        });

        // kick 2nd loan
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           19.754038604390179389 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.195342779771472726 * 1e18,
            transferAmount: 0.195342779771472726 * 1e18
        });

        _assertLoans({
            noOfLoans:         0,
            maxBorrower:       address(0),
            maxThresholdPrice: 0
        });
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_114.174951097528944000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.290450922889736704 * 1e18,
                poolDebt:             9_996.315708608352095626 * 1e18,
                actualUtilization:    0.541033613782051282 * 1e18,
                targetUtilization:    0.999781133426980224 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 100 days
            })
        );

        // force pool interest accumulation 
        skip(14 hours);

        _addLiquidity({
            from:    _lender1,
            amount:  1 * 1e18,
            index:   _i9_91,
            lpAward: 0.993688287401017551 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_115.810705342225439101 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_028.364405977643667984 * 1e18,
                poolDebt:             9_997.034647576329686631 * 1e18,
                actualUtilization:    0.100661311571554831 * 1e18,
                targetUtilization:    0.999781133426980224 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 100 days + 14 hours
            })
        );
    }
}
