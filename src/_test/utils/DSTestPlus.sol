// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.14;

import '@std/Test.sol';
import '@std/Vm.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/IPoolFactory.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';

abstract contract DSTestPlus is Test {

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    /*************/
    /*** Pools ***/
    /*************/

    // Pool events
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event Kick(address indexed borrower_, uint256 debt_, uint256 collateral_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event MoveCollateral(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);
    event TransferLPTokens(address owner_, address newOwner_, uint256[] prices_, uint256 lpTokens_);
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);
    event ReserveAuction(uint256 claimableReservesRemaining_, uint256 auctionPrice_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    IPool         internal _pool;
    PoolInfoUtils internal _poolUtils;
    uint256       internal _startTime;

    struct PoolState {
        uint256 htp;
        uint256 lup;
        uint256 poolSize;
        uint256 pledgedCollateral;
        uint256 encumberedCollateral;
        uint256 borrowerDebt;
        uint256 actualUtilization;
        uint256 targetUtilization;
        uint256 minDebtAmount;
        uint256 loans;
        address maxBorrower;
        uint256 interestRate;
        uint256 interestRateUpdate;
    }

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
    }

    function _borrow(
        address from,
        uint256 amount,
        uint256 indexLimit,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Borrow(from, newLup, amount);
        _assertTokenTransferEvent(address(_pool), from, amount);
        _pool.borrow(amount, indexLimit);
    }

    function _kick(
        address from,
        address borrower,
        uint256 debt,
        uint256 collateral,
        uint256 bond
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Kick(borrower, debt, collateral);
        _assertTokenTransferEvent(from, address(_pool), bond);
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
        (uint256 removedAmount, uint256 lpRedeemed) = _pool.removeAllQuoteToken(index);
        assertEq(removedAmount, amount);
        assertEq(lpRedeemed,    lpRedeem);
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
        uint256 lpRedeemed = _pool.removeQuoteToken(amount, index);
        assertEq(lpRedeemed, lpRedeem);
    }

    function _repay(
        address from,
        address borrower,
        uint256 amount,
        uint256 repaid,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit Repay(borrower, newLup, repaid);
        _assertTokenTransferEvent(from, address(_pool), amount);
        _pool.repay(borrower, amount);
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

    function _assertAuction(
        address borrower,
        bool    active,
        address kicker,
        uint256 bondSize,
        uint256 bondFactor,
        uint256 kickTime,
        uint256 kickMomp
    ) internal {
        (
            address auctionKicker,
            uint256 auctionBondFactor,
            uint256 auctionKickTime,
            uint256 auctionKickMomp,
            ,
        ) = _pool.auctionInfo(borrower);
        (, uint256 lockedBonds) = _pool.kickers(kicker);

        assertEq(auctionKickTime != 0,  active);
        assertEq(auctionKicker,         kicker);
        assertEq(lockedBonds,           bondSize);
        assertEq(auctionBondFactor,     bondFactor);
        assertEq(auctionKickTime,       kickTime);
        assertEq(auctionKickMomp, kickMomp);
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

        assertEq(htp, state_.htp);
        assertEq(lup, state_.lup);

        assertEq(poolSize,                   state_.poolSize);
        assertEq(_pool.pledgedCollateral(),  state_.pledgedCollateral);
        assertEq(
            PoolUtils.encumberance(
                state_.borrowerDebt,
                state_.lup
            ),                               state_.encumberedCollateral
        );
        assertEq(_pool.borrowerDebt(),       state_.borrowerDebt);
        assertEq(poolActualUtilization,      state_.actualUtilization);
        assertEq(poolTargetUtilization,      state_.targetUtilization);
        assertEq(poolMinDebtAmount,          state_.minDebtAmount);

        assertEq(loansCount,  state_.loans);
        assertEq(maxBorrower, state_.maxBorrower);

        uint256 poolInflatorSnapshot = _pool.inflatorSnapshot();
        assertGe(poolInflatorSnapshot, 1e18);
        assertGe(pendingInflator,      poolInflatorSnapshot);

        assertEq(_pool.interestRate(),       state_.interestRate);
        assertEq(_pool.interestRateUpdate(), state_.interestRateUpdate);
    }

    function _assertLenderLpBalance(
        address lender,
        uint256 index,
        uint256 lpBalance,
        uint256 depositTime
    ) internal {
        (uint256 curLpBalance, uint256 time) = _pool.lenders(index, lender);
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
        uint256 borrowerMompFactor,
        uint256 borrowerInflator,
        uint256 borrowerPendingDebt,
        uint256 borrowerCollateralization
    ) internal {
        (
            uint256 debt,
            uint256 pendingDebt,
            uint256 col,
            uint256 mompFactor,
            uint256 inflator
        ) = _poolUtils.borrowerInfo(address(_pool), borrower);

        uint256 lup = _poolUtils.lup(address(_pool));

        assertEq(debt,        borrowerDebt);
        assertEq(col,         borrowerCollateral);
        assertEq(mompFactor,  borrowerMompFactor);
        assertEq(inflator,    borrowerInflator);
        assertEq(
            PoolUtils.collateralization(
                borrowerDebt,
                borrowerCollateral,
                lup
            ),
            borrowerCollateralization
        );
        assertEq(pendingDebt, borrowerPendingDebt);
    }

    function _assertKicker(
        address kicker,
        uint256 claimable,
        uint256 locked
    ) internal {
        (uint256 curClaimable, uint256 curLocked) = _pool.kickers(kicker);

        assertEq(curClaimable, claimable);
        assertEq(curLocked,    locked);
    }

    function _assertLoans(
        uint256 noOfLoans,
        address maxBorrower,
        uint256 maxThresholdPrice
    ) internal {
        assertEq(_pool.noOfLoans(),         noOfLoans);
        assertEq(_pool.maxBorrower(),       maxBorrower);
        assertEq(_pool.maxThresholdPrice(), maxThresholdPrice);
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

    function _assertBorrowAuctionActiveRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AuctionActive.selector);
        _pool.borrow(amount, indexLimit);
    }

    function _assertBorrowLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexReached.selector);
        _pool.borrow(amount, indexLimit);
    }

    function _assertBorrowBorrowerUnderCollateralizedRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerUnderCollateralized.selector);
        _pool.borrow(amount, indexLimit);
    }

    function _assertBorrowMinDebtRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        _pool.borrow(amount, indexLimit);
    }

    function _assertKickAuctionActiveRevert(
        address from,
        address borrower
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AuctionActive.selector);
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

    function _assertRepayNoDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoDebt.selector);
        _pool.repay(borrower, amount);
    }

    function _assertRepayMinDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        _pool.repay(borrower, amount);
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

    function _assertRemoveAllLiquidityLupBelowHtpRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        _pool.removeAllQuoteToken(index);
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

    function _assertDeployWith0xAddressRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        IPoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertDeployWithInvalidRateRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        IPoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertDeployMultipleTimesRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        IPoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
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
