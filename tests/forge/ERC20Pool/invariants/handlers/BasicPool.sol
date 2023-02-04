// SPDX-License-Identifier: UNLICENSED 
pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import "forge-std/console.sol";
import '@std/Test.sol';
import '@std/Vm.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils, _collateralization }    from 'src/PoolInfoUtils.sol';

import { _ptp } from 'src/libraries/helpers/PoolHelper.sol';

import { BaseHandler }    from './Base.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './Base.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract UnboundedBasicPoolHandler is Test, BaseHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BaseHandler(pool, quote, collateral, poolInfo, numOfActors) {} 

    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function addQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        // vm.startPrank(_actors[0]);
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        fenwickAccrueInterest();

        _pool.addQuoteToken(amount, bucketIndex);

        // vm.stopPrank();
        
        uint256 deposit = fenwickDeposits[bucketIndex];
        fenwickDeposits[bucketIndex] = deposit + amount;
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        // vm.startPrank(_actors[0]);
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        fenwickAccrueInterest();
        
        (uint256 removedAmount,) = _pool.removeQuoteToken(amount, bucketIndex);

        // add early withdrawal penalty back to removedAmount if removeQT is occurs above the PTP
        // as that is the value removed from the fenwick tree
        (, uint256 depositTime) = _pool.lenderInfo(bucketIndex, _actor);
        uint256 price = _poolInfo.indexToPrice(bucketIndex);
        (, uint256 poolDebt ,) = _pool.debtInfo();
        uint256 poolCollateral  = _pool.pledgedCollateral();

        if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
            if (price > _ptp(poolDebt, poolCollateral)) {
                removedAmount = wdiv(removedAmount, 1e18 - _poolInfo.feeRate(address(_pool)));
            }
        }

        // vm.stopPrank();

        // Fenwick
        uint256 deposit = fenwickDeposits[bucketIndex];
        fenwickDeposits[bucketIndex] = deposit - removedAmount;

    }

    function addCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        _pool.addCollateral(amount, bucketIndex);
    }

    function removeCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        _pool.removeCollateral(amount, bucketIndex);
    }

    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 amount) internal {

        // vm.startPrank(_actors[1]);
        // _actor = _actors[1];
        numberOfCalls['UBBasicHandler.drawDebt']++;

        fenwickAccrueInterest();

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));
        if (amount < minDebt) amount = minDebt + 1;


        // TODO: Need to constrain amount so LUP > HTP


        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (amount > poolQuoteBalance) {
            addQuoteToken(amount * 2, LENDER_MAX_BUCKET_INDEX);
        }

        // 3. drawing of addition debt will make them under collateralized
        uint256 lup = _poolInfo.lup(address(_pool));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        if (_collateralization(debt, collateral, lup) < 1) {
            repayDebt(debt);
            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
            require(debt == 0, "borrower has debt");
        }

        (uint256 poolDebt, , ) = _pool.debtInfo();

        // find bucket to borrow quote token
        uint256 bucket = _pool.depositIndex(amount + poolDebt) - 1;

        uint256 price = _poolInfo.indexToPrice(bucket);

        uint256 collateralToPledge = ((amount * 1e18 + price / 2) / price) * 101 / 100;

        _pool.drawDebt(_actor, amount, 7388, collateralToPledge); 
        // vm.stopPrank();

        // skip time to make borrower undercollateralized
        // vm.warp(block.timestamp + 200 days);
    }

    function repayDebt(uint256 amountToRepay) internal {

        numberOfCalls['UBBasicHandler.repayDebt']++;

        _pool.repayDebt(_actor, amountToRepay, 0);
    }

}


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract BoundedBasicPoolHandler is UnboundedBasicPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) UnboundedBasicPoolHandler(pool, quote, collateral, poolInfo, numOfActors) {} 

    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        uint256 totalSupply = _quote.totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : _quote.balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {

        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        if (lpBalanceBefore == 0) {
            amount = constrictToRange(amount, 1, 1e36);
            super.addQuoteToken(amount, _lenderBucketIndex);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
    }

    function addCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        uint256 totalSupply = _collateral.totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : _collateral.balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        // Action
        super.addCollateral(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {

        numberOfCalls['BBasicHandler.removeCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        if (lpBalanceBefore == 0) return; // no value in bucket

        // Action
        super.removeCollateral(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
    }


    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 actorIndex, uint256 amountToBorrow) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.drawDebt']++;

        // amount of debt is contstrained so overflow doesn't happen on mint
        // uint256 totalSupply = _quote.totalSupply();
        // uint256 minBorrow = totalSupply == 0 ? 1 : _quote.balanceOf(address(_actor)) / totalSupply + 1;
        amountToBorrow = constrictToRange(amountToBorrow, 1e18, 1e36);
        
        // Action
        super.drawDebt(amountToBorrow);
        
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) {

        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay = constrictToRange(amountToRepay, 1e18, 1e36);

        // Pre condition
        (uint256 debt, uint256 collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            super.drawDebt(amountToRepay);
        }

        // Action
        super.repayDebt(amountToRepay);

    }
}
