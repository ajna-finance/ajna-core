// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolLiquidationsHealTest is ERC20HelperContract {

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
    
    function testHealOnAuctionKicked72HoursAgoAndPartiallyTaken() external {
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
        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    2_000 * 1e27,
                collateral:   0,
                deposit:      2_118.781595119199960000 * 1e18,
                exchangeRate: 1.05939079755959998 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    5_000 * 1e27,
                collateral:   0,
                deposit:      5_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      11_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // skip ahead so take can be called on the loan
        skip(10 hours);
        // take partial 800 collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   800 * 1e18,
                bondChange:      4.860647932515889920 * 1e18,
                givenAmount:     486.064793251588992000 * 1e18,
                collateralTaken: 800 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          103.394590352308106377 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 103.394590352308106377 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_495.870032454838888301 * 1e18
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_495.870032454838888301 * 1e18,
                borrowerCollateral:        200 * 1e18,
                borrowerMompFactor:        9.684667957374334904 * 1e18,
                borrowerCollateralization: 0.204747871059870949 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    2_000 * 1e27,
                collateral:   0,
                deposit:      2_118.911507166546111004 * 1e18,
                exchangeRate: 1.059455753583273055502 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    5_000 * 1e27,
                collateral:   0,
                deposit:      5_000.306572531226000000 * 1e18,
                exchangeRate: 1.0000613145062452 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      11_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // heal should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   10,
                healedDebt: 9_495.870032454838888301 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
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
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.684667957374334904 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    2_000 * 1e27,
                collateral:   200 * 1e18,
                deposit:      0,
                exchangeRate: 0.9917184843435912074 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      8_771.489426795178714532 * 1e18,
                exchangeRate: 0.797408129708652610412000000 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
    }

    function testHealOnAuctionKicked72HoursAgo() external {
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
        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    2_000 * 1e27,
                collateral:   0,
                deposit:      2_118.781595119199960000 * 1e18,
                exchangeRate: 1.05939079755959998 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    5_000 * 1e27,
                collateral:   0,
                deposit:      5_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      11_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // heal should work on an kicked auction if 72 hours passed from kick time
        // heal should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   10,
                healedDebt: 9_976.561670003961916237 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
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
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    2_000 * 1e27,
                collateral:   213.647484499757089173 * 1e18,
                deposit:      0,
                exchangeRate: 1.059390797559599980000723485 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    5_000 * 1e27,
                collateral:   509.229693680926841063 * 1e18,
                deposit:      0,
                exchangeRate: 0.999999999999999999999092167 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   277.122821819316069764 * 1e18,
                deposit:      8_290.284277977147272573 * 1e18,
                exchangeRate: 0.998570656348654837501066179 * 1e27
            }
        );
        _assertBucket(
            {
                index:        _i9_62,
                lpBalance:    25_000 * 1e27,
                collateral:   0,
                deposit:      25_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
    }

    function testHealAuctionReverts() external {
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
        // heal should revert on a borrower that is not auctioned
        _assertHealOnNotKickedAuctionRevert(
            {
                from:     _lender,
                borrower: _borrower2
            }
        );

        uint256 kickTime = _startTime + 100 days;
        _kick(
            {
                from:           _lender,
                borrower:       _borrower2,
                debt:           9_976.561670003961916237 * 1e18,
                collateral:     1_000 * 1e18,
                bond:           98.533942419792216457 * 1e18,
                transferAmount: 98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          kickTime,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_976.561670003961916237 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );

        // heal should revert on an kicked auction but 72 hours not passed (there's still debt to heal and collateral to be auctioned)
        _assertHealOnNotClearableAuctionRevert(
            {
                from:     _lender,
                borrower: _borrower2
            }
        );
        // skip ahead so take can be called on the loan
        skip(10 hours);
        // take entire collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000 * 1e18,
                bondChange:      6.075809915644862400 * 1e18,
                givenAmount:     607.580991564486240000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );

        // remove quote tokens should fail since auction head is clearable
        _assertRemoveLiquidityAuctionNotClearedRevert(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  _i9_52
            }
        );
        _assertRemoveAllLiquidityAuctionNotClearedRevert(
            {
                from:   _lender,
                index:  _i9_52
            }
        );
        // remove collateral should fail since auction head is clearable
        _assertRemoveCollateralAuctionNotClearedRevert(
            {
                from:   _lender,
                amount: 10 * 1e18,
                index:  _i9_52
            }
        );

        // add liquidity in same block should be possible as debt was not yet healed / bucket is not yet insolvent
        _addLiquidity(
            {
                from:   _lender1,
                amount: 100 * 1e18,
                index:  _i9_91,
                newLup: 9.721295865031779605 * 1e18
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       _i9_91,
                lpBalance:   94.388085261495553091346700232 * 1e27,
                depositTime: _startTime + 100 days + 10 hours
            }
        );
        // adding to a different bucket for testing move in same block with bucket bankruptcy
        _addLiquidity(
            {
                from:   _lender1,
                amount: 100 * 1e18,
                index:  _i9_52,
                newLup: 9.721295865031779605 * 1e18
            }
        );

        // heal to make buckets insolvent
        // heal should work because there is still debt to heal but no collateral left to auction (even if 72 hours didn't pass from kick)
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_375.568996125070612781 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 0
            }
        );
        assertTrue(block.timestamp - kickTime < 72 hours); // assert auction was kicked less than 72 hours ago
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   10,
                healedDebt: 9_375.568996125070612781 * 1e18
            }
        );

        // bucket is insolvent, balances are resetted
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    0, // bucket is bankrupt
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        // after bucket bankruptcy lenders balance is zero
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       _i9_91,
                lpBalance:   0,
                depositTime: _startTime + 100 days + 10 hours
            }
        );
        // cannot add liquidity in same block when bucket marked insolvent
        _assertAddLiquidityBankruptcyBlockRevert(
            {
                from:   _lender1,
                amount: 1_000 * 1e18,
                index:  _i9_91
            }
        );
        // cannot add collateral in same block when bucket marked insolvent
        _assertAddCollateralBankruptcyBlockRevert(
            {
                from:   _lender1,
                amount: 10 * 1e18,
                index:  _i9_91
            }
        );
        // cannot move LPs in same block when bucket marked insolvent
        _assertMoveLiquidityBankruptcyBlockRevert(
            {
                from:      _lender1,
                amount:    10 * 1e18,
                fromIndex: _i9_52,
                toIndex:   _i9_91
            }
        );

        // all operations should work if not in same block
        skip(1 hours);
        _pool.addQuoteToken(100 * 1e18, _i9_91);
        _pool.moveQuoteToken(10 * 1e18, _i9_52, _i9_91);
        ERC20Pool(address(_pool)).addCollateral(4 * 1e18, _i9_91);
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       _i9_91,
                lpBalance:   149.668739373743648321147432044 * 1e27,
                depositTime: _startTime + 100 days + 10 hours + 1 hours
            }
        );
        // bucket is healthy again
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    149.668739373743648321147432044 * 1e27,
                collateral:   4 * 1e18,
                deposit:      109.999999999999999948 * 1e18,
                exchangeRate: 0.999999999999999999484545454 * 1e27
            }
        );

        // when moving to a bucket that was marked insolvent, the deposit time should be the greater between from bucket deposit time and insolvency time + 1
        changePrank(_lender);
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   0,
                depositTime: _startTime
            }
        );
        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91);
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   1_000.000000000000000515454546000 * 1e27,
                depositTime: _startTime + 100 days + 10 hours + 1 // _i9_91 bucket insolvency time + 1 (since deposit in _i9_52 from bucket was done before _i9_91 target bucket become insolvent)
            }
        );
        _pool.addQuoteToken(1_000 * 1e18, _i9_52);
        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91);
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   2_000.000000000000001438852689000 * 1e27,
                depositTime: _startTime + 100 days + 10 hours + 1 hours // time of deposit in _i9_52 from bucket (since deposit in _i9_52 from bucket was done after _i9_91 target bucket become insolvent)
            }
        );
    }

}