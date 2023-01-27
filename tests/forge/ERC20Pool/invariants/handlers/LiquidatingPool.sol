
// SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.14;

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