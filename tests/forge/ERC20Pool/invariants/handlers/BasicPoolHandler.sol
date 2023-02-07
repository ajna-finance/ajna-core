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

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX, BaseHandler } from './BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicPoolHandler is BaseHandler {

    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function addQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.addQuoteToken(amount, bucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        try _pool.removeQuoteToken(amount, bucketIndex) {
            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
            shouldExchangeRateChange = false;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) || err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) || err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")));
        }
    }

    function addCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.addCollateral(amount, bucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.removeCollateral(amount, bucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
    }

    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 amount) internal {
        numberOfCalls['UBBasicHandler.drawDebt']++;

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

        try _pool.drawDebt(_actor, amount, 7388, collateralToPledge) {}
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(err == keccak256(abi.encodeWithSignature("BorrowerUnderCollateralized()")));
        }
    }

    function repayDebt(uint256 amountToRepay) internal {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        try _pool.repayDebt(_actor, amountToRepay, 0) {}
        catch(bytes memory _err) {
            bytes32 err = keccak256(_err);
            require(err == keccak256(abi.encodeWithSignature("NoDebt()")));
        }
    }

}


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract BasicPoolHandler is UnboundedBasicPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BaseHandler(pool, quote, collateral, poolInfo, numOfActors) {} 

    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        shouldExchangeRateChange = false;

        uint256 totalSupply = _quote.totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : _quote.balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        (uint256 lpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        if (lpBalance == 0) {
            amount = constrictToRange(amount, 1, 1e36);
            super.addQuoteToken(amount, _lenderBucketIndex);
        }

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);
    }

    function addCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addCollateral']++;

        shouldExchangeRateChange = false;

        amount = constrictToRange(amount, 1, 1e36);

        // Action
        super.addCollateral(amount, _lenderBucketIndex);
    }

    function removeCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        (uint256 lpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        ( , uint256 bucketCollateral, , , ) = _pool.bucketInfo(_lenderBucketIndex);

        if (lpBalance == 0 || bucketCollateral == 0) return; // no value in bucket

        amount = constrictToRange(amount, 1, 1e36);

        // Action
        super.removeCollateral(amount, _lenderBucketIndex);
    }


    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function drawDebt(uint256 actorIndex, uint256 amountToBorrow) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.drawDebt']++;

        shouldExchangeRateChange = true;

        amountToBorrow = constrictToRange(amountToBorrow, 1, 1e36);
        
        // Action
        super.drawDebt(amountToBorrow);

        // skip time to make borrower undercollateralized
        vm.warp(block.timestamp + 200 days);
        
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.repayDebt']++;

        shouldExchangeRateChange = true;

        amountToRepay = constrictToRange(amountToRepay, 1, 1e36);

        // Pre condition
        (uint256 debt, uint256 collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            super.drawDebt(amountToRepay);
        }

        // Action
        super.repayDebt(amountToRepay);

    }
}
