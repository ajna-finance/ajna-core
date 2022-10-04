// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 } from '@solmate/tokens/ERC20.sol';

import { DSTestPlus } from '../utils/DSTestPlus.sol';
import { Token }      from '../utils/Tokens.sol';

import { ERC20Pool }        from '../../erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from '../../erc20/ERC20PoolFactory.sol';

import { PoolInfoUtils } from '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';
import '../../libraries/Actors.sol';

abstract contract ERC20DSTestPlus is DSTestPlus {

    // ERC20 events
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    // Pool events
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event PledgeCollateral(address indexed borrower_, uint256 amount_);
    event PullCollateral(address indexed borrower_, uint256 amount_);
    event RemoveCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /*****************/
    /*** Utilities ***/
    /*****************/

    struct AddLiquiditySpecs {
        address from;        // lender address
        Liquidity[] amounts; // liquidities to add
    }

    struct AddCollateralSpecs {
        address from;
        uint256 amount;
        uint256 index;
    }

    struct BorrowSpecs {
        address from;
        address borrower;
        uint256 pledgeAmount; 
        uint256 borrowAmount;
        uint256 indexLimit;
        uint256 price;
    }

    struct PledgeSpecs {
        address from;
        address borrower;
        uint256 amount; 
    }

    struct PullSpecs {
        address from;
        uint256 amount; 
    }

    struct MoveCollateralSpecs {
        address from;
        uint256 amount;
        uint256 fromIndex; 
        uint256 toIndex;
        uint256 lpRedeemFrom;
        uint256 lpRedeemTo;
    }

    struct MoveLiquiditySpecs {
        address from;
        uint256 amount;
        uint256 fromIndex; 
        uint256 toIndex;
        uint256 newLup;
        uint256 lpRedeemFrom;
        uint256 lpRedeemTo;
    }

    struct RemoveAllLiquiditySpecs {
        address from;
        uint256 index;
        uint256 amount;
        uint256 newLup;
        uint256 lpRedeem;
    }

    struct RemoveCollateralSpecs {
        address from;
        uint256 amount;
        uint256 index;
        uint256 lpRedeem;
    }

    struct RemoveLiquiditySpecs {
        address from;
        uint256 index;
        uint256 amount;
        uint256 penalty;
        uint256 newLup;
        uint256 lpRedeem;
    }

    struct RepaySpecs {
        address from;
        address borrower;
        uint256 repayAmount; 
        uint256 price;
    }

    struct Liquidity {
        uint256 index;  // bucket index
        uint256 amount; // amount to add
        uint256 newLup;
    }

    struct LenderLPs {
        address    lender;
        BucketLP[] bucketLPs;
    }

    struct BucketLP {
        uint256 index;
        uint256 balance;
        uint256 time;
    }

    struct BucketState {
        uint256 index;
        uint256 LPs;
        uint256 collateral;
    }

    struct BorrowerState {
        address borrower;
        uint256 debt;
        uint256 pendingDebt;
        uint256 collateral;
        uint256 collateralization;
        uint256 mompFactor;
        uint256 inflator;
    }

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

    struct PoolPricesInfo {
        uint256 hpb;
        uint256 htp;
        uint256 lup;
        uint256 lupIndex;
    }

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

}

// TODO: merge this contract with parent ERC20DSTestPlus
abstract contract ERC20HelperContract is ERC20DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    Token         internal _collateral;
    Token         internal _quote;
    ERC20Pool     internal _pool;
    PoolInfoUtils internal _poolUtils;
    uint256       internal _startTime;

    constructor() {
        _collateral = new Token("Collateral", "C");
        _quote      = new Token("Quote", "Q");
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils  = new PoolInfoUtils();
        _startTime  = block.timestamp;
    }

    function _mintQuoteAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
    }

    function _mintCollateralAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_collateral), operator_, mintAmount_);

        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);

    }

    function _addLiquidity(AddLiquiditySpecs memory specs_) internal {
        changePrank(specs_.from);
        for (uint256 i = 0; i < specs_.amounts.length; ++i) {
            vm.expectEmit(true, true, false, true);
            emit AddQuoteToken(specs_.from, specs_.amounts[i].index, specs_.amounts[i].amount, specs_.amounts[i].newLup);
            vm.expectEmit(true, true, false, true);
            emit Transfer(specs_.from, address(_pool), specs_.amounts[i].amount);
            _pool.addQuoteToken(specs_.amounts[i].amount, specs_.amounts[i].index);
        }
    }

    function _addCollateral(AddCollateralSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(specs_.from, specs_.index, specs_.amount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(specs_.from, address(_pool), specs_.amount);
        _pool.addCollateral(specs_.amount, specs_.index);
    }

    function _removeAllCollateral(RemoveCollateralSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(specs_.from, specs_.index, specs_.amount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), specs_.from, specs_.amount);
        (uint256 collateralRemoved, uint256 lpAmount) = _pool.removeAllCollateral(specs_.index);
        assertEq(collateralRemoved, specs_.amount);
        assertEq(lpAmount, specs_.lpRedeem);
    }

    function _removeAllLiquidity(RemoveAllLiquiditySpecs memory specs_) internal {
        // apply penalty if case
        changePrank(specs_.from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(specs_.from, specs_.index, specs_.amount, specs_.newLup);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), specs_.from, specs_.amount);
        (uint256 amount, uint256 lpRedeemed) = _pool.removeAllQuoteToken(specs_.index);
        assertEq(amount, specs_.amount);
        assertEq(lpRedeemed, specs_.lpRedeem);
    }

    function _removeCollateral(RemoveCollateralSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(specs_.from, specs_.index, specs_.amount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), specs_.from, specs_.amount);
        uint256 lpRedeemed = _pool.removeCollateral(specs_.amount, specs_.index);
        assertEq(lpRedeemed, specs_.lpRedeem);
    }

    function _removeLiquidity(RemoveLiquiditySpecs memory specs_) internal {
        // apply penalty if case
        uint256 expectedWithdrawal = specs_.penalty != 0 ? Maths.wmul(specs_.amount, specs_.penalty) : specs_.amount;

        changePrank(specs_.from);
        vm.expectEmit(true, true, false, true);
        emit RemoveQuoteToken(specs_.from, specs_.index, expectedWithdrawal, specs_.newLup);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), specs_.from, expectedWithdrawal);
        uint256 lpRedeemed = _pool.removeQuoteToken(specs_.amount, specs_.index);
        assertEq(lpRedeemed, specs_.lpRedeem);
    }

    function _moveCollateral(MoveCollateralSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, true, true);
        emit MoveCollateral(specs_.from, specs_.fromIndex, specs_.toIndex, specs_.amount);
        (uint256 lpbFrom, uint256 lpbTo) = _pool.moveCollateral(specs_.amount, specs_.fromIndex, specs_.toIndex);
        assertEq(lpbFrom, specs_.lpRedeemFrom);
        assertEq(lpbTo, specs_.lpRedeemTo);
    }

    function _moveLiquidity(MoveLiquiditySpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(specs_.from, specs_.fromIndex, specs_.toIndex, specs_.lpRedeemTo / 1e9, specs_.newLup);
        (uint256 lpbFrom, uint256 lpbTo) = _pool.moveQuoteToken(specs_.amount, specs_.fromIndex, specs_.toIndex);
        assertEq(lpbFrom, specs_.lpRedeemFrom);
        assertEq(lpbTo, specs_.lpRedeemTo);
    }

    function _borrow(BorrowSpecs memory specs_) internal {
        changePrank(specs_.from);
        if (specs_.pledgeAmount != 0) _pool.pledgeCollateral(specs_.borrower, specs_.pledgeAmount);

        vm.expectEmit(true, true, false, true);
        emit Borrow(specs_.borrower, specs_.price, specs_.borrowAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), specs_.from, specs_.borrowAmount);
        _pool.borrow(specs_.borrowAmount, specs_.indexLimit);
    }

    function _pledgeCollateral(PledgeSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(specs_.from, specs_.amount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(specs_.from, address(_pool), specs_.amount);
        _pool.pledgeCollateral(specs_.borrower, specs_.amount);
    }

    function _pullCollateral(PullSpecs memory specs_) internal {
        changePrank(specs_.from);
        vm.expectEmit(true, true, false, true);
        emit PullCollateral(specs_.from, specs_.amount);
        _pool.pullCollateral(specs_.amount);
    }

    function _repay(RepaySpecs memory specs_) internal {
        changePrank(specs_.from);
        
        vm.expectEmit(true, true, false, true);
        emit Repay(specs_.borrower, specs_.price, specs_.repayAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(specs_.from, address(_pool), specs_.repayAmount);
        _pool.repay(specs_.borrower, specs_.repayAmount);
    }

    function _assertPool(PoolState memory state_) internal {
        ( , , uint256 htp, , uint256 lup, ) = _poolUtils.poolPricesInfo(address(_pool));
        (uint256 poolSize, uint256 loansCount, address maxBorrower, uint256 pendingInflator, ) = _poolUtils.poolLoansInfo(address(_pool));
        (uint256 poolMinDebtAmount, , uint256 poolActualUtilization, uint256 poolTargetUtilization) = _poolUtils.poolUtilizationInfo(address(_pool));
        assertEq(htp, state_.htp);
        assertEq(lup, state_.lup);

        assertEq(poolSize,              state_.poolSize);
        assertEq(_pool.pledgedCollateral(),     state_.pledgedCollateral);
        assertEq(_encumberedCollateral(state_.borrowerDebt, state_.lup), state_.encumberedCollateral);
        assertEq(_pool.borrowerDebt(),          state_.borrowerDebt);
        assertEq(poolActualUtilization, state_.actualUtilization);
        assertEq(poolTargetUtilization, state_.targetUtilization);
        assertEq(poolMinDebtAmount,     state_.minDebtAmount);

        assertEq(loansCount,  state_.loans);
        assertEq(maxBorrower, state_.maxBorrower);

        uint256 poolInflatorSnapshot = _pool.inflatorSnapshot();
        assertGe(poolInflatorSnapshot, 1e18);
        assertGe(pendingInflator,      poolInflatorSnapshot);

        assertEq(_pool.interestRate(),       state_.interestRate);
        assertEq(_pool.interestRateUpdate(), state_.interestRateUpdate);
    }

    function _assertLPs(LenderLPs memory specs_) internal {
        for (uint256 i = 0; i < specs_.bucketLPs.length; ++i) {
            (uint256 lpBalance, uint256 time) = _pool.lenders(specs_.bucketLPs[i].index, specs_.lender);
            assertEq(lpBalance, specs_.bucketLPs[i].balance);
            assertEq(time,      specs_.bucketLPs[i].time);
        }
    }

    function _assertBuckets(BucketState[] memory state_) internal {
        for (uint256 i = 0; i < state_.length; ++i) {
            (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(state_[i].index);
            assertEq(lpAccumulator,       state_[i].LPs);
            assertEq(availableCollateral, state_[i].collateral);
        }
    }

    function _assertBorrower(BorrowerState memory state_) internal {
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 mompFactor, uint256 inflator) = _poolUtils.borrowerInfo(address(_pool), state_.borrower);
        ( , , , , uint256 lup, ) = _poolUtils.poolPricesInfo(address(_pool));
        assertEq(debt,        state_.debt);
        assertEq(pendingDebt, state_.pendingDebt);
        assertEq(col,         state_.collateral);
        assertEq(mompFactor,  state_.mompFactor);
        assertEq(inflator,    state_.inflator);

        assertEq(
            PoolUtils.collateralization(
                state_.debt,
                state_.collateral,
                lup
            ),
            state_.collateralization
        );
    }

    function _assertPoolPrices(PoolPricesInfo memory state_) internal {
        (uint256 hpb, , uint256 htp, , uint256 lup, uint256 lupIndex) = _poolUtils.poolPricesInfo(address(_pool));
        assertEq(hpb,      state_.hpb);
        assertEq(htp,      state_.htp);
        assertEq(lup,      state_.lup);
        assertEq(lupIndex, state_.lupIndex);
    }

    function _assertTpHeapValid() internal {
        ( , , uint256 htp, , , ) = _poolUtils.poolPricesInfo(address(_pool));
        (, uint256 loansCount, address maxBorrower, , ) = _poolUtils.poolLoansInfo(address(_pool));
        if (_pool.borrowerDebt() == 0) {
            assertEq(htp, 0);
            assertEq(loansCount, 0);
            assertEq(maxBorrower, address(0));
        } else {
            assertGt(htp, 0);
            assertGt(loansCount, 0);
            assertTrue(maxBorrower != address(0));
        }
    }

    function _loansCount() internal view returns (uint256 loansCount_) {
        ( , loansCount_, , , ) = _poolUtils.poolLoansInfo(address(_pool));
    }

    function _poolSize() internal view returns (uint256 poolSize_) {
        (poolSize_, , , , ) = _poolUtils.poolLoansInfo(address(_pool));
    }

    function _exchangeRate(uint256 index_) internal view returns (uint256 exchangeRate_) {
        ( , , , , , exchangeRate_) = _poolUtils.bucketInfo(address(_pool), index_);
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

    function _indexToPrice(uint256 index_) internal view returns (uint256 price_) {
        ( price_, , , , , ) = _poolUtils.bucketInfo(address(_pool), index_);
    }

    function _encumberedCollateral(uint256 debt_, uint256 price_) internal pure returns (uint256 encumberance_) {
        encumberance_ =  price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }
}