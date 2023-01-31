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

import { BaseHandler }    from './Base.sol';
import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './Base.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract UnboundedBasicPoolHandler is Test, BaseHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BaseHandler(pool, quote, collateral, poolInfo, numOfActors) {
    } 


    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    // function _addQuoteToken(uint256 amount, uint256 bucket) internal {
    //     ERC20Pool(_pool).addQuoteToken(amount, bucket);
    // }

    function addQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        uint256 totalSupply = _quote.totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : _quote.balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        _pool.addQuoteToken(amount, bucketIndex);
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        _pool.removeQuoteToken(amount, bucketIndex);
    }

    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 amount, uint256 collateralToPledge) public virtual {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        // _collateral.mint(_actor, collateralToPledge);
        // _collateral.approve(address(_pool), collateralToPledge);

        _pool.drawDebt(_actor, amount, 7388, collateralToPledge); 
    }

    function repayDebt(address _actor, uint256 amountToRepay) internal {

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

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = ERC20Pool(_pool).lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {

        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        if (lpBalanceBefore == 0) return; // no value in bucket

        // get max amount of quote actor has in bucket
        uint256 deposit = _poolInfo.lpsToQuoteTokens(address(_pool), lpBalanceBefore, _lenderBucketIndex);

        amount = constrictToRange(amount, 1, deposit);

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
    }


    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 actorIndex, uint256 amountToBorrow) public override useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.drawDebt']++;

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized
        // 4. borrower should have sufficent collateral to draw debt

        // amount of debt is contstrained so overflow doesn't happen on mint for _quote or _collateral in collateralToPledge
        amountToBorrow = constrictToRange(amountToBorrow, 0, 1e36);

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));
        if (amountToBorrow < minDebt) amountToBorrow = minDebt + 1;

        // TODO: Need to constrain amountToBorrow so LUP > HTP

        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (amountToBorrow > poolQuoteBalance) {
            addQuoteToken(amountToBorrow, LENDER_MAX_BUCKET_INDEX);
        }

        // 3. drawing of addition debt will make them under collateralized
        uint256 lup = _poolInfo.lup(address(_pool));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        if (_collateralization(debt, collateral, lup) < 1) {
            repayDebt(_actor, debt);
            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
            require(debt == 0, "borrower has debt");
        }

        // 4. borrower should have sufficent collateral to draw debt 
        uint256 poolPrice = _poolInfo.lup(address(_pool));
        poolPrice = poolPrice == 1_004_968_987606512354182109771 ? _poolInfo.hpb(address(_pool)) : poolPrice;
        uint256 collateralToPledge = ((amountToBorrow * 1e18 + poolPrice / 2) / poolPrice) * 1e18;
        
        // Action
        super.drawDebt(amountToBorrow, collateralToPledge);
        
        // Post Condition
    }

    // function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) {

    //     // Pre condition
    //     (uint256 debt, uint256 collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
    //     if (debt == 0) return;

    //     // Action
    //     repayDebt(_actor, amountToRepay);

    //     // Post condition
    //     (debt, collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
    //     require(debt == 0, "borrower has debt");
    // }
}
