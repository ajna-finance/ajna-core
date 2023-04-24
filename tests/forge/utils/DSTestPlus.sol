// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@std/Test.sol';
import '@std/Vm.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/interfaces/pool/commons/IPoolEvents.sol';
import 'src/interfaces/pool/IERC3156FlashBorrower.sol';
import 'src/PoolInfoUtils.sol';

import { _auctionPrice, _bpf, MAX_PRICE } from 'src/libraries/helpers/PoolHelper.sol';

abstract contract DSTestPlus is Test, IPoolEvents {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // nonce for generating random addresses
    uint256 internal _nonce = 0;

    // mainnet address of AJNA token, because tests are forked
    address internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /*************/
    /*** Pools ***/
    /*************/

    IPool             internal _pool;
    PoolInfoUtils     internal _poolUtils;
    uint256           internal _startTime;

    uint256 internal _p1505_26  = 1_505.263728469068226832 * 1e18;
    uint256 internal _p1004_98  = 1_004.989662429170775094 * 1e18;
    uint256 internal _p236_59   = 236.593977318257012077 * 1e18;
    uint256 internal _p100_33   = 100.332368143282009890 * 1e18;
    uint256 internal _p9_91     = 9.917184843435912074 * 1e18;
    uint256 internal _p9_81     = 9.818751856078723036 * 1e18;
    uint256 internal _p9_72     = 9.721295865031779605 * 1e18;
    uint256 internal _p9_62     = 9.624807173121239337 * 1e18;
    uint256 internal _p9_52     = 9.529276179422528643 * 1e18;

    uint256 internal _i49910    = 1987;
    uint256 internal _i10016    = 2309;
    uint256 internal _i1505_26  = 2689;
    uint256 internal _i1004_98  = 2770;
    uint256 internal _i236_59   = 3060;
    uint256 internal _i100_33   = 3232;
    uint256 internal _i9_91     = 3696;
    uint256 internal _i9_81     = 3698;
    uint256 internal _i9_72     = 3700;
    uint256 internal _i9_62     = 3702;
    uint256 internal _i9_52     = 3704;

    struct PoolParams {
        uint256 htp;
        uint256 lup;
        uint256 poolSize;
        uint256 pledgedCollateral;
        uint256 encumberedCollateral;
        uint256 poolDebt;
        uint256 actualUtilization;
        uint256 targetUtilization;
        uint256 minDebtAmount;
        uint256 loans;
        address maxBorrower;
        uint256 interestRate;
        uint256 interestRateUpdate;
    }

    struct AuctionParams {
        address borrower;
        bool    active;
        address kicker;
        uint256 bondSize;
        uint256 bondFactor;
        uint256 kickTime;
        uint256 kickMomp;
        uint256 totalBondEscrowed;
        uint256 auctionPrice;
        uint256 debtInAuction;
        uint256 thresholdPrice;
        uint256 neutralPrice;
    }

    mapping(address => EnumerableSet.UintSet) lendersDepositedIndex;
    EnumerableSet.AddressSet lenders;
    EnumerableSet.AddressSet borrowers;
    EnumerableSet.UintSet bucketsUsed;

    function _registerLender(
        address lender,
        uint256[] memory indexes
    ) internal {
        lenders.add(lender);
        for (uint256 i = 0; i < indexes.length; i++) {
            lendersDepositedIndex[lender].add(indexes[i]);
        }
    }

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    // Adds liquidity to a pool which has no debt drawn and a bucket with exchange rate of 1
    function _addInitialLiquidity(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        uint256 quoteTokenScale = IPool(address(_pool)).quoteTokenScale();
        uint256 lpAmount        = (amount / quoteTokenScale) * quoteTokenScale;
        _addLiquidity(from, amount, index, lpAmount, MAX_PRICE);
    }

    // Adds liquidity with interest rate update
    function _addLiquidityNoEventCheck(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        _pool.addQuoteToken(amount, index, type(uint256).max);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);
    }

    function _addLiquidity(
        address from,
        uint256 amount,
        uint256 index,
        uint256 lpAward,
        uint256 newLup
    ) internal {
        _addLiquidityWithPenalty(from, amount, amount, index, lpAward, newLup);
    }

    function _addLiquidityWithPenalty(
        address from,
        uint256 amount,
        uint256 amountAdded,    // amount less penalty, where applicable
        uint256 index,
        uint256 lpAward,
        uint256 newLup
    ) internal {
        uint256 quoteTokenScale = IPool(address(_pool)).quoteTokenScale();
        changePrank(from);

        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(from, index, (amountAdded / quoteTokenScale) * quoteTokenScale, lpAward, newLup);
        _assertQuoteTokenTransferEvent(from, address(_pool), amount);
        _pool.addQuoteToken(amount, index, type(uint256).max);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);
    }

    function _arbTake(
        address from,
        address borrower,
        address kicker,
        uint256 index,
        uint256 collateralArbed,
        uint256 quoteTokenAmount,
        uint256 bondChange,
        bool    isReward,
        uint256 lpAwardTaker,
        uint256 lpAwardKicker
    ) internal virtual {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit BucketTakeLPAwarded(from, kicker, lpAwardTaker, lpAwardKicker);
        vm.expectEmit(true, true, false, true);
        emit BucketTake(borrower, index, quoteTokenAmount, collateralArbed, bondChange, isReward);
        _pool.bucketTake(borrower, false, index);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);
    }

    function _depositTake(
        address from,
        address borrower,
        address kicker,
        uint256 index,
        uint256 collateralArbed,
        uint256 quoteTokenAmount,
        uint256 bondChange,
        bool    isReward,
        uint256 lpAwardTaker,
        uint256 lpAwardKicker
    ) internal virtual {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit BucketTakeLPAwarded(from, kicker, lpAwardTaker, lpAwardKicker);
        vm.expectEmit(true, true, false, true);
        emit BucketTake(borrower, index, quoteTokenAmount, collateralArbed, bondChange, isReward);
        _depositTake(from, borrower, index);
    }

    function _depositTake(
        address from,
        address borrower,
        uint256 index
    ) internal virtual {
        changePrank(from);
        _pool.bucketTake(borrower, true, index);
    }

    function _settle(
        address from,
        address borrower,
        uint256 maxDepth,
        uint256 settledDebt
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Settle(borrower, settledDebt);
        _pool.settle(borrower, maxDepth);

        // Added for tearDown
        // Borrowers may receive LP in 7388 during settle if 0 deposit in book
        lenders.add(borrower);
        lendersDepositedIndex[borrower].add(7388);
        bucketsUsed.add(7388);
    }

    function _kick(
        address from,
        address borrower,
        uint256 debt,
        uint256 collateral,
        uint256 bond,
        uint256 transferAmount
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Kick(borrower, debt, collateral, bond);
        if (transferAmount != 0) _assertQuoteTokenTransferEvent(from, address(_pool), transferAmount);
        _pool.kick(borrower, MAX_FENWICK_INDEX);
    }

    function _kickWithDeposit(
        address from,
        uint256 index,
        address borrower,
        uint256 debt,
        uint256 collateral,
        uint256 bond,
        uint256 removedFromDeposit,
        uint256 transferAmount,
        uint256 lup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Kick(borrower, debt, collateral, bond);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(from, index, removedFromDeposit, removedFromDeposit, lup);
        if (transferAmount != 0) _assertQuoteTokenTransferEvent(from, address(_pool), transferAmount);
        _pool.kickWithDeposit(index, MAX_FENWICK_INDEX);
    }

    function _moveLiquidity(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 lpRedeemFrom,
        uint256 lpAwardTo,
        uint256 newLup
    ) internal {
        _moveLiquidityWithPenalty(from, amount, amount, fromIndex, toIndex, lpRedeemFrom, lpAwardTo, newLup);
    }

    function _moveLiquidityWithPenalty(
        address from,
        uint256 amount,
        uint256 amountMoved,    // amount less penalty, where applicable
        uint256 fromIndex,
        uint256 toIndex,
        uint256 lpRedeemFrom,
        uint256 lpAwardTo,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(from, fromIndex, toIndex, amountMoved, lpRedeemFrom, lpAwardTo, newLup);
        (uint256 lpbFrom, uint256 lpbTo, ) = _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
        assertEq(lpbFrom, lpRedeemFrom);
        assertEq(lpbTo,   lpAwardTo);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(toIndex);
        bucketsUsed.add(toIndex);
    }

    function _removeAllLiquidity(
        address from,
        uint256 amount,
        uint256 index,
        uint256 newLup,
        uint256 lpRedeem
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(from, index, amount, lpRedeem, newLup);
        _assertQuoteTokenTransferEvent(address(_pool), from, amount);
        (uint256 removedAmount, uint256 lpRedeemed) = _pool.removeQuoteToken(type(uint256).max, index);
        assertEq(removedAmount, amount);
        assertEq(lpRedeemed,    lpRedeem);
    }

    function _removeCollateral(
        address from,
        uint256 amount,
        uint256 index,
        uint256 lpRedeem
    ) internal virtual returns (uint256 lpRedeemed_) {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(from, index, amount, lpRedeem);
        _assertCollateralTokenTransferEvent(address(_pool), from, amount);
        (, lpRedeemed_) = _pool.removeCollateral(amount, index);
        assertEq(lpRedeemed_, lpRedeem);
    }

    function _removeCollateralWithoutLPCheck(
        address from,
        uint256 amount,
        uint256 index
    ) internal virtual returns (uint256 lpRedeemed_) {
        changePrank(from);
        _assertCollateralTokenTransferEvent(address(_pool), from, amount);
        (, lpRedeemed_) = _pool.removeCollateral(amount, index);
    }

    function _removeLiquidity(
        address from,
        uint256 amount,
        uint256 index,
        uint256 newLup,
        uint256 lpRedeem
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(from, index, amount, lpRedeem, newLup);
        _assertQuoteTokenTransferEvent(address(_pool), from, amount);
        (uint256 removedAmount, uint256 lpRedeemed) = _pool.removeQuoteToken(amount, index);
        assertEq(removedAmount, amount);
        assertEq(lpRedeemed,    lpRedeem);
    }

    function _kickReserveAuction(
        address from,
        uint256 remainingReserves,
        uint256 price,
        uint256 epoch
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit KickReserveAuction(remainingReserves, price, epoch);
        _pool.kickReserveAuction();
    }

    function _take(
        address from,
        address borrower,
        uint256 maxCollateral,
        uint256 bondChange,
        uint256 givenAmount,
        uint256 collateralTaken,
        bool isReward
    ) internal virtual {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Take(borrower, givenAmount, collateralTaken, bondChange, isReward);
        _assertQuoteTokenTransferEvent(from, address(_pool), givenAmount);
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _takeReserves(
        address from,
        uint256 amount,
        uint256 remainingReserves,
        uint256 price,
        uint256 epoch
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(remainingReserves, price, epoch);
        _pool.takeReserves(amount);
    }

    function _updateInterest() internal {
        _pool.updateInterest();
    }

    function _assertQuoteTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        // to be overidden by ERC20 helper 
    }

    function _assertCollateralTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        // to be overidden by ERC20 helper 
    }

    /*********************/
    /*** State asserts ***/
    /*********************/

    struct AuctionLocalVars {
        address auctionKicker;
        uint256 auctionBondFactor;
        uint256 auctionBondSize;
        uint256 auctionKickTime;
        uint256 auctionKickMomp;
        uint256 auctionNeutralPrice;
        uint256 auctionTotalBondEscrowed;
        uint256 auctionDebtInAuction;
        uint256 borrowerThresholdPrice;
    }

    function _assertAuction(AuctionParams memory state_) internal {
        AuctionLocalVars memory vars;
        (
            vars.auctionKicker,
            vars.auctionBondFactor,
            vars.auctionBondSize,
            vars.auctionKickTime,
            vars.auctionKickMomp,
            vars.auctionNeutralPrice,
            ,
            ,
            ,
        ) = _pool.auctionInfo(state_.borrower);

        (uint256 borrowerDebt, uint256 borrowerCollateral , ) = _poolUtils.borrowerInfo(address(_pool), state_.borrower);
        (, uint256 lockedBonds) = _pool.kickerInfo(state_.kicker);
        (vars.auctionTotalBondEscrowed,,,) = _pool.reservesInfo();
        (,, vars.auctionDebtInAuction,)  = _pool.debtInfo(); 
        vars.borrowerThresholdPrice = borrowerCollateral > 0 ? borrowerDebt * Maths.WAD / borrowerCollateral : 0;

        assertEq(vars.auctionKickTime != 0,     state_.active);
        assertEq(vars.auctionKicker,            state_.kicker);
        assertGe(lockedBonds,                   vars.auctionBondSize);
        assertEq(vars.auctionBondSize,          state_.bondSize);
        assertEq(vars.auctionBondFactor,        state_.bondFactor);
        assertEq(vars.auctionKickTime,          state_.kickTime);
        assertEq(vars.auctionKickMomp,          state_.kickMomp);
        assertEq(vars.auctionTotalBondEscrowed, state_.totalBondEscrowed);
        assertEq(_auctionPrice(
            vars.auctionKickMomp,
            vars.auctionNeutralPrice,
            vars.auctionKickTime),              state_.auctionPrice);
        assertEq(vars.auctionDebtInAuction,     state_.debtInAuction);
        assertEq(vars.auctionNeutralPrice,      state_.neutralPrice);
        assertEq(vars.borrowerThresholdPrice,   state_.thresholdPrice);

        (
            uint256 kickTime, 
            uint256 collateral, 
            uint256 debtToCover, 
            bool    isCollateralized,      
            uint256 price,          
            uint256 neutralPrice    
        ) = _poolUtils.auctionStatus(address(_pool), state_.borrower);
        assertEq(kickTime,     state_.kickTime);
        assertEq(neutralPrice, state_.neutralPrice);
        if (kickTime == 0) {
            assertEq(collateral,  0);
            assertEq(debtToCover, 0);
            assertEq(price,       0);
        } else {
            assertEq(collateral,       borrowerCollateral);
            assertEq(debtToCover,      borrowerDebt);
            assertEq(isCollateralized, _isCollateralized(
                borrowerDebt, 
                borrowerCollateral, 
                _lup(), 
                _pool.poolType())
            );
            assertEq(price,            state_.auctionPrice);
        }
    }

    function _assertPool(PoolParams memory state_) internal {
        ( 
            , 
            , 
            uint256 htp, 
            , 
            uint256 lup, 
        ) = _poolUtils.poolPricesInfo(address(_pool));
        (
            uint256 poolSize,
            uint256 loansCount,
            address maxBorrower,
            uint256 pendingInflator,
        ) = _poolUtils.poolLoansInfo(address(_pool));
        (
            uint256 poolMinDebtAmount, 
            , 
            uint256 poolActualUtilization, 
            uint256 poolTargetUtilization
        ) = _poolUtils.poolUtilizationInfo(address(_pool));

        (uint256 poolDebt,,,) = _pool.debtInfo();

        assertEq(htp, state_.htp);
        assertEq(lup, state_.lup);

        assertEq(poolSize,                   state_.poolSize);
        assertEq(_pool.pledgedCollateral(),  state_.pledgedCollateral);
        assertEq(
            _encumberance(
                state_.poolDebt,
                state_.lup
            ),                               state_.encumberedCollateral
        );
        assertEq(poolDebt,                   state_.poolDebt);
        assertEq(poolActualUtilization,      state_.actualUtilization);
        assertEq(poolTargetUtilization,      state_.targetUtilization);
        assertEq(poolMinDebtAmount,          state_.minDebtAmount);

        assertEq(loansCount,  state_.loans);
        assertEq(maxBorrower, state_.maxBorrower);

        (uint256 poolInflator, ) = _pool.inflatorInfo();
        assertGe(poolInflator,    1e18);
        assertGe(pendingInflator, poolInflator);

        (uint256 interestRate, uint256 interestRateUpdate) = _pool.interestRateInfo();
        assertEq(interestRate,       state_.interestRate);
        assertEq(interestRateUpdate, state_.interestRateUpdate);
    }

    function _assertLenderLpBalance(
        address lender,
        uint256 index,
        uint256 lpBalance,
        uint256 depositTime
    ) internal {
        (uint256 curLpBalance, uint256 time) = _pool.lenderInfo(index, lender);
        assertEq(curLpBalance, lpBalance);
        assertEq(time,       depositTime);
    }

    function _assertBucket(
        uint256 index,
        uint256 lpBalance,
        uint256 collateral,
        uint256 deposit,
        uint256 exchangeRate
    ) internal {
        (
            ,
            uint256 curDeposit,
            uint256 availableCollateral,
            uint256 lpAccumulator,
            ,
            uint256 rate
        ) = _poolUtils.bucketInfo(address(_pool), index);
        assertEq(lpAccumulator,       lpBalance);
        assertEq(availableCollateral, collateral);
        assertEq(curDeposit,          deposit);
        assertEq(rate,                exchangeRate);

        _validateBucketLp(index, lpBalance);
        _validateBucketQuantities(index);
    }

    function _validateBucketLp(
        uint256 index,
        uint256 lpBalance
    ) internal {
        uint256 lenderLps = 0;

        uint256 curLpBalance;
        // sum up LP across lenders
        for (uint i = 0; i < lenders.length(); i++ ){
            (curLpBalance, ) = _pool.lenderInfo(index, lenders.at(i));
            lenderLps += curLpBalance;
        }
        // handle borrowers awarded LP from liquidation
        for (uint i = 0; i < borrowers.length(); i++ ){
            address borrower = borrowers.at(i);
            if (!lenders.contains(borrower)) {
                (curLpBalance, ) = _pool.lenderInfo(index, borrowers.at(i));
                lenderLps += curLpBalance;
            }
        }

        assertEq(lenderLps, lpBalance);
    }

    function _validateBucketQuantities(
        uint256 index
    ) internal {
        (
            ,
            uint256 curDeposit,
            uint256 availableCollateral,
            uint256 lpAccumulator,
            ,
        ) = _poolUtils.bucketInfo(address(_pool), index);
        if (lpAccumulator == 0) {
            assertEq(curDeposit, 0);
            assertEq(availableCollateral, 0);
        } else {
            assertTrue(curDeposit != 0 || availableCollateral != 0);
        }
    }

    function _assertBorrower(
        address borrower,
        uint256 borrowerDebt,
        uint256 borrowerCollateral,
        uint256 borrowert0Np,
        uint256 borrowerCollateralization
    ) internal {
        (
            uint256 debt,
            uint256 col,
            uint256 t0Np
        ) = _poolUtils.borrowerInfo(address(_pool), borrower);

        uint256 lup = _poolUtils.lup(address(_pool));

        assertEq(debt,        borrowerDebt);
        assertEq(col,         borrowerCollateral);
        assertEq(t0Np,        borrowert0Np);
        assertEq(
            _collateralization(
                borrowerDebt,
                borrowerCollateral,
                lup
            ),
            borrowerCollateralization
        );
    }

    function _assertEMAs(
        uint256 debtColEma,
        uint256 lupt0DebtEma,
        uint256 debtEma,
        uint256 depositEma
    ) internal {
        (uint256 curDebtColEma, uint256 curLupt0DebtEma, uint256 curDebtEma, uint256 curDepositEma) = _pool.emasInfo();

        assertEq(curDebtColEma,    debtColEma);
        assertEq(curLupt0DebtEma,  lupt0DebtEma);
        assertEq(curDebtEma,       debtEma);
        assertEq(curDepositEma,    depositEma);
    }

    function _assertKicker(
        address kicker,
        uint256 claimable,
        uint256 locked
    ) internal {
        (uint256 curClaimable, uint256 curLocked) = _pool.kickerInfo(kicker);

        assertEq(curClaimable, claimable);
        assertEq(curLocked,    locked);
    }

    function _assertLenderInterest(
        uint256 liquidityAdded,
        uint256 lenderInterest
    ) internal {
        (uint256 poolSize, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize - liquidityAdded, lenderInterest);
    }

    function _assertLpAllowance(
        address owner,
        address spender,
        uint256 index,
        uint256 lpAllowance
    ) internal {
        assertEq(_pool.lpAllowance(index, spender, owner), lpAllowance);
    }

    function _assertLoans(
        uint256 noOfLoans,
        address maxBorrower,
        uint256 maxThresholdPrice
    ) internal {
        (address curMaxBorrower, uint256 curTpPrice, uint256 curNoOfLoans) = _pool.loansInfo();
        assertEq(curNoOfLoans,   noOfLoans);
        assertEq(curMaxBorrower, maxBorrower);
        assertEq(curTpPrice,     maxThresholdPrice);
    }

    function _assertPoolPrices(
        uint256 hpb,
        uint256 hpbIndex,
        uint256 htp,
        uint256 htpIndex,
        uint256 lup,
        uint256 lupIndex
    ) internal {
        (
            uint256 curHpb,
            uint256 curHpbIndex,
            uint256 curHtp,
            uint256 curHtpIndex,
            uint256 curLup,
            uint256 curLupIndex
        ) = _poolUtils.poolPricesInfo(address(_pool));
        assertEq(curHpb,      hpb);
        assertEq(curHpbIndex, hpbIndex);
        assertEq(curHtp,      htp);
        assertEq(curHtpIndex, htpIndex);
        assertEq(curLup,      lup);
        assertEq(curLupIndex, lupIndex);
    }

    function _assertReserveAuction(
            uint256 reserves,
            uint256 claimableReserves,
            uint256 claimableReservesRemaining,
            uint256 auctionPrice,
            uint256 timeRemaining
    ) internal {
        (
            uint256 curReserves,
            uint256 curClaimableReserves,
            uint256 curClaimableReservesRemaining,
            uint256 curAuctionPrice,
            uint256 curTimeRemaining
        ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(curReserves, reserves);
        assertEq(curClaimableReserves, claimableReserves);
        assertEq(curClaimableReservesRemaining, claimableReservesRemaining);
        assertEq(curAuctionPrice, auctionPrice);
        assertEq(curTimeRemaining, timeRemaining);
    }

    function _assertReserveAuctionPrice(
        uint256 expectedPrice_
    ) internal {
        ( , , , uint256 auctionPrice, ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(auctionPrice, expectedPrice_);
    }

    function _assertReserveAuctionTooSoon() internal {
        vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        _pool.kickReserveAuction();
    }

    /**********************/
    /*** Revert asserts ***/
    /**********************/

    function _assertAddLiquidityBankruptcyBlockRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('BucketBankruptcyBlock()'));
        _pool.addQuoteToken(amount, index, type(uint256).max);
    }

    function _assertAddLiquidityAtIndex0Revert(
        address from,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.addQuoteToken(amount, 0, type(uint256).max);
    }

    function _assertAddLiquidityDustRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        _pool.addQuoteToken(amount, index, type(uint256).max);
    }

    function _assertAddLiquidityExpiredRevert(
        address from,
        uint256 amount,
        uint256 index,
        uint256 expiry
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.TransactionExpired.selector);
        _pool.addQuoteToken(amount, index, expiry);
    }

    function _assertArbTakeNoAuction(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('NoAuction()'));
        _pool.bucketTake(borrower, false, index);
    }

    function _assertArbTakeAuctionInCooldownRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('TakeNotPastCooldown()'));
        _pool.bucketTake(borrower, false, index);
    }

    function _assertArbTakeAuctionInsufficientLiquidityRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        _pool.bucketTake(borrower,false, index);
    }

    function _assertArbTakeAuctionPriceGreaterThanBucketPriceRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionPriceGtBucketPrice()'));
        _pool.bucketTake(borrower, false, index);
    }

    function _assertArbTakeDebtUnderMinPoolDebtRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        _pool.bucketTake(borrower, false, index);
    }

    function _assertArbTakeInsufficentCollateralRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        _pool.bucketTake(borrower, false, index);
    }

    function _assertArbTakeNoAuctionRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('NoAuction()'));
        _pool.bucketTake(borrower, false, index);
    }

    function _assertDepositTakeAuctionInCooldownRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('TakeNotPastCooldown()'));
        _pool.bucketTake(borrower, true, index);
    }

    function _assertDepositTakeAuctionInsufficientLiquidityRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        _pool.bucketTake(borrower, true, index);
    }

    function _assertDepositTakeAuctionPriceGreaterThanBucketPriceRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionPriceGtBucketPrice()'));
        _pool.bucketTake(borrower, true, index);
    }

    function _assertDepositTakeDebtUnderMinPoolDebtRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        _pool.bucketTake(borrower, true, index);
    }

    function _assertDepositTakeInsufficentCollateralRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        _pool.bucketTake(borrower, true, index);
    }

    function _assertDepositTakeNoAuctionRevert(
        address from,
        address borrower,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('NoAuction()'));
        _pool.bucketTake(borrower, true, index);
    }

    function _assertStampLoanAuctionActiveRevert(
        address borrower
    ) internal {
        changePrank(borrower);
        vm.expectRevert(IPoolErrors.AuctionActive.selector);
        _pool.stampLoan();
    }

    function _assertStampLoanBorrowerUnderCollateralizedRevert(
        address borrower
    ) internal {
        changePrank(borrower);
        vm.expectRevert(IPoolErrors.BorrowerUnderCollateralized.selector);
        _pool.stampLoan();
    }

    function _assertBorrowAuctionActiveRevert(
        address from,
        uint256,
        uint256
    ) internal virtual {
        // to be overidden by ERC20/ERC721DSTestPlus 
    }

    function _assertBorrowBorrowerNotSenderRevert(
        address from,
        address borrower,
        uint256,
        uint256
    ) internal virtual {
        // to be overidden by ERC20/ERC721DSTestPlus 
    }

    function _assertBorrowLimitIndexRevert(
        address from,
        uint256,
        uint256
    ) internal virtual {
        // to be overidden by ERC20/ERC721DSTestPlus 
    }

    function _assertBorrowBorrowerUnderCollateralizedRevert(
        address from,
        uint256,
        uint256
    ) internal virtual {
        // to be overidden by ERC20/ERC721DSTestPlus 
    }

    function _assertBorrowMinDebtRevert(
        address from,
        uint256,
        uint256
    ) internal virtual {
        // to be overidden by ERC20/ERC721DSTestPlus 
    }

    function _assertFlashloanFeeRevertsForToken(
        address token,
        uint256 amount
    ) internal {
        vm.expectRevert(abi.encodeWithSignature('FlashloanUnavailableForToken()'));
        _pool.flashFee(token, amount);
    }

    function _assertFlashloanTooLargeRevert(
        IERC3156FlashBorrower flashBorrower,
        address token,
        uint256 amount
    ) internal {
        changePrank(address(flashBorrower));
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        _pool.flashLoan(flashBorrower, token, amount, new bytes(0));
    }

    function _assertFlashloanUnavailableForToken(
        IERC3156FlashBorrower flashBorrower,
        address token,
        uint256 amount
    ) internal {
        changePrank(address(flashBorrower));
        vm.expectRevert(abi.encodeWithSignature('FlashloanUnavailableForToken()'));
        _pool.flashLoan(flashBorrower, token, amount, new bytes(0));
    }

    function _assertSettleOnNotClearableAuctionRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotClearable()'));
        _pool.settle(borrower, 1);
    }

    function _assertSettleOnNotKickedAuctionRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('NoAuction()'));
        _pool.settle(borrower, 1);
    }

    function _assertKickAuctionActiveRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionActive()'));
        _pool.kick(borrower, MAX_FENWICK_INDEX);
    }

    function _assertKickCollateralizedBorrowerRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerOk.selector);
        _pool.kick(borrower, MAX_FENWICK_INDEX);
    }

    function _assertKickNpUnderLimitRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        _pool.kick(borrower, 0);
    }

    function _assertKickWithDepositNpUnderLimitRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        _pool.kickWithDeposit(index, 0);
    }

    function _assertKickWithInsufficientLiquidityRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('InsufficientLiquidity()'));
        _pool.kickWithDeposit(index, MAX_FENWICK_INDEX);
    }

    function _assertKickWithBadProposedLupRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('BorrowerOk()'));
        _pool.kickWithDeposit(index, MAX_FENWICK_INDEX);
    }

    function _assertKickPriceBelowProposedLupRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('PriceBelowLUP()'));
        _pool.kickWithDeposit(index, MAX_FENWICK_INDEX);
    }

    function _assertRemoveCollateralAuctionNotClearedRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        _pool.removeCollateral(amount, index);
    }

    function _assertRemoveInsufficientCollateralRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        _pool.removeCollateral(amount, index);
    }

    function _assertRemoveLiquidityAuctionNotClearedRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        _pool.removeQuoteToken(amount, index);
    }

    function _assertRemoveLiquidityInsufficientLPRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLP.selector);
        _pool.removeQuoteToken(amount, index);
    }

    function _assertRemoveLiquidityLupBelowHtpRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        _pool.removeQuoteToken(amount, index);
    }

    function _assertRemoveInsufficientLiquidityRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        _pool.removeQuoteToken(amount, index);
    }

    function _assertRemoveAllLiquidityAuctionNotClearedRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        _pool.removeQuoteToken(type(uint256).max, index);
    }

    function _assertRemoveAllLiquidityLupBelowHtpRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        _pool.removeQuoteToken(type(uint256).max, index);
    }

    function _assertRemoveDepositLockedByAuctionDebtRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.RemoveDepositLockedByAuctionDebt.selector);
        _pool.removeQuoteToken(amount, index);
    }

    function _assertRemoveAllLiquidityNoClaimRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        _pool.removeQuoteToken(type(uint256).max, index);
    }

    function _assertMoveLiquidityBankruptcyBlockRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('BucketBankruptcyBlock()'));
        _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
    }

    function _assertMoveLiquidityLupBelowHtpRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
    }

    function _assertMoveLiquidityExpiredRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 expiry
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.TransactionExpired.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex, expiry);
    }

    function _assertMoveLiquidityDustRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
    }

    function _assertMoveLiquidityToSameIndexRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.MoveToSameIndex.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
    }

    function _assertMoveLiquidityToIndex0Revert(
        address from,
        uint256 amount,
        uint256 fromIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.moveQuoteToken(amount, fromIndex, 0, type(uint256).max);
    }

    function _assertMoveDepositLockedByAuctionDebtRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.RemoveDepositLockedByAuctionDebt.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max);
    }

    function _assertTakeAuctionInCooldownRevert(
        address from,
        address borrower,
        uint256 maxCollateral
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('TakeNotPastCooldown()'));
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _assertTakeDebtUnderMinPoolDebtRevert(
        address from,
        address borrower,
        uint256 maxCollateral
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _assertTakeInsufficentCollateralRevert(
        address from,
        address borrower,
        uint256 maxCollateral
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _assertTakeNoAuctionRevert(
        address from,
        address borrower,
        uint256 maxCollateral
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('NoAuction()'));
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _assertTakeReservesNoAuctionRevert(
        uint256 amount
    ) internal {
        vm.expectRevert(IPoolErrors.NoReservesAuction.selector);
        _pool.takeReserves(amount);
    }

    function _assertTakeReservesNoReservesRevert() internal {
        vm.expectRevert(IPoolErrors.NoReserves.selector);
        _pool.kickReserveAuction();
    }

    function _lup() internal view returns (uint256 lup_) {
        ( , , , , lup_, ) = _poolUtils.poolPricesInfo(address(_pool));
    }

    function _lupIndex() internal view returns (uint256 lupIndex_) {
        ( , , , , , lupIndex_ ) = _poolUtils.poolPricesInfo(address(_pool));
    }

    function _htp() internal view returns (uint256 htp_) {
        ( , , htp_, , , ) = _poolUtils.poolPricesInfo(address(_pool));
    }

    function _hpb() internal view returns (uint256 hpb_) {
        (hpb_, , , , , ) = _poolUtils.poolPricesInfo(address(_pool));
    }


    /********************/
    /*** Pool Depoyer ***/
    /********************/

    // Pool deployer events
    event PoolCreated(address pool_);


    /************************/
    /*** Position Manager ***/
    /************************/

    // PositionManager events
    event Burn(address indexed lender_, uint256 indexed price_);
    event MemorializePosition(address indexed lender_, uint256 tokenId_, uint256[] indexes_);
    event Mint(address indexed lender_, address indexed pool_, uint256 tokenId_);
    event MoveLiquidity(address indexed owner_, uint256 tokenId_, uint256 fromIndex_, uint256 toIndex_, uint256 lpRedeemedFrom_, uint256 lpAwardedTo_);
    event RedeemPosition(address indexed lender_, uint256 tokenId_, uint256[] indexes_);


    /******************************/
    /*** Test utility functions ***/
    /******************************/

    function _calculateLup(address pool_, uint256 debtAmount_) internal view returns (uint256 lup_) {
        IPool pool = IPool(pool_);

        uint256 lupIndex = pool.depositIndex(debtAmount_);
        lup_ = _priceAt(lupIndex); 
    }

    function setRandomSeed(uint256 seed) public {
        _nonce = seed;
    }

    function getNextNonce() public returns (uint256) {
        return _nonce == type(uint256).max ? 0 : ++_nonce;
    }

    function randomInRange(uint256 min, uint256 max) public returns (uint256) {
        return randomInRange(min, max, false);
    }

    function randomInRange(uint256 min, uint256 max, bool nonZero) public returns (uint256) {
        require(min <= max, "randomInRange bad inputs");
        if      (max == 0 && nonZero) return 1;
        else if (max == min)          return max;
        return uint256(keccak256(abi.encodePacked(msg.sender, getNextNonce()))) % (max - min + 1) + min;
    }

    // returns a random index between 1 and 7388
    function _randomIndex() internal returns (uint256 index_) {
        // calculate a random index between 1 and 7388
        index_ = 1 + uint256(keccak256(abi.encodePacked(msg.sender, getNextNonce()))) % 7387;
    }

    // returns a random index between 1 and a given maximum
    // used for testing in NFT pools where higher indexes (and lower prices) would require so many NFTs that gas and memory limits would be exceeded
    function _randomIndexWithMinimumPrice(uint256 minimumPrice_) internal returns (uint256 index_) {
        index_ = 1 + uint256(keccak256(abi.encodePacked(msg.sender, getNextNonce()))) % minimumPrice_;
    }

    // find the bucket index in array corresponding to the highest bucket price
    function _findHighestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 highestIndex_) {
        highestIndex_ = 7388;
        // highest index corresponds to lowest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] < highestIndex_) {
                highestIndex_ = indexes[i];
            }
        }
    }

    // find the bucket index in array corresponding to the lowest bucket price
    function _findLowestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 lowestIndex_) {
        lowestIndex_ = 1;
        // lowest index corresponds to highest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] > lowestIndex_) {
                lowestIndex_ = indexes[i];
            }
        }
    }

    // calculates a limit index leaving one index above the htp to accrue interest
    function _findSecondLowestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 secondLowestIndex_) {
        secondLowestIndex_ = 1;
        uint256 lowestIndex = secondLowestIndex_;

        // lowest index corresponds to highest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] > lowestIndex) {
                secondLowestIndex_ = lowestIndex;
                lowestIndex = indexes[i];
            }
            else if (indexes[i] > secondLowestIndex_) {
                secondLowestIndex_ = indexes[i];
            }
        }
    }

    // calculate required collateral to borrow a given amount at a given limitIndex
    function _requiredCollateral(uint256 borrowAmount, uint256 indexPrice) internal view returns (uint256 requiredCollateral_) {
        // calculate the required collateral based upon the borrow amount and index price
        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 newInterestRate = Maths.wmul(interestRate, 1.1 * 10**18); // interest rate multipled by increase coefficient
        uint256 expectedDebt = Maths.wmul(borrowAmount, _borrowFeeRate(newInterestRate) + Maths.WAD);
        requiredCollateral_ = Maths.wdiv(expectedDebt, _poolUtils.indexToPrice(indexPrice));
    }

    // calculate the fee that will be charged a borrower
    function _borrowFee() internal view returns (uint256 feeRate_) {
        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 newInterestRate = Maths.wmul(interestRate, 1.1 * 10**18); // interest rate multipled by increase coefficient
        // calculate the fee rate based upon the interest rate
        feeRate_ = _borrowFeeRate(newInterestRate) + Maths.WAD;
    }

}
