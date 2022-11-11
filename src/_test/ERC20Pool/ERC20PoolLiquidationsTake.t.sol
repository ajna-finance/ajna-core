// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolLiquidationsTakeTest is ERC20HelperContract {

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

        // should revert if there's no auction started
        _assertTakeNoAuctionRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 10 * 1e18
            }
        );
    }
    
    function utilKickBorrower() public {

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
    }

    function testTakeGTAndLTNeutral() external {

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

        uint256 snapshot = vm.snapshot();

        skip(2 hours);

        // Collateral amount is restrained by debt
        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2 * 1e18,
                bondChange:      0.195342779771472726 * 1e18,
                givenAmount:     19.778659656225180612 * 1e18,
                collateralTaken: 0.127160642539504961 * 1e18,
                isReward:        false
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

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0 * 1e18,
                borrowerCollateral:        1.872839357460495039 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1.0 * 1e18
            }
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0, // the entire bond was penalized
                locked:    0
            }
        );

        vm.revertTo(snapshot);

        skip(6 hours);

        // Collateral amount is restrained by taker
        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   1 * 1e18,
                bondChange:      0.097212958650317796 * 1e18,
                givenAmount:     9.721295865031779616 * 1e18,
                collateralTaken: 1 * 1e18,
                isReward:        true
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.292555738421790522 * 1e18,
                bondFactor:        0.010000000000000000 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 0.292555738421790522 * 1e18,
                auctionPrice:      9.721295865031779616 * 1e18,
                debtInAuction:     10.154983164834054929 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              10.154983164834054929 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        9.684866959445391109 * 1e18,
                borrowerCollateralization: 0.957293154231500657 * 1e18
            }
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.292555738421790522 * 1e18
            }
        );
    }

    function testTakewithHeal() external {

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
                borrowerDebt:              9_853.394241979221645666 * 1e18,
                borrowerCollateral:        1_000 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.986593617011217057 * 1e18
            }
        );
        _kick(
            {
                from:       _lender,
                borrower:   _borrower2,
                debt:       9_976.561670003961916237 * 1e18,
                collateral: 1_000 * 1e18,
                bond:       98.533942419792216457 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.533942419792216457 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.533942419792216457 * 1e18,
                auctionPrice:      311.081467681016947360 * 1e18,
                debtInAuction:     9_976.561670003961916237 * 1e18
            })
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
                borrowerCollateralization: 0.974413448899967463 * 1e18
            }
        );
        _assertReserveAuction(
            {
                reserves:                   148.064352861909228810 * 1e18,
                claimableReserves :         98.083873122003682866 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        uint256 preTakeSnapshot = vm.snapshot();

        // skip ahead so take can be called on the loan
        // Debt cannot be used as a constraint when AP < NP
        skip(358 minutes);

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000 * 1e18,
                bondChange:      99.485203846497266560 * 1e18,
                givenAmount:     9_948.520384649726656000 * 1e18,
                collateralTaken: 1_000 * 1e18,
                isReward:        true
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              127.832282335540121316 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.781959425706739955 * 1e18,
                borrowerCollateralization: 0
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          198.019146266289483017 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 358 minutes,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 198.019146266289483017 * 1e18,
                auctionPrice:      9.948520384649726656 * 1e18,
                debtInAuction:     127.832282335540121316 * 1e18
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    198.019146266289483017 * 1e18 // locked bond + reward, auction is not yet finished
            }
        );

        vm.revertTo(preTakeSnapshot);

        // skip ahead so take can be called on the loan
        skip(10 hours);

        // partial take for 20 collateral
        // Collateral amount is restrained by taker
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   20 * 1e18,
                bondChange:      0.121516198312897248 * 1e18,
                givenAmount:     12.151619831289724800 * 1e18,
                collateralTaken: 20 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          98.655458618105113705 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 98.655458618105113705 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_965.044074140935162829 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    98.655458618105113705 * 1e18 // locked bond + reward, auction is not yet finished
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_965.044074140935162829 * 1e18,
                borrowerCollateral:        980 * 1e18,
                borrowerMompFactor:        9.684667957374334904 * 1e18,
                borrowerCollateralization: 0.956028882245805301 * 1e18
            }
        );

        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         98.218482774160286961 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            }
        );

        // take remaining collateral
        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   981 * 1e18,
                bondChange:      5.954293717331965152 * 1e18,
                givenAmount:     595.429371733196515200 * 1e18,
                collateralTaken: 980 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          104.609752335437078857 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 104.609752335437078857 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_375.568996125070612781 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0 * 1e18,
                locked:    104.609752335437078857 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_375.568996125070612781 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // reserves should increase after take action
        _assertReserveAuction(
            {
                reserves:                   148.141379552245490832 * 1e18,
                claimableReserves :         101.165858164239609711 * 1e18,
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
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

        // full clear / debt heal
        uint256 postTakeSnapshot = vm.snapshot();

        _assertBucket(
            {
                index:        3696,
                lpBalance:    2_000 * 1e27,
                collateral:   0,
                deposit:      2_118.911507166546111004 * 1e18,
                exchangeRate: 1.059455753583273055502000000 * 1e27
            }
        );
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   10,
                healedDebt: 9_375.568996125070612781 * 1e18
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
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 104.609752335437078857 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBucket(
            {
                index:        _i9_91,
                lpBalance:    0, // bucket is bankrupt
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_91,
                lpBalance:   0, // bucket is bankrupt
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_81,
                lpBalance:    0, // bucket is bankrupt
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_81,
                lpBalance:   0, // bucket is bankrupt
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    11_000 * 1e27,
                collateral:   0,
                deposit:      8_891.790463124946990051 * 1e18,
                exchangeRate: 0.808344587556813362731909090 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_72,
                lpBalance:   11_000 * 1e27,
                depositTime: _startTime
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
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_62,
                lpBalance:   25_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    30_000 * 1e27,
                collateral:   0,
                deposit:      30_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       _i9_52,
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );

        vm.revertTo(postTakeSnapshot);

        // partial clears / debt heal - max buckets to use is 1
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   1,
                healedDebt: 148.141379552245490832 * 1e18
            }
        );
        _assertAuction(
            AuctionState({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          104.609752335437078857 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          _startTime + 100 days,
                kickMomp:          9.721295865031779605 * 1e18,
                totalBondEscrowed: 104.609752335437078857 * 1e18,
                auctionPrice:      0.607580991564486240 * 1e18,
                debtInAuction:     9_227.427616572825121949 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    104.609752335437078857 * 1e18 // locked bond + reward, auction is not yet finalized
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              9_227.427616572825121949 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 0
            }
        );
        // clear remaining debt
        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   5,
                healedDebt: 9_227.427616572825121949 * 1e18
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
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 104.609752335437078857 * 1e18,
                locked:    0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        9.588542815647469183 * 1e18,
                borrowerCollateralization: 1 * 1e18
            }
        );

        // kicker withdraws his auction bonds
        assertEq(_quote.balanceOf(_lender), 46_293.885066015721543543 * 1e18);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 46_398.494818351158622400 * 1e18);
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0
            }
        );
    }

    function testTakeReverts() external {

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

        skip(2 hours);

        // 10 borrowers draw debt to enable the min debt check
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_000 * 1e18, 6_000 * 1e18, 7777);
        }        
        // should revert if auction leaves borrower with debt under minimum pool debt
        _assertTakeDebtUnderMinPoolDebtRevert(
            {
                from:          _lender,
                borrower:      _borrower,
                maxCollateral: 0.1 * 1e18
            }
        );
    }

    function testLenderForcedExit() external {

        skip(25 hours);
        
        // Lender attempts to withdraw entire position
        _removeLiquidity(
            {
                from:     _lender,
                amount:   2_000.00 * 1e18,
                index:    _i9_91,
                penalty:  0,
                newLup:   9.721295865031779605 * 1e18,
                lpRedeem: 1999891367962935869240493669537
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   5_000 * 1e18,
                index:    _i9_81,
                penalty:  0,
                newLup:   9.721295865031779605 * 1e18,
                lpRedeem: 4999728419907339673101234173842
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   2_992.8 * 1e18,
                index:    _i9_72,
                penalty:  0,
                newLup:   9721295865031779605,
                lpRedeem: 2992637443019737234731474727095
            }
        );

        // Lender amount to withdraw is restricted by HTP 
        _assertRemoveAllLiquidityLupBelowHtpRevert(
            {
                from:     _lender,
                index:    _i9_72
            }
        );

        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    8_007.362556980262765268525272905 * 1e27, 
                collateral:   0,
                deposit:      8_007.797508658144068000 * 1e18,
                exchangeRate: 1.000054318968922188000000000 * 1e27
            }
        );

        skip(16 hours);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower,
                debt:       19.489662805046791054 * 1e18,
                collateral: 2 * 1e18,
                bond:       0.192728433177224139 * 1e18
            }
        );

        _assertBucket(
            {
                index:        _i9_72,
                lpBalance:    8_007.362556980262765268525272905 * 1e27,
                collateral:   0,          
                deposit:      8_008.361347558277120605 * 1e18,
                exchangeRate: 1.000124734027079076000086027 * 1e27
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.192728433177224139 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.624807173121239337 * 1e18,
                totalBondEscrowed: 0.192728433177224139 * 1e18,
                auctionPrice:      307.993829539879658784 * 1e18,
                debtInAuction:     19.489662805046791054 * 1e18
            })
        );

        // lender cannot withdraw
        _assertRemoveDepositLockedByAuctionDebtRevert(
            {
                from:     _lender,
                amount:   10.0 * 1e18,
                index:    _i9_72
            }
        );

        skip(3 hours);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.489933125874732298 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowerMompFactor:        9.917184843435912074 * 1e18,
                borrowerCollateralization: 0.987669594447545452 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2.0 * 1e18,
                bondChange:      0.192728433177224139 * 1e18,
                givenAmount:     19.489933125874732298 * 1e18,
                collateralTaken: 0.253121085639816517 * 1e18,
                isReward:        false
            }
        );
        
        // Borrower is removed from auction, keeps collateral in system
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

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1.746878914360183483 * 1e18,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  7.991488192808991114 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             63_008.836766669707728354 * 1e18,
                pledgedCollateral:    1_001.746878914360183483 * 1e18,
                encumberedCollateral: 821.863722498661263922 * 1e18,
                poolDebt:             7_989.580407145861717463 * 1e18,
                actualUtilization:    0.126800950741756503 * 1e18,
                targetUtilization:    0.826474536317057937 * 1e18,
                minDebtAmount:        798.958040714586171746 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 3 hours
            })
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   8_008.373442262808822463 * 1e18,
                index:    _i9_72,
                penalty:  0,
                newLup:   9.624807173121239337 * 1e18,
                lpRedeem: 8_007.362556980262765268525272905 * 1e27
            }
        );
        
        _assertBucket(
        {
                index:        _i9_72,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0.000000000000002445 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   25_000.037756489769875000 * 1e18,
                index:    _i9_62,
                penalty:  0,
                newLup:   9.529276179422528643 * 1e18,
                lpRedeem: 25_000.00 * 1e27
            }
        );

        _assertBucket(
        {
                index:        _i9_62,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   22_010.045307787723850000 * 1e18,
                penalty:  0,
                index:    _i9_52,
                newLup:   9.529276179422528643 * 1e18,
                lpRedeem: 22_010.012066955906216160936672387 * 1e27
            }
        );

        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    7_989.987933044093783839063327613 * 1e27,
                collateral:   0,          
                deposit:      7_990.0 * 1e18,
                exchangeRate: 1.000001510259590795000000000 * 1e27
            }
        );

        _assertRemoveAllLiquidityLupBelowHtpRevert({
            from:  _lender,
            index: _i9_52
        });

        skip(25 hours);

        _assertPool(
            PoolState({
                htp:                  7.991488192808991114 * 1e18,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             7_990.380260129405180891 * 1e18,
                pledgedCollateral:    1_001.746878914360183483 * 1e18,
                encumberedCollateral: 80036071881.142911713937910614 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    1.000015475308649579 * 1e18,
                targetUtilization:    0.826474536317057937 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   block.timestamp - 28 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              7_990.503913730158190391 * 1e18,
                borrowerCollateral:        1_000.00 * 1e18,
                borrowerMompFactor:        9.818751856078723036 * 1e18,
                borrowerCollateralization: 0.000000012494366309 * 1e18
            }
        );

        _moveCollateral({
            from:         _lender,
            amount:       0,
            fromIndex:    123,
            toIndex:      1000,
            lpRedeemFrom: 0,
            lpRedeemTo:   0
        });

        _assertPool(
            PoolState({
                htp:                  7.993335753787741967 * 1e18,
                lup:                  9.529276179422528643 * 1e18,
                poolSize:             7_991.297334721700255725 * 1e18,
                pledgedCollateral:    1_001.746878914360183483 * 1e18,
                encumberedCollateral: 838.521600516187410670 * 1e18,
                poolDebt:             7_990.503913730158190391 * 1e18,
                actualUtilization:    0.999900714369856482 * 1e18,
                targetUtilization:    0.830320609473953071 * 1e18,
                minDebtAmount:        799.050391373015819039 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.04455 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        skip(117 days);

        _kick(
            {
                from:       _lender,
                borrower:   _borrower2,
                debt:       8_195.704467159075241912 * 1e18,
                collateral: 1_000.0 * 1e18,
                bond:       81.054302378846351183 * 1e18
            }
        );

        _assertRemoveDepositLockedByAuctionDebtRevert(
            {
                from:   _lender,
                amount: 10.0 * 1e18,
                index:  _i9_52
            }
        );

        skip(10 hours);

        _take(
            {
                from:            _lender,
                borrower:        _borrower2,
                maxCollateral:   1_000.0 * 1e18,
                bondChange:      0,
                givenAmount:     0,
                collateralTaken: 1_000.0 * 1e18,
                isReward:        true
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             8_105.800538156165693723 * 1e18,
                pledgedCollateral:    1.746878914360183483 * 1e18,
                encumberedCollateral: 82_095_199_864.949941479526972802 * 1e18,
                poolDebt:             8_196.079597628232153239 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.174755075706248551 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              8_196.079597628232153239 * 1e18,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerCollateralization: 0
            }
        );

        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 7_990.0 * 1e18,
            index:  _i9_52
        });

        _heal(
            {
                from:       _lender,
                borrower:   _borrower2,
                maxDepth:   5,
                healedDebt: 8_196.079597628232153239 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  1_004_968_987.606512354182109771 * 1e18,
                poolSize:             9.176155018749408974 * 1e18,
                pledgedCollateral:    1.746878914360183483 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1.174755075706248551 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    7_989.987933044093783839063327613 * 1e27,
                collateral:   0,          
                deposit:      9.176155018749414998 * 1e18,
                exchangeRate: 1_148_456.680491306468833172 * 1e18
            }
        );

        _removeLiquidity(
            {
                from:     _lender,
                amount:   9.176155018749414998 * 1e18,
                penalty:  0,
                index:    _i9_52,
                newLup:   1_004_968_987.606512354182109771 * 1e18,
                lpRedeem: 7_989.987933044093783839063327613 * 1e27
            }
        );

        _assertBucket(
            {
                index:        _i9_52,
                lpBalance:    0,
                collateral:   0,          
                deposit:      0.000000000000000004 * 1e18,
                exchangeRate: 1000000000.0 * 1e18
            }
        );


        _pullCollateral(_borrower, 1.746878914360183483 * 1e18);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1.0 * 1e18
            }
        );

        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  1_004_968_987.606512354182109771 * 1e18,
                poolSize:             0,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1.174755075706248551 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.04009500000000000 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );
    }

}