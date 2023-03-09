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
import "src/libraries/internal/Maths.sol";

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

    function addQuoteToken(uint256 amount, uint256 bucketIndex) internal useTimestamps {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        (uint256 poolDebt,,) = _pool.debtInfo();
        uint256 lupIndex = _pool.depositIndex(poolDebt);
        (uint256 interestRate,) = _pool.interestRateInfo();

        try _pool.addQuoteToken(amount, bucketIndex, block.timestamp + 1 minutes) {
            // lender's deposit time updates when lender adds Quote token into pool
            lenderDepositTime[_actor][bucketIndex] = block.timestamp;

            // deposit fee is charged if deposit is added below lup
            if(lupIndex < bucketIndex) {
                amount = Maths.wmul(amount, 1e18 - Maths.wdiv(interestRate, 365 * 1e18));
            }

            fenwickAdd(amount, bucketIndex);
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
            require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
        }
        catch (bytes memory _err) {
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("BucketBankruptcyBlock()"))
            );
        }

        // skip some time to avoid early withdraw penalty
        vm.warp(block.timestamp + 25 hours);
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        if (lpBalanceBefore == 0) {
            amount = constrictToRange(amount, 1, 1e30);
            addQuoteToken(amount, bucketIndex);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        try _pool.removeQuoteToken(amount, bucketIndex) returns (uint256 removedAmount, uint256) {
            fenwickRemove(removedAmount, bucketIndex);
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
        }
        catch (bytes memory _err){
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
                err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
                err == keccak256(abi.encodeWithSignature("NoClaim()")));
        }
    }

    function moveQuoteToken(uint256 amount, uint256 fromIndex, uint256 toIndex) internal useTimestamps resetAllPreviousLocalState {
        if(fromIndex == toIndex) return;

        (uint256 lpBalance, ) = _pool.lenderInfo(fromIndex, _actor);

        if (lpBalance == 0) {
            addQuoteToken(amount, fromIndex);
        }
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        (uint256 poolDebt,,) = _pool.debtInfo();
        uint256 lupIndex = _pool.depositIndex(poolDebt);

        try _pool.moveQuoteToken(amount, fromIndex, toIndex, block.timestamp + 1 minutes) returns(uint256, uint256, uint256 movedAmount) {
            fenwickAdd(movedAmount, toIndex);

            // deposit fee is charged if deposit is moved from above the lup to below the lup
            if(fromIndex >= lupIndex && toIndex < lupIndex) {
                movedAmount = Maths.wdiv(Maths.wmul(movedAmount, 365 * 1e18), 364 * 1e18);
                fenwickRemove(movedAmount, fromIndex);
            }

            (, uint256 fromBucketDepositTime) = _pool.lenderInfo(fromIndex, _actor);
            (, uint256 toBucketDepositTime) = _pool.lenderInfo(toIndex, _actor);
            
            // lender's deposit time updates when lender moves Quote token from one bucket to another
            lenderDepositTime[_actor][toIndex] = Maths.max(fromBucketDepositTime, toBucketDepositTime);

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();
        }
        catch (bytes memory _err){
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
                err == keccak256(abi.encodeWithSignature("MoveToSameIndex()")) ||
                err == keccak256(abi.encodeWithSignature("DustAmountNotExceeded()")) ||
                err == keccak256(abi.encodeWithSignature("InvalidIndex()")) ||
                err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
                err == keccak256(abi.encodeWithSignature("BucketBankruptcyBlock()"))
            );
        }
    }

    function addCollateral(uint256 amount, uint256 bucketIndex) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);
        
        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousExchangeRate();
        updatePreviousReserves();

        _pool.addCollateral(amount, bucketIndex, block.timestamp + 1 minutes);

        // lender's deposit time updates when lender adds collateral token into pool
        lenderDepositTime[_actor][bucketIndex] = block.timestamp;

        updateCurrentExchangeRate();
        updateCurrentReserves();

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");

        // skip some time to avoid early withdraw penalty
        vm.warp(block.timestamp + 25 hours);
    }

    function removeCollateral(uint256 amount, uint256 bucketIndex) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);

        if(lpBalanceBefore == 0) {
            addCollateral(amount, bucketIndex);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex, _actor);
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        try _pool.removeCollateral(amount, bucketIndex) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");
        }
        catch (bytes memory _err){
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLPs()")) || 
                err == keccak256(abi.encodeWithSignature("AuctionNotCleared()"))
            );
        }
    }

    function increaseLPsAllowance(address receiver, uint256 bucketIndex, uint256 amount) internal useTimestamps resetAllPreviousLocalState {
        // approve as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = receiver;
        _pool.approveLPsTransferors(transferors);
        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        _pool.increaseLPsAllowance(receiver, buckets, amounts);
    }

    function transferLps(address sender, address receiver, uint256 bucketIndex) internal useTimestamps resetAllPreviousLocalState {
        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex;

        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        changePrank(receiver);
        try _pool.transferLPs(sender, receiver, buckets) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();

            (, uint256 senderDepositTime) = _pool.lenderInfo(bucketIndex, sender);
            (, uint256 receiverDepositTime) = _pool.lenderInfo(bucketIndex, receiver);

            // receiver's deposit time updates when receiver receives lps
            lenderDepositTime[receiver][bucketIndex] = Maths.max(senderDepositTime, receiverDepositTime);
        } catch{
            resetReservesAndExchangeRate();
        }
    }

    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(uint256 amount) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        _pool.drawDebt(_actor, 0, 0, amount);   

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;   
        updateCurrentExchangeRate();
        updateCurrentReserves();

    }

    function pullCollateral(uint256 amount) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pullCollateral']++;
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousExchangeRate();
        updatePreviousReserves();

        try _pool.repayDebt(_actor, 0, amount, _actor, 7388) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentExchangeRate();
            updateCurrentReserves();
        } catch (bytes memory _err){
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientCollateral()")) ||
                err == keccak256(abi.encodeWithSignature("AuctionActive()"))
            );
        }
    }
 
    function drawDebt(uint256 amount) internal useTimestamps resetAllPreviousLocalState {
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

        uint256 collateralToPledge = ((amount * 1e18 + price / 2) / price) * 101 / 100 + 1;
        
        fenwickAccrueInterest();
        updatePoolState();

        updatePreviousReserves();
        updatePreviousExchangeRate();

        (uint256 interestRate, ) = _pool.interestRateInfo();

        try _pool.drawDebt(_actor, amount, 7388, collateralToPledge) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = true;
            updateCurrentReserves();
            updateCurrentExchangeRate();

            // reserve should increase by origination fee on draw debt
            drawDebtIncreaseInReserve = Maths.wmul(amount, Maths.max(Maths.wdiv(interestRate, 52 * 1e18), 0.0005 * 1e18));
        }
        catch (bytes memory _err){
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("BorrowerUnderCollateralized()")) ||
                err == keccak256(abi.encodeWithSignature("AuctionActive()"))
            );
        }

        // skip to make borrower undercollateralize
        vm.warp(block.timestamp + 200 days);
    }

    function repayDebt(uint256 amountToRepay) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        // Pre condition
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) {
            drawDebt(amountToRepay);
        }
        
        fenwickAccrueInterest();
        updatePoolState();
        updatePreviousReserves();
        updatePreviousExchangeRate();

        try _pool.repayDebt(_actor, amountToRepay, 0, _actor, 7388) {
            shouldExchangeRateChange = false;
            shouldReserveChange      = false;
            updateCurrentReserves();
            updateCurrentExchangeRate();
        }
        catch(bytes memory _err) {
            resetReservesAndExchangeRate();
            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
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

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors, address testContract) BaseHandler(pool, quote, collateral, poolInfo, numOfActors, testContract) {} 

    /**************************/
    /*** Lender Functions ***/
    /**************************/

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) useTimestamps {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        amount = constrictToRange(amount, _pool.quoteTokenDust(), 1e30);

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) useTimestamps {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);
    }

    function moveQuoteToken(uint256 actorIndex, uint256 amount, uint256 fromBucketIndex, uint256 toBucketIndex) public useRandomActor(actorIndex) useTimestamps {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        fromBucketIndex = constrictToRange(fromBucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        toBucketIndex   = constrictToRange(toBucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

        amount          = constrictToRange(amount, 1, 1e30);
        
        super.moveQuoteToken(amount, fromBucketIndex, toBucketIndex);
    }

    function addCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) useTimestamps {
        numberOfCalls['BBasicHandler.addCollateral']++;

        amount = constrictToRange(amount, 1e6, 1e30);

        // Action
        super.addCollateral(amount, _lenderBucketIndex);
    }

    function removeCollateral(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) useTimestamps {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        (uint256 lpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        ( , uint256 bucketCollateral, , , ) = _pool.bucketInfo(_lenderBucketIndex);

        if (lpBalance == 0 || bucketCollateral == 0) return; // no value in bucket

        amount = constrictToRange(amount, 1, 1e30);

        // Action
        super.removeCollateral(amount, _lenderBucketIndex);
    }

    function transferLps(uint256 fromActorIndex, uint256 toActorIndex, uint256 lpsToTransfer, uint256 bucketIndex) public useRandomActor(fromActorIndex) useRandomLenderBucket(bucketIndex) useTimestamps {
        (uint256 senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        address receiver = actors[constrictToRange(toActorIndex, 0, actors.length - 1)];
        if(senderLpBalance == 0) {
            super.addQuoteToken(1e24, _lenderBucketIndex);
        }
        (senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);
        lpsToTransfer = constrictToRange(lpsToTransfer, 1, senderLpBalance);

        super.increaseLPsAllowance(receiver, _lenderBucketIndex, lpsToTransfer);
        super.transferLps(_actor, receiver, _lenderBucketIndex);
    }


    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(uint256 actorIndex, uint256 amountToPledge) public useRandomActor(actorIndex) useTimestamps {
        numberOfCalls['BBasicHandler.pledgeCollateral']++;

        uint256 collateralScale = _pool.collateralScale();

        amountToPledge = constrictToRange(amountToPledge, collateralScale, 1e30);

        // Action
        super.pledgeCollateral(amountToPledge);
    }

    function pullCollateral(uint256 actorIndex, uint256 amountToPull) public useRandomActor(actorIndex) useTimestamps {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        amountToPull = constrictToRange(amountToPull, 1, 1e30);

        // Action
        super.pullCollateral(amountToPull);
    } 

    function drawDebt(uint256 actorIndex, uint256 amountToBorrow) public useRandomActor(actorIndex) useTimestamps {
        numberOfCalls['BBasicHandler.drawDebt']++;

        amountToBorrow = constrictToRange(amountToBorrow, 1e6, 1e30);
        
        // Action
        super.drawDebt(amountToBorrow);
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) useTimestamps {
        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay = constrictToRange(amountToRepay, _pool.quoteTokenDust(), 1e30);

        // Action
        super.repayDebt(amountToRepay);
    }
}
