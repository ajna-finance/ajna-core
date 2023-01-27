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

uint256 constant LENDER_MIN_BUCKET_INDEX = 2570;
uint256 constant LENDER_MAX_BUCKET_INDEX = 2590;

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract UnboundedBasicPoolHandler is Test, BaseHandler {

    // Lender tracking
    mapping(address => uint256[]) public touchedBuckets;

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BaseHandler(pool, quote, collateral, poolInfo) {
        _actors     = _getActors(numOfActors);
    } 

    modifier useRandomActor(uint256 actorIndex) {
        vm.stopPrank();

        address actor = _actors[constrictToRange(actorIndex, 0, _actors.length - 1)];
        _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier useRandomLenderBucket(uint256 bucketIndex) {
        uint256[] storage lenderBucketIndexes = touchedBuckets[_actor];
        if (lenderBucketIndexes.length < 3) {
            // if actor has touched less than three buckets, add a new bucket
            _lenderBucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
            lenderBucketIndexes.push(_lenderBucketIndex);
        } else {
            // if actor has touched more than three buckets, reuse one of the touched buckets
            _lenderBucketIndex = lenderBucketIndexes[constrictToRange(bucketIndex, 0, lenderBucketIndexes.length - 1)];
        }
        _;
    }
 
    function _getActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actors = new address[](noOfActors_);
        for(uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actors[i] = actor;
        }
        return actors;
    }

    function getActorsCount() external view returns(uint256) {
        return _actors.length;
    }

    /**************************************************************************************************************************************/
    /*** Lender Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function _addQuoteToken(uint256 amount, uint256 bucket) internal {
        ERC20Pool(_pool).addQuoteToken(amount, bucket);
    }

    function addQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.addQuoteToken']++;

        uint256 totalSupply = Token(_quote).totalSupply();
        uint256 minDeposit = totalSupply == 0 ? 1 : Token(_quote).balanceOf(address(_actor)) / totalSupply + 1;
        amount = constrictToRange(amount, minDeposit, 1e36);

        Token(_quote).mint(_actor, amount);
        Token(_quote).approve(_pool, amount);

        _addQuoteToken(amount, bucketIndex);
    }

    function _removeQuoteToken(uint256 amount, uint256 bucket) internal {
        ERC20Pool(_pool).removeQuoteToken(amount, bucket);
    }

    function removeQuoteToken(uint256 amount, uint256 bucketIndex) internal {
        numberOfCalls['UBBasicHandler.removeQuoteToken']++;

        _removeQuoteToken(amount, bucketIndex);
    }

    /**************************************************************************************************************************************/
    /*** Borrower Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    function _drawDebt(uint256 amountToBorrow, uint256 limitIndex, uint256 collateralToPledge) internal {
        // ERC20Pool(_pool).drawDebt(_actor, amountToBorrow, limitIndex, collateralToPledge);
        try ERC20Pool(_pool).drawDebt(_actor, amountToBorrow, limitIndex, collateralToPledge) {
            console.log("success");
        } catch {
            console.log("amountToBorrow", amountToBorrow);
            console.log("collateralToPledge", collateralToPledge);
        }
        // skip some time for more interest and make borrower under collateralized
        // vm.warp(block.timestamp + 200 days);
    }

    function drawDebt(uint256 amount, uint256 collateralToPledge) public virtual {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        // uint256 totalSupply = Token(_quote).totalSupply();
        // uint256 minDeposit = totalSupply == 0 ? 1 : Token(_quote).balanceOf(address(_actor)) / totalSupply + 1;
        // amount = constrictToRange(amount, minDeposit, 1e36);

        Token(_collateral).mint(_actor, collateralToPledge);
        Token(_collateral).approve(_pool, collateralToPledge);

        _drawDebt(amount, 7388, collateralToPledge); 
    }

    function _repayDebt(address _actor, uint256 amountToRepay) internal {

        Token(_quote).mint(_actor, amountToRepay);
        Token(_quote).approve(_pool, amountToRepay);

        ERC20Pool(_pool).repayDebt(_actor, amountToRepay, 0);
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
        (uint256 lpBalanceBefore, ) = ERC20Pool(_pool).lenderInfo(_lenderBucketIndex, _actor);

        // uint256 totalSupply = Token(_quote).totalSupply();
        // console.log("totalSupply", totalSupply);

        // uint256 minDeposit = totalSupply == 0 ? 1 : Token(_quote).balanceOf(address(_actor)) / totalSupply + 1;
        // console.log("minDepo", minDeposit);

        // amount = constrictToRange(amount, minDeposit, 1e36);

        // Action
        super.addQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = ERC20Pool(_pool).lenderInfo(_lenderBucketIndex, _actor);
        require(lpBalanceAfter > lpBalanceBefore, "LP balance should increase");
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) public useRandomActor(actorIndex) useRandomLenderBucket(bucketIndex) {

        numberOfCalls['BBasicHandler.removeQuoteToken']++;

        // Pre condition
        (uint256 lpBalanceBefore, ) = ERC20Pool(_pool).lenderInfo(_lenderBucketIndex, _actor);

        if (lpBalanceBefore == 0) return; // no value in bucket

        // get max amount of quote actor has in bucket
        uint256 deposit = PoolInfoUtils(_poolInfo).lpsToQuoteTokens(_pool, lpBalanceBefore, _lenderBucketIndex);

        amount = constrictToRange(amount, 1, deposit);

        // Action
        super.removeQuoteToken(amount, _lenderBucketIndex);

        // Post condition
        (uint256 lpBalanceAfter, ) = ERC20Pool(_pool).lenderInfo(_lenderBucketIndex, _actor);
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

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = PoolInfoUtils(_poolInfo).poolUtilizationInfo(_pool);
        if (amountToBorrow < minDebt) amountToBorrow = minDebt + 1;


        // TODO: Need to constrain amountToBorrow so LUP > HTP


        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = Token(_quote).balanceOf(_pool);

        if (amountToBorrow > poolQuoteBalance) {
            addQuoteToken(amountToBorrow, LENDER_MAX_BUCKET_INDEX);
        }


        // 3. drawing of addition debt will make them under collateralized
        uint256 lup = PoolInfoUtils(_poolInfo).lup(_pool);
        (debt, collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);

        if (_collateralization(debt, collateral, lup) < 1) {
            _repayDebt(_actor, debt);
            (debt, collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
            require(debt == 0, "borrower has debt");
        }


        // 4. borrower should have sufficent collateral to draw debt 
        // (debt, collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
        // uint256 collateralToPledge = (amountToBorrow + debt * 1e18 / PoolInfoUtils(_poolInfo).hpb(_pool)) * 101 / 100;  

        uint256 poolPrice = PoolInfoUtils(_poolInfo).lup(_pool);
        poolPrice = poolPrice == 1_004_968_987606512354182109771 ? PoolInfoUtils(_poolInfo).hpb(_pool) : poolPrice;
        uint256 collateralToPledge = amountToBorrow / poolPrice * 2 * 10 * 1e18;
        // require(poolPrice > 0, "poolPrice should be > 0");
        // if (amountToBorrow > 0 ) require(collateralToPledge > 0, "collateralToPledge should be > 0");
        
        // Action
        super.drawDebt(amountToBorrow, collateralToPledge);
        
        // Post Condition
    }

    // function repayDebt(uint256 actorIndex, uint256 amountToRepay) public useRandomActor(actorIndex) {

    //     // Pre condition
    //     (uint256 debt, uint256 collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
    //     if (debt == 0) return;

    //     // Action
    //     _repayDebt(_actor, amountToRepay, 0);

    //     // Post condition
    //     (debt, collateral, ) = PoolInfoUtils(_poolInfo).borrowerInfo(address(_pool), _actor);
    //     require(debt == 0, "borrower has debt");
    // }


    // function _drawDebt(uint256 amount, uint256 limitIndex, uint256 collateralToPledge) internal {
    //     ERC20Pool(_pool).drawDebt(_actor, amount, limitIndex, collateralToPledge);

    //     // skip some time for more interest and make borrower under collateralized
    //     vm.warp(block.timestamp + 200 days);
    // }

    // function drawDebt(uint256 actorIndex, uint256 amount, uint256 limitIndex) external useRandomActor(actorIndex) useRandomBucketBorrower(limitIndex) {
    //     (uint256 minDebt, , , ) = PoolInfoUtils(_poolInfo).poolUtilizationInfo(_pool);

    //     if (amount > minDebt) amount = minDebt + 100 * 1e18;

    //     uint256 poolQuoteBalance = Token(_quote).balanceOf(_pool);
    //     if (amount > poolQuoteBalance) {
    //         _addQuoteToken(amount, LENDER_MAX_BUCKET_INDEX);
    //     }

    //     // pledge slightly more than required collateral to draw debt
    //     uint256 collateralToPledge = (amount * 1e18 / PoolInfoUtils(_poolInfo).hpb(_pool)) * 101 / 100;  

    //     _drawDebt(amount, _bucketBorrower, collateralToPledge);
        
    // }


    // function kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) external {
    //     console.log("M: kick");
    //     borrowerIndex = constrictToRange(borrowerIndex, 0, _actors.length - 1);
    //     kickerIndex   = constrictToRange(kickerIndex, 0, _actors.length - 1);

    //     address borrower = _actors[borrowerIndex];

    //     ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

    //     if (kickTime == 0) {
    //         (uint256 debt, , ) = ERC20Pool(_pool).borrowerInfo(borrower);
    //         if (debt == 0) {
    //             vm.startPrank(borrower);
    //             _drawDebt(borrowerIndex, amount, BORROWER_MIN_BUCKET_INDEX);
    //             vm.stopPrank();
    //         }
    //         vm.startPrank(_actors[kickerIndex]);
    //         ERC20Pool(_pool).kick(borrower);
    //         vm.stopPrank();
    //     }

    //     // skip some time for more interest
    //     vm.warp(block.timestamp + 2 hours);
    // }

    // function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external useRandomActor(borrowerIndex){
    //     console.log("M: take");
    //     actorIndex = constrictToRange(actorIndex, 0, _actors.length - 1);

    //     address borrower = _actor;
    //     address taker    = _actors[actorIndex];

    //     ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

    //     if (kickTime != 0) {
    //         ERC20Pool(_pool).take(borrower, amount, taker, bytes(""));
    //     }
    // }

    // function getActorsCount() external view returns(uint256) {
    //     return _actors.length;
    // }
}
