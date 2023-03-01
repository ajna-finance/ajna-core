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

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.addQuoteToken(amount, bucketIndex, block.timestamp + 1 minutes);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        if (lpBalanceBefore == 0) {
            amount = constrictToRange(amount, 1, 1e36);
            addQuoteToken(amount, bucketIndex);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        try _pool.removeQuoteToken(amount, bucketIndex) {
            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
                err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
                err == keccak256(abi.encodeWithSignature("NoClaim()")));
        }
    }

    function moveQuoteToken(uint256 amount, uint256 fromIndex, uint256 toIndex) internal {
        if(fromIndex == toIndex) return;

        (uint256 lpBalance, ) = _pool.lenderInfo(fromIndex, _actor);

        if (lpBalance == 0) {
            addQuoteToken(amount, fromIndex);
        }

        try _pool.moveQuoteToken(amount, fromIndex, toIndex, block.timestamp + 1 minutes) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
                err == keccak256(abi.encodeWithSignature("MoveToSameIndex()")) ||
                err == keccak256(abi.encodeWithSignature("DustAmountNotExceeded()")) ||
                err == keccak256(abi.encodeWithSignature("InvalidIndex()")) ||
                err == keccak256(abi.encodeWithSignature("BucketBankruptcyBlock()"))
            );
        }
    }

    function addCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.addCollateral(amount, bucketIndex, block.timestamp + 1 minutes);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeCollateral(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        if(lpBalanceBefore == 0) {
            addCollateral(amount, bucketIndex);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        _pool.removeCollateral(amount, bucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
    }

    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(uint256 amount) internal {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        _pool.drawDebt(_actor, 0, 0, amount);      
    }

    function pullCollateral(uint256 amount) internal {
        numberOfCalls['UBBasicHandler.pullCollateral']++;

        try _pool.repayDebt(_actor, 0, amount, _actor, 7388) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
        } catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InsufficientCollateral()")) ||
                err == keccak256(abi.encodeWithSignature("AuctionActive()"))
            );
        }
    }
 
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

        try _pool.drawDebt(_actor, amount, 7388, collateralToPledge) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
        }
        catch (bytes memory _err){
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("BorrowerUnderCollateralized()")) ||
                err == keccak256(abi.encodeWithSignature("AuctionActive()"))
            );
        }
    }

    function repayDebt(uint256 amountToRepay) internal {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        // Pre condition
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            drawDebt(amountToRepay);
        }

        try _pool.repayDebt(_actor, amountToRepay, 0, _actor, 7388) {
            shouldExchangeRateChange = true;
            shouldReserveChange      = true;
        }
        catch(bytes memory _err) {
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("NoDebt()")) ||
                err == keccak256(abi.encodeWithSignature("AmountLTMinDebt()"))
            );
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

    /**************************/
    /*** Lender Functions ***/
    /**************************/

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        uint256 totalSupply = _quote.totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : _quote.balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);
    }

    function moveQuoteToken(uint256 actorIndex, uint256 amount, uint256 fromBucketIndex, uint256 toBucketIndex) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        fromBucketIndex = constrictToRange(fromBucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        toBucketIndex   = constrictToRange(toBucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        amount          = constrictToRange(amount, 1, 1e36);
        
        super.moveQuoteToken(amount, fromBucketIndex, toBucketIndex);
    }

    function addCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {
        numberOfCalls['BBasicHandler.addCollateral']++;

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


    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(uint256 actorIndex, uint256 amountToPledge) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.pledgeCollateral']++;

        amountToPledge = constrictToRange(amountToPledge, 1, 1e36);

        // Action
        super.pledgeCollateral(amountToPledge);
    }

    function pullCollateral(uint256 actorIndex, uint256 amountToPull) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        amountToPull = constrictToRange(amountToPull, 1, 1e36);

        // Action
        super.pullCollateral(amountToPull);
    } 

    function drawDebt(uint256 actorIndex, uint256 amountToBorrow) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.drawDebt']++;

        amountToBorrow = constrictToRange(amountToBorrow, 1, 1e36);
        
        // Action
        super.drawDebt(amountToBorrow);

        // skip time to make borrower undercollateralized
        vm.warp(block.timestamp + 200 days);
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) {
        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay = constrictToRange(amountToRepay, 1, 1e36);

        // Action
        super.repayDebt(amountToRepay);
    }
}
