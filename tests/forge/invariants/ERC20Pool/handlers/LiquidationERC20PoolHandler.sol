// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationPoolHandler }               from '../../base/handlers/LiquidationPoolHandler.sol';
import { BasicERC20PoolHandler }                from './BasicERC20PoolHandler.sol';

contract LiquidationERC20PoolHandler is LiquidationPoolHandler, BasicERC20PoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BasicERC20PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    function _constrictTakeAmount(uint256 amountToTake_) internal view override returns(uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToTake_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
    }

}