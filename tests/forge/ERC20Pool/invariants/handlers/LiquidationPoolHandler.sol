
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { BasicPoolHandler } from './BasicPoolHandler.sol';

contract UnBoundedLiquidationPoolHandler {
    function kickAuction(address borrower) internal {

    }
}

contract LiquidationPoolHandler is UnBoundedLiquidationPoolHandler, BasicPoolHandler {

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) BasicPoolHandler(pool, quote, collateral, poolInfo, numOfActors) {} 

    function kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) external useRandomActor(kickerIndex) {
        borrowerIndex   = constrictToRange(borrowerIndex, 0, _actors.length - 1);

        address borrower = _actors[borrowerIndex];

        ( , , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime == 0) {
            // (uint256 debt, , ) = ERC20Pool(_pool).borrowerInfo(borrower);
            // if (debt == 0) {
            //     vm.startPrank(borrower);
            //     _drawDebt(borrowerIndex, amount, BORROWER_MIN_BUCKET_INDEX);
            //     vm.stopPrank();
            // }
            // vm.startPrank(_actors[kickerIndex]);
            try _pool.kick(borrower) {}
            catch (bytes memory err){
                require(keccak256(abi.encodeWithSignature("BorrowerOk()")) == keccak256(err));
            }
            // vm.stopPrank();
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }

    function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external useRandomActor(borrowerIndex){
        actorIndex = constrictToRange(actorIndex, 0, _actors.length - 1);

        address borrower = _actor;
        address taker    = _actors[actorIndex];

        ( , , , uint256 kickTime, , , , , ) = _pool.auctionInfo(borrower);

        if (kickTime != 0) {
            _pool.take(borrower, amount, taker, bytes(""));
        }
    }
}