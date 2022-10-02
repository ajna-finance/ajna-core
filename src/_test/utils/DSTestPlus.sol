// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.14;

import '@std/Test.sol';
import '@std/Vm.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/IPoolFactory.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';
import '../../libraries/Heap.sol';
import '../../libraries/Book.sol';

abstract contract DSTestPlus is Test {

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    /*************/
    /*** Pools ***/
    /*************/

    // Pool events
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event Liquidate(address indexed borrower_, uint256 debt_, uint256 collateral_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event MoveCollateral(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
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
        vm.expectRevert(IPoolErrors.NoAuction.selector);
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


    /**************/
    /*** Prices ***/
    /**************/

    uint256 internal _p50159    = 50_159.593888626183666006 * 1e18;
    uint256 internal _p49910    = 49_910.043670274810022205 * 1e18;
    uint256 internal _p15000    = 15_000.520048194378317056 * 1e18;
    uint256 internal _p10016    = 10_016.501589292607751220 * 1e18;
    uint256 internal _p9020     = 9_020.461710444470171420 * 1e18;
    uint256 internal _p8002     = 8_002.824356287850613262 * 1e18;
    uint256 internal _p5007     = 5_007.644384905151472283 * 1e18;
    uint256 internal _p4000     = 4_000.927678580567537368 * 1e18;
    uint256 internal _p3514     = 3_514.334495390401848927 * 1e18;
    uint256 internal _p3010     = 3_010.892022197881557845 * 1e18;
    uint256 internal _p3002     = 3_002.895231777120270013 * 1e18;
    uint256 internal _p2995     = 2_995.912459898389633881 * 1e18;
    uint256 internal _p2981     = 2_981.007422784467321543 * 1e18;
    uint256 internal _p2966     = 2_966.176540084047110076 * 1e18;
    uint256 internal _p2850     = 2_850.155149230026939621 * 1e18;
    uint256 internal _p2835     = 2_835.975272865698470386 * 1e18;
    uint256 internal _p2821     = 2_821.865943149948749647 * 1e18;
    uint256 internal _p2807     = 2_807.826809104426639178 * 1e18;
    uint256 internal _p2793     = 2_793.857521496941952028 * 1e18;
    uint256 internal _p2779     = 2_779.957732832778084277 * 1e18;
    uint256 internal _p2503     = 2_503.519024294695168295 * 1e18;
    uint256 internal _p2000     = 2_000.221618840727700609 * 1e18;
    uint256 internal _p1004     = 1_004.989662429170775094 * 1e18;
    uint256 internal _p1000     = 1_000.023113960510762449 * 1e18;
    uint256 internal _p502      = 502.433988063349232760 * 1e18;
    uint256 internal _p146      = 146.575625611106531706 * 1e18;
    uint256 internal _p145      = 145.846393642892072537 * 1e18;
    uint256 internal _p100      = 100.332368143282009890 * 1e18;
    uint256 internal _p14_63    = 14.633264579158672146 * 1e18;
    uint256 internal _p13_57    = 13.578453165083418466 * 1e18;
    uint256 internal _p13_31    = 13.310245063610237646 * 1e18;
    uint256 internal _p12_66    = 12.662674231425615571 * 1e18;
    uint256 internal _p5_26     = 5.263790124045347667 * 1e18;
    uint256 internal _p1_64     = 1.646668492116543299 * 1e18;
    uint256 internal _p1_31     = 1.315628874808846999 * 1e18;
    uint256 internal _p1_05     = 1.051140132040790557 * 1e18;
    uint256 internal _p0_951347 = 0.951347940696068854 * 1e18;
    uint256 internal _p0_607286 = 0.607286776171110946 * 1e18;
    uint256 internal _p0_189977 = 0.189977179263271283 * 1e18;
    uint256 internal _p0_006856 = 0.006856528811048429 * 1e18;
    uint256 internal _p0_006822 = 0.006822416727411372 * 1e18;
    uint256 internal _p0_000046 = 0.000046545370002462 * 1e18;
    uint256 internal _p1        = 1 * 1e18;

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

    function generateAddress() internal returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(uint160(uint256(keccak256(abi.encodePacked(_nonce, blockhash(block.number))))));
        _nonce++;
    }

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

    function wadPercentDifference(uint256 lhs, uint256 rhs) internal pure returns (uint256 difference_) {
        difference_ = lhs < rhs ? Maths.WAD - Maths.wdiv(lhs, rhs) : Maths.WAD - Maths.wdiv(rhs, lhs);
    }

}

contract HeapInstance is DSTestPlus {
    using Heap for Heap.Data;

    Heap.Data private _heap;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    address[] private inserts;

    constructor () {
        _heap.init();
    }

    function getCount() public view returns (uint256) {
        return _heap.count;
    }

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIdByInsertIndex(uint256 i_) public view returns (address) {
        return inserts[i_];
    }

    function upsertTp(address borrower_, uint256 tp_) public {
        _heap.upsert(borrower_, tp_);
    }

    function removeTp(address borrower_) external {
        _heap.remove(borrower_);
    }

    function getTp(address borrower_) public view returns (uint256) {
        return _heap.getById(borrower_).val;
    }

    function getMaxTp() external view returns (uint256) {
        return _heap.getMax().val;
    }

    function getMaxBorrower() external view returns (address) {
        return _heap.getMax().id;
    }

    function getTotalTps() external view returns (uint256) {
        return _heap.count;
    }


    /**
     *  @notice fills Heap with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 inserts_,
        bool trackInserts_)
        external {

        uint256 tp;
        address borrower;

        // Calculate total insertions 
        uint256 totalInserts = bound(inserts_, 1000, 2000);
        uint256 insertsDec = totalInserts;

        while (insertsDec > 0) {

            // build address and TP
            borrower = makeAddr(vm.toString(insertsDec));
            tp = randomInRange(99_836_282_890, 1_004_968_987.606512354182109771 * 10**18, true);

            // Insert TP
            upsertTp(borrower, tp);
            insertsDec  -=  1;

            // Verify amount of Heap TPs
            assertEq(_heap.count - 1, totalInserts - insertsDec);
            assertEq(getTp(borrower), tp);

            if (trackInserts_)  inserts.push(borrower);
        }

        assertEq(_heap.count - 1, totalInserts);
    }
}


contract FenwickTreeInstance is DSTestPlus {
    using Book for Book.Deposits;

    Book.Deposits private deposits;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    uint256[] private inserts;

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIByInsertIndex(uint256 i_) public view returns (uint256) {
        return inserts[i_];
    }

    function add(uint256 i_, uint256 x_) public {
        deposits.add(i_, x_);
    }

    function remove(uint256 i_, uint256 x_) public {
        deposits.remove(i_, x_);
    }

    function mult(uint256 i_, uint256 f_) public {
        deposits.mult(i_, f_);
    }

    function treeSum() external view returns (uint256) {
        return deposits.treeSum();
    }

    function get(uint256 i_) external view returns (uint256 m_) {
        return deposits.valueAt(i_);
    }

    function scale(uint256 i_) external view returns (uint256 a_) {
        return deposits.scale(i_);
    }

    function findIndexOfSum(uint256 x_) external view returns (uint256 m_) {
        return deposits.findIndexOfSum(x_);
    }

    function prefixSum(uint256 i_) external view returns (uint256 s_) {
        return deposits.prefixSum(i_);
    }

    /**
     *  @notice fills fenwick tree with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 insertions_,
        uint256 amount_,
        bool trackInserts)
        external {

        uint256 i;
        uint256 amount;

        // Calculate total insertions 
        uint256 insertsDec= bound(insertions_, 1000, 2000);

        // Calculate total amount to insert
        uint256 totalAmount = bound(amount_, 1 * 1e18, 9_000_000_000_000_000 * 1e18);
        uint256 totalAmountDec = totalAmount;


        while (totalAmountDec > 0 && insertsDec > 0) {

            // Insert at random index
            i = randomInRange(1, 8190);

            // If last iteration, insert remaining
            amount = insertsDec == 1 ? totalAmountDec : (totalAmountDec % insertsDec) * randomInRange(1_000, 1 * 1e10, true);

            // Update values
            add(i, amount);
            totalAmountDec  -=  amount;
            insertsDec      -=  1;

            // Verify tree sum
            assertEq(deposits.treeSum(), totalAmount - totalAmountDec);

            if (trackInserts)  inserts.push(i);
        }

        assertEq(deposits.treeSum(), totalAmount);
    }

}
