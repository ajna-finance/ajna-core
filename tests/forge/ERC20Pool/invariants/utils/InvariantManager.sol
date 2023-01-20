// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "forge-std/console.sol";
import '@std/Test.sol';
import '@std/Vm.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { InvariantActor }   from './InvariantActor.sol';

uint256 constant LENDER_MIN_BUCKET_INDEX = 2570;
uint256 constant LENDER_MAX_BUCKET_INDEX = 2590;

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;

function constrictToRange(
    uint256 x,
    uint256 min,
    uint256 max
) pure returns (uint256 result) {
    require(max >= min, "MAX_LESS_THAN_MIN");

    uint256 size = max - min;

    if (size == 0) return min;            // Using max would be equivalent as well.
    if (max != type(uint256).max) size++; // Make the max inclusive.

    // Ensure max is inclusive in cases where x != 0 and max is at uint max.
    if (max == type(uint256).max && x != 0) x--; // Accounted for later.

    if (x < min) x += size * (((min - x) / size) + 1);

    result = min + ((x - min) % size);

    // Account for decrementing x to make max inclusive.
    if (max == type(uint256).max && x != 0) result++;
}


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract InvariantActorManager is Test{
    address internal _pool;
    address internal _quote;
    address internal _collateral;
    address internal _poolInfo;

    InvariantActor[] public actors;

    constructor(address pool, address quote, address collateral, address poolInfo) {
        _pool       = pool;
        _quote      = quote;
        _collateral = collateral;
        _poolInfo   = poolInfo;
    }

    function createActor() external {
        console.log("M: creatA");
        InvariantActor newActor = new InvariantActor(_pool, _quote, _collateral);
        actors.push(newActor);
    }

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) external {
        console.log("M: add");
        amount = constrictToRange(amount, 1, 1000000 * 1e18);
        bucketIndex  = constrictToRange(bucketIndex , LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        actors[constrictToRange(actorIndex, 0, actors.length - 1)].addQuoteToken(amount, bucketIndex);
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) external {
        console.log("M: remove");
        actorIndex = constrictToRange(actorIndex, 0, actors.length - 1);
        bucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        uint256 lpBalance = actors[actorIndex].lenderLpBalance(bucketIndex);

        if ( lpBalance > 0 ) {
            amount = constrictToRange(amount, 1, 1000000 * 1e18);
            actors[actorIndex].removeQuoteToken(amount, bucketIndex);
        }
    }

    function _drawDebt(uint256 actorIndex, uint256 amount, uint256 limitIndex) internal {
        actorIndex = constrictToRange(actorIndex, 0, actors.length - 1);

        (uint256 minDebt, , , ) = PoolInfoUtils(_poolInfo).poolUtilizationInfo(_pool);

        if (amount > minDebt) amount = minDebt + 100 * 1e18;

        uint256 poolQuoteBalance = Token(_quote).balanceOf(_pool);
        if (amount > poolQuoteBalance) {
            actors[0].addQuoteToken(amount, LENDER_MAX_BUCKET_INDEX);
        }

        // pledge slightly more than required collateral to draw debt
        uint256 collateralToPledge = (amount * 1e18 / PoolInfoUtils(_poolInfo).hpb(_pool)) * 101 / 100;  

        limitIndex = constrictToRange(limitIndex, BORROWER_MIN_BUCKET_INDEX, BORROWER_MAX_BUCKET_INDEX);

        actors[actorIndex].drawDebt(amount, limitIndex, collateralToPledge);
        
        // skip some time for more interest and make borrower under collateralized
        vm.warp(block.timestamp + 200 days);
    }

    function drawDebt(uint256 actorIndex, uint256 amount, uint256 limitIndex) external {
        console.log("M: draw");
        _drawDebt(actorIndex, amount, limitIndex);
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay) external {
        console.log("M: repay");
        actorIndex = constrictToRange(actorIndex, 0, actors.length - 1);

        actors[actorIndex].repayDebt(amountToRepay);
    }

    function kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) external {
        console.log("M: kick");
        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);
        kickerIndex   = constrictToRange(kickerIndex, 0, actors.length - 1);
        address borrower = address(actors[borrowerIndex]);

        ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

        if (kickTime == 0) {
            (uint256 debt, , ) = ERC20Pool(_pool).borrowerInfo(borrower);
            if (debt == 0) {
                _drawDebt(borrowerIndex, amount, BORROWER_MIN_BUCKET_INDEX);
            }
            actors[kickerIndex].kickAuction(borrower);
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }

    function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external {
        console.log("M: take");
        borrowerIndex = constrictToRange(borrowerIndex, 0, actors.length - 1);
        actorIndex    = constrictToRange(actorIndex, 0, actors.length - 1);

        address borrower = address(actors[borrowerIndex]);
        address taker    = address(actors[actorIndex]);

        ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

        if (kickTime != 0) {
            actors[actorIndex].takeAuction(borrower, amount, taker);
        }

    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }
}