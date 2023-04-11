// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationPoolHandler }               from '../../base/handlers/LiquidationPoolHandler.sol';
import { BasicERC721PoolHandler }                from './BasicERC721PoolHandler.sol';

contract LiquidationERC721PoolHandler is LiquidationPoolHandler, BasicERC721PoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BasicERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    function _constrictTakeAmount(uint256 amountToTake_) internal view override returns(uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToTake_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
    }

}