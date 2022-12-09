// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.14;

import '@std/Test.sol';
import '@std/Vm.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import 'src/base/interfaces/IPool.sol';
import 'src/base/PoolInfoUtils.sol';

import 'src/libraries/external/Auctions.sol';
import 'src/libraries/Maths.sol';


abstract contract DSTestPlus is Test {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    // mainnet address of AJNA token, because tests are forked
    address internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /*************/
    /*** Pools ***/
    /*************/

    // Pool events
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event BucketTake(address indexed borrower, uint256 index, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event Settle(address indexed borrower, uint256 settledDebt);
    event Kick(address indexed borrower_, uint256 debt_, uint256 collateral_, uint256 bond_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event MoveCollateral(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_);
    event PullCollateral(address indexed borrower_, uint256 amount_);
    event RemoveCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);
    event TransferLPTokens(address owner_, address newOwner_, uint256[] prices_, uint256 lpTokens_);
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);
    event ReserveAuction(uint256 claimableReservesRemaining_, uint256 auctionPrice_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    IPool         internal _pool;
    PoolInfoUtils internal _poolUtils;
    uint256       internal _startTime;

    uint256 internal _p1505_26  = 1_505.263728469068226832 * 1e18;
    uint256 internal _p100_33   = 100.332368143282009890 * 1e18;
    uint256 internal _p9_91     = 9.917184843435912074 * 1e18;
    uint256 internal _p9_81     = 9.818751856078723036 * 1e18;
    uint256 internal _p9_72     = 9.721295865031779605 * 1e18;
    uint256 internal _p9_62     = 9.624807173121239337 * 1e18;
    uint256 internal _p9_52     = 9.529276179422528643 * 1e18;

    uint256 internal _i1505_26  = 2689;
    uint256 internal _i49910    = 1987;
    uint256 internal _i10016    = 2309;
    uint256 internal _i100_33   = 3232;
    uint256 internal _i9_91     = 3696;
    uint256 internal _i9_81     = 3698;
    uint256 internal _i9_72     = 3700;
    uint256 internal _i9_62     = 3702;
    uint256 internal _i9_52     = 3704;

    struct PoolState {
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

    struct AuctionState {
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

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _addLiquidity(
        address from,
        uint256 amount,
        uint256 index,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(from, index, amount, newLup);
        _assertTokenTransferEvent(from, address(_pool), amount);
        _pool.addQuoteToken(amount, index);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);
    }

    function _arbTake(
        address from,
        address borrower,
        uint256 index,
        uint256 collateralArbed,
        uint256 quoteTokenAmount,
        uint256 bondChange,
        bool isReward
    ) internal virtual {
        changePrank(from);
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
        uint256 index,
        uint256 collateralArbed,
        uint256 quoteTokenAmount,
        uint256 bondChange,
        bool isReward
    ) internal virtual {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit BucketTake(borrower, index, quoteTokenAmount, collateralArbed, bondChange, isReward);
        _pool.bucketTake(borrower, true, index);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);
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
        if(transferAmount != 0) _assertTokenTransferEvent(from, address(_pool), transferAmount);
        _pool.kick(borrower);
    }

    function _moveLiquidity(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex,
        uint256 newLup,
        uint256 lpRedeemFrom,
        uint256 lpRedeemTo
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(from, fromIndex, toIndex, lpRedeemTo / 1e9, newLup);
        (uint256 lpbFrom, uint256 lpbTo) = _pool.moveQuoteToken(amount, fromIndex, toIndex);
        assertEq(lpbFrom, lpRedeemFrom);
        assertEq(lpbTo,   lpRedeemTo);

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
        // apply penalty if case
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(from, index, amount, newLup);
        _assertTokenTransferEvent(address(_pool), from, amount);
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
        emit RemoveCollateral(from, index, amount);
        _assertTokenTransferEvent(address(_pool), from, amount);
        (, lpRedeemed_) = _pool.removeCollateral(amount, index);
        assertEq(lpRedeemed_, lpRedeem);
    }

    function _removeLiquidity(
        address from,
        uint256 amount,
        uint256 index,
        uint256 penalty,
        uint256 newLup,
        uint256 lpRedeem
    ) internal {
        // apply penalty if case
        uint256 expectedWithdrawal = penalty != 0 ? Maths.wmul(amount, penalty) : amount;

        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(from, index, expectedWithdrawal, newLup);
        _assertTokenTransferEvent(address(_pool), from, expectedWithdrawal);
        (uint256 removedAmount, uint256 lpRedeemed) = _pool.removeQuoteToken(amount, index);
        assertEq(removedAmount, expectedWithdrawal);
        assertEq(lpRedeemed,    lpRedeem);
    }

    function _startClaimableReserveAuction(
        address from,
        uint256 remainingReserves,
        uint256 price
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(remainingReserves, price);
        _pool.startClaimableReserveAuction();
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
        _assertTokenTransferEvent(from, address(_pool), givenAmount);
        _pool.take(borrower, maxCollateral, from, new bytes(0));
    }

    function _takeReserves(
        address from,
        uint256 amount,
        uint256 remainingReserves,
        uint256 price
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(remainingReserves, price);
        _pool.takeReserves(amount);
    }

    function _assertTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        // to be overidden by ERC20 helper 
    }

    /*********************/
    /*** State asserts ***/
    /*********************/

    function _assertAuction(AuctionState memory state_) internal {
        (
            address auctionKicker,
            uint256 auctionBondFactor,
            uint256 auctionBondSize,
            uint256 auctionKickTime,
            uint256 auctionKickMomp,
            uint256 auctionNeutralPrice
        ) = _pool.auctionInfo(state_.borrower);

        (uint256 borrowerDebt, uint256 borrowerCollateral , ) = _poolUtils.borrowerInfo(address(_pool), state_.borrower);
        (, uint256 lockedBonds) = _pool.kickerInfo(state_.kicker);
        (uint256 auctionTotalBondEscrowed,,) = _pool.reservesInfo();
        (,,uint256 auctionDebtInAuction)  = _pool.debtInfo(); 
        uint256 borrowerThresholdPrice = borrowerCollateral > 0 ? borrowerDebt * Maths.WAD / borrowerCollateral : 0;

        assertEq(auctionKickTime != 0,     state_.active);
        assertEq(auctionKicker,            state_.kicker);
        assertGe(lockedBonds,              auctionBondSize);
        assertEq(auctionBondSize,          state_.bondSize);
        assertEq(auctionBondFactor,        state_.bondFactor);
        assertEq(auctionKickTime,          state_.kickTime);
        assertEq(auctionKickMomp,          state_.kickMomp);
        assertEq(auctionTotalBondEscrowed, state_.totalBondEscrowed);
        assertEq(auctionDebtInAuction,     state_.debtInAuction);
        assertEq(auctionNeutralPrice,      state_.neutralPrice);
        assertEq(borrowerThresholdPrice,   state_.thresholdPrice);
        assertEq(Auctions._auctionPrice(
            auctionKickMomp,
            auctionKickTime),              state_.auctionPrice);
    }

    function _assertPool(PoolState memory state_) internal {
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

        (uint256 poolDebt,,) = _pool.debtInfo();

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

        (uint256 poolInflatorSnapshot, ) = _pool.inflatorInfo();
        assertGe(poolInflatorSnapshot, 1e18);
        assertGe(pendingInflator,      poolInflatorSnapshot);

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
        uint256 debtEma,
        uint256 lupColEma
    ) internal {
        (uint256 curDebtEma, uint256 curLupColEma) = _pool.emasInfo();

        assertEq(curDebtEma,   debtEma);
        assertEq(curLupColEma, lupColEma);
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
        _pool.addQuoteToken(amount, index);
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

    function _assertBorrowAuctionActiveRevert(
        address from,
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
        _pool.kick(borrower);
    }

    function _assertKickCollateralizedBorrowerRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerOk.selector);
        _pool.kick(borrower);
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

    function _assertRemoveLiquidityInsufficientLPsRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLPs.selector);
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
        _pool.moveQuoteToken(amount, fromIndex, toIndex);
    }

    function _assertMoveLiquidityLupBelowHtpRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex);
    }

    function _assertMoveLiquidityToSamePriceRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.MoveToSamePrice.selector);
        _pool.moveQuoteToken(amount, fromIndex, toIndex);
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
        _pool.startClaimableReserveAuction();
    }

    function _lup() internal view returns (uint256 lup_) {
        ( , , , , lup_, ) = _poolUtils.poolPricesInfo(address(_pool));
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
    event DecreaseLiquidity(address indexed lender_, uint256 indexed price_);
    event DecreaseLiquidityNFT(address indexed lender_, uint256 indexed price_);
    event IncreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 amount_);
    event MemorializePosition(address indexed lender_, uint256 tokenId_);
    event Mint(address indexed lender_, address indexed pool_, uint256 tokenId_);
    event MoveLiquidity(address indexed owner_, uint256 tokenId_);
    event RedeemPosition(address indexed lender_, uint256 tokenId_);


    /******************************/
    /*** Test utility functions ***/
    /******************************/

    function randomInRange(uint256 min, uint256 max) public returns (uint256) {
        return randomInRange(min, max, false);
    }

    function randomInRange(uint256 min, uint256 max, bool nonZero) public returns (uint256) {
        if      (max == 0 && nonZero) return 1;
        else if (max == min)           return max;
        uint256 rand = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, _nonce))) % (max - min + 1) + min;
        _nonce++;
        return rand;
    }

}
