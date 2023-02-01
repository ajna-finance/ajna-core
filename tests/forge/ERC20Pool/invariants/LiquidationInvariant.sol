// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { TestBase } from './TestBase.sol';

import { LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX, BORROWER_MIN_BUCKET_INDEX } from './handlers/BasicPoolHandler.sol';
import { LiquidationPoolHandler } from './handlers/LiquidationPoolHandler.sol';
import { BasicInvariants, Handler } from './BasicInvariants.t.sol';

contract LiquidationInvariant is BasicInvariants {
    
    LiquidationPoolHandler internal _liquidationPoolHandler;

    function setUp() public override virtual{

        super.setUp();

        excludeContract(address(_basicPoolHandler));

        _liquidationPoolHandler = new LiquidationPoolHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), NUM_ACTORS);
        _handler = address(_liquidationPoolHandler);
    }

    // checks sum of all kicker bond is equal to total pool bond
    function invariant_bond() public {
        uint256 actorCount = Handler(_handler).getActorsCount();
        uint256 totalKickerBond;
        for(uint256 i = 0; i < actorCount; i++) {
            address kicker = Handler(_handler)._actors(i);
            (, uint256 bond) = _pool.kickerInfo(kicker);
            totalKickerBond += bond;
        }

        uint256 totalBondInAuction;

        for(uint256 i = 0; i < actorCount; i++) {
            address borrower = Handler(_handler)._actors(i);
            (, , uint256 bondSize, , , , , , ) = _pool.auctionInfo(borrower);
            totalBondInAuction += bondSize;
        }

        require(totalBondInAuction == totalKickerBond, "Incorrect bond");

        (uint256 totalPoolBond, , ) = _pool.reservesInfo();

        require(totalPoolBond == totalKickerBond, "Incorrect bond");
    }

}