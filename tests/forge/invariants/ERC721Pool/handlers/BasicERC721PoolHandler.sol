// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { PoolInfoUtils, _collateralization } from 'src/PoolInfoUtils.sol';
import { Maths }                             from 'src/libraries/internal/Maths.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX,
    BORROWER_MIN_BUCKET_INDEX,
    MIN_AMOUNT,
    MAX_AMOUNT
}                                         from '../../base/handlers/unbounded/BaseHandler.sol';
import { BasicPoolHandler }               from '../../base/handlers/BasicPoolHandler.sol';
import { UnboundedBasicPoolHandler }      from '../../base/handlers/unbounded/UnboundedBasicPoolHandler.sol';
import { UnboundedBasicERC721PoolHandler } from './unbounded/UnboundedBasicERC721PoolHandler.sol';
import { BaseERC721PoolHandler }           from './unbounded/BaseERC721PoolHandler.sol';

/**
 *  @dev this contract manages multiple actors
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects an actor contract to make a txn
 */ 
contract BasicERC721PoolHandler is UnboundedBasicERC721PoolHandler, BasicPoolHandler {

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

    }

    function _preDrawDebt(
        uint256 amountToBorrow_
    ) internal override returns (uint256 boundedAmount_) {}
}
