// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import '@std/Test.sol';
import '@std/Vm.sol';
import "@std/console.sol";

import { ERC20Pool }                         from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }                  from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils, _collateralization } from 'src/PoolInfoUtils.sol';

import "src/libraries/internal/Maths.sol";

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    BaseHandler
}                from './BaseHandler.sol';
import { Token } from '../../../utils/Tokens.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicPoolHandler is BaseHandler {

    /************************/
    /*** Lender Functions ***/
    /************************/

    function addQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        (uint256 poolDebt, , )   = _pool.debtInfo();
        uint256 lupIndex         = _pool.depositIndex(poolDebt);
        (uint256 interestRate, ) = _pool.interestRateInfo();

        try _pool.addQuoteToken(amount_, bucketIndex_, block.timestamp + 1 minutes) {
        
            // lender's deposit time updates when lender adds Quote token into pool
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;

            // deposit fee is charged if deposit is added below lup
            if (lupIndex < bucketIndex_) {
                amount_ = Maths.wmul(
                    amount_,
                    1e18 - Maths.wdiv(interestRate, 365 * 1e18)
                );
            }

            _fenwickAdd(amount_, bucketIndex_);

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");

        } catch (bytes memory _err) {
            _resetReservesAndExchangeRate();

            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("BucketBankruptcyBlock()"))
            );
        }

        // skip some time to avoid early withdraw penalty
        vm.warp(block.timestamp + 25 hours);
    }

    function removeQuoteToken(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);

        if (lpBalanceBefore == 0) {
            amount_ = constrictToRange(amount_, 1, 1e30);
            addQuoteToken(amount_, bucketIndex_);
        }

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        try _pool.removeQuoteToken(amount_, bucketIndex_) returns (uint256 removedAmount_, uint256) {

            _fenwickRemove(removedAmount_, bucketIndex_);

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");

        } catch (bytes memory _err){
            _resetReservesAndExchangeRate();

            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
                err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
                err == keccak256(abi.encodeWithSignature("NoClaim()")));
        }
    }

    function moveQuoteToken(
        uint256 amount_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        if(fromIndex_ == toIndex_) return;

        (uint256 lpBalance, ) = _pool.lenderInfo(fromIndex_, _actor);

        if (lpBalance == 0) addQuoteToken(amount_, fromIndex_);
        
        _fenwickAccrueInterest();

        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        (uint256 poolDebt, , ) = _pool.debtInfo();
        uint256 lupIndex       = _pool.depositIndex(poolDebt);

        try _pool.moveQuoteToken(
            amount_,
            fromIndex_,
            toIndex_,
            block.timestamp + 1 minutes
        ) returns (uint256, uint256, uint256 movedAmount) {

            _fenwickAdd(movedAmount, toIndex_);

            // deposit fee is charged if deposit is moved from above the lup to below the lup
            if (fromIndex_ >= lupIndex && toIndex_ < lupIndex) {
                movedAmount = Maths.wdiv(
                    Maths.wmul(movedAmount, 365 * 1e18),
                    364 * 1e18
                );
            
                _fenwickRemove(movedAmount, fromIndex_);
            }

            (, uint256 fromBucketDepositTime) = _pool.lenderInfo(fromIndex_, _actor);
            (, uint256 toBucketDepositTime)   = _pool.lenderInfo(toIndex_,    _actor);
            
            // lender's deposit time updates when lender moves Quote token from one bucket to another
            lenderDepositTime[_actor][toIndex_] = Maths.max(fromBucketDepositTime, toBucketDepositTime);

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

        } catch (bytes memory _err){
            _resetReservesAndExchangeRate();

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

    function addCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);
        
        _fenwickAccrueInterest();
        _updatePoolState();
        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        _pool.addCollateral(amount_, bucketIndex_, block.timestamp + 1 minutes);

        // lender's deposit time updates when lender adds collateral token into pool
        lenderDepositTime[_actor][bucketIndex_] = block.timestamp;

        _updateCurrentExchangeRate();
        _updateCurrentReserves();

        // Post condition
        (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex_, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");

        // skip some time to avoid early withdraw penalty
        vm.warp(block.timestamp + 25 hours);
    }

    function removeCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);

        if(lpBalanceBefore == 0) addCollateral(amount_, bucketIndex_);

        (lpBalanceBefore, ) = _pool.lenderInfo(bucketIndex_, _actor);
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        try _pool.removeCollateral(amount_, bucketIndex_) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

            // Post condition
            (uint256 lpBalanceAfter, ) = _pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfter < lpBalanceBefore, "LP balance should decrease");

        } catch (bytes memory _err){
            _resetReservesAndExchangeRate();

            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientLPs()")) || 
                err == keccak256(abi.encodeWithSignature("AuctionNotCleared()"))
            );
        }
    }

    function increaseLPsAllowance(
        address receiver_,
        uint256 bucketIndex_,
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        // approve as transferor
        address[] memory transferors = new address[](1);
        transferors[0] = receiver_;
        _pool.approveLPsTransferors(transferors);

        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount_;
        _pool.increaseLPsAllowance(receiver_, buckets, amounts);
    }

    function transferLps(
        address sender_,
        address receiver_,
        uint256 bucketIndex_
    ) internal useTimestamps resetAllPreviousLocalState {
        uint256[] memory buckets = new uint256[](1);
        buckets[0] = bucketIndex_;

        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        changePrank(receiver_);

        try _pool.transferLPs(sender_, receiver_, buckets) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

            (, uint256 senderDepositTime)   = _pool.lenderInfo(bucketIndex_, sender_);
            (, uint256 receiverDepositTime) = _pool.lenderInfo(bucketIndex_, receiver_);

            // receiver's deposit time updates when receiver receives lps
            lenderDepositTime[receiver_][bucketIndex_] = Maths.max(senderDepositTime, receiverDepositTime);

        } catch{
            _resetReservesAndExchangeRate();
        }
    }

    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        _pool.drawDebt(_actor, 0, 0, amount_);   

        shouldExchangeRateChange = false;
        shouldReserveChange      = false;
   
        _updateCurrentExchangeRate();
        _updateCurrentReserves();

    }

    function pullCollateral(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.pullCollateral']++;
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousExchangeRate();
        _updatePreviousReserves();

        try _pool.repayDebt(_actor, 0, amount_, _actor, 7388) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentExchangeRate();
            _updateCurrentReserves();

        } catch (bytes memory _err){
            _resetReservesAndExchangeRate();

            bytes32 err = keccak256(_err);
            require(
                err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
                err == keccak256(abi.encodeWithSignature("InsufficientCollateral()")) ||
                err == keccak256(abi.encodeWithSignature("AuctionActive()"))
            );
        }
    }
 
    function drawDebt(
        uint256 amount_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));

        if (amount_ < minDebt) amount_ = minDebt + 1;

        // TODO: Need to constrain amount so LUP > HTP

        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (amount_ > poolQuoteBalance) addQuoteToken(amount_ * 2, LENDER_MAX_BUCKET_INDEX);

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
        uint256 bucket = _pool.depositIndex(amount_ + poolDebt) - 1;

        uint256 price = _poolInfo.indexToPrice(bucket);

        uint256 collateralToPledge = ((amount_ * 1e18 + price / 2) / price) * 101 / 100 + 1;
        
        _fenwickAccrueInterest();
        _updatePoolState();

        _updatePreviousReserves();
        _updatePreviousExchangeRate();

        try _pool.drawDebt(_actor, amount_, 7388, collateralToPledge) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = true;

            _updateCurrentReserves();
            _updateCurrentExchangeRate();

            (uint256 interestRate, ) = _pool.interestRateInfo();

            // reserve should increase by origination fee on draw debt
            drawDebtIncreaseInReserve = Maths.wmul(
                amount_,
                Maths.max(
                    Maths.wdiv(interestRate, 52 * 1e18), 0.0005 * 1e18
                )
            );

        } catch (bytes memory _err){
            _resetReservesAndExchangeRate();

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

    function repayDebt(
        uint256 amountToRepay_
    ) internal useTimestamps resetAllPreviousLocalState {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        // Pre condition
        (uint256 debt, , ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        if (debt == 0) drawDebt(amountToRepay_);
        
        _fenwickAccrueInterest();
        _updatePoolState();
        _updatePreviousReserves();
        _updatePreviousExchangeRate();

        try _pool.repayDebt(_actor, amountToRepay_, 0, _actor, 7388) {

            shouldExchangeRateChange = false;
            shouldReserveChange      = false;

            _updateCurrentReserves();
            _updateCurrentExchangeRate();

        } catch(bytes memory _err) {
            _resetReservesAndExchangeRate();

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

    constructor(
        address pool_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    } 

    /**************************/
    /*** Lender Functions ***/
    /**************************/

    function addQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addQuoteToken']++;

        amount_ = constrictToRange(amount_, _pool.quoteTokenDust(), 1e30);

        // Action
        super.addQuoteToken(amount_, _lenderBucketIndex);
    }

    function removeQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        uint256 poolBalance = _quote.balanceOf(address(_pool));

        if (poolBalance < amount_) return; // (not enough quote token to withdraw / quote tokens are borrowed)

        // Action
        super.removeQuoteToken(amount_, _lenderBucketIndex);
    }

    function moveQuoteToken(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 fromBucketIndex_,
        uint256 toBucketIndex_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.moveQuoteToken']++;

        fromBucketIndex_ = constrictToRange(
            fromBucketIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );
        toBucketIndex_ = constrictToRange(
            toBucketIndex_,
            LENDER_MIN_BUCKET_INDEX,
            LENDER_MAX_BUCKET_INDEX
        );

        amount_ = constrictToRange(amount_, 1, 1e30);
        
        super.moveQuoteToken(amount_, fromBucketIndex_, toBucketIndex_);
    }

    function addCollateral(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.addCollateral']++;

        amount_ = constrictToRange(amount_, 1e6, 1e30);

        // Action
        super.addCollateral(amount_, _lenderBucketIndex);
    }

    function removeCollateral(
        uint256 actorIndex_,
        uint256 amount_,
        uint256 bucketIndex_
    ) public useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.removeCollateral']++;

        (uint256 lpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        ( , uint256 bucketCollateral, , , ) = _pool.bucketInfo(_lenderBucketIndex);

        if (lpBalance == 0 || bucketCollateral == 0) return; // no value in bucket

        amount_ = constrictToRange(amount_, 1, 1e30);

        // Action
        super.removeCollateral(amount_, _lenderBucketIndex);
    }

    function transferLps(
        uint256 fromActorIndex_,
        uint256 toActorIndex_,
        uint256 lpsToTransfer_,
        uint256 bucketIndex_
    ) public useRandomActor(fromActorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps {
        (uint256 senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        address receiver = actors[constrictToRange(toActorIndex_, 0, actors.length - 1)];

        if(senderLpBalance == 0) super.addQuoteToken(1e24, _lenderBucketIndex);

        (senderLpBalance, ) = _pool.lenderInfo(_lenderBucketIndex, _actor);

        lpsToTransfer_ = constrictToRange(lpsToTransfer_, 1, senderLpBalance);

        super.increaseLPsAllowance(receiver, _lenderBucketIndex, lpsToTransfer_);
        super.transferLps(_actor, receiver, _lenderBucketIndex);
    }


    /**************************/
    /*** Borrower Functions ***/
    /**************************/

    function pledgeCollateral(
        uint256 actorIndex_,
        uint256 amountToPledge_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.pledgeCollateral']++;

        uint256 collateralScale = _pool.collateralScale();

        amountToPledge_ = constrictToRange(amountToPledge_, collateralScale, 1e30);

        // Action
        super.pledgeCollateral(amountToPledge_);
    }

    function pullCollateral(
        uint256 actorIndex_,
        uint256 amountToPull_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.pullCollateral']++;

        amountToPull_ = constrictToRange(amountToPull_, 1, 1e30);

        // Action
        super.pullCollateral(amountToPull_);
    } 

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.drawDebt']++;

        amountToBorrow_ = constrictToRange(amountToBorrow_, 1e6, 1e30);
        
        // Action
        super.drawDebt(amountToBorrow_);
    }

    function repayDebt(
        uint256 actorIndex_,
        uint256 amountToRepay_
    ) public useRandomActor(actorIndex_) useTimestamps {
        numberOfCalls['BBasicHandler.repayDebt']++;

        amountToRepay_ = constrictToRange(amountToRepay_, _pool.quoteTokenDust(), 1e30);

        // Action
        super.repayDebt(amountToRepay_);
    }
}
