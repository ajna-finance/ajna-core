// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ERC20Pool }                         from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }                  from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }                     from 'src/PoolInfoUtils.sol';
import { _borrowFeeRate, _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                             from "src/libraries/internal/Maths.sol";

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX
}                                    from '../../../base/handlers/unbounded/BaseHandler.sol';
import { UnboundedBasicPoolHandler } from "../../../base/handlers/unbounded/UnboundedBasicPoolHandler.sol";
import { BaseERC721PoolHandler }      from './BaseERC721PoolHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicERC721PoolHandler is UnboundedBasicPoolHandler, BaseERC721PoolHandler {

    function _drawDebt(
        uint256 amount_
    ) internal virtual override updateLocalStateAndPoolInterest {}
}
