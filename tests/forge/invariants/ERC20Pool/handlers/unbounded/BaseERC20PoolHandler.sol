// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';

import { TokenWithNDecimals } from '../../../../utils/Tokens.sol';

import { BaseHandler } from '../../../base/handlers/unbounded/BaseHandler.sol';

abstract contract BaseERC20PoolHandler is BaseHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    // Token
    TokenWithNDecimals internal _collateral;

    // ERC20Pool
    ERC20Pool internal _erc20Pool;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, ajna_, poolInfo_, testContract_) {

        LENDER_MIN_BUCKET_INDEX = vm.envOr("BUCKET_INDEX_ERC20", uint256(2570));
        LENDER_MAX_BUCKET_INDEX = LENDER_MIN_BUCKET_INDEX + vm.envOr("NO_OF_BUCKETS", uint256(3)) - 1;

        MIN_QUOTE_AMOUNT = vm.envOr("MIN_QUOTE_AMOUNT_ERC20", uint256(1e3));
        MAX_QUOTE_AMOUNT = vm.envOr("MAX_QUOTE_AMOUNT_ERC20", uint256(1e30));

        MIN_DEBT_AMOUNT = vm.envOr("MIN_DEBT_AMOUNT", uint256(0));
        MAX_DEBT_AMOUNT = vm.envOr("MAX_DEBT_AMOUNT", uint256(1e28));

        MIN_COLLATERAL_AMOUNT = vm.envOr("MIN_COLLATERAL_AMOUNT_ERC20", uint256(1e3));
        MAX_COLLATERAL_AMOUNT = vm.envOr("MAX_COLLATERAL_AMOUNT_ERC20", uint256(1e30));

        for (uint256 bucket = LENDER_MIN_BUCKET_INDEX; bucket <= LENDER_MAX_BUCKET_INDEX; bucket++) {
            buckets.add(bucket);
        }

        // Pool
        _erc20Pool  = ERC20Pool(pool_);

        // Tokens
        _collateral = TokenWithNDecimals(_erc20Pool.collateralAddress());

        // Actors
        actors = _buildActors(numOfActors_);
    }

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _buildActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actorsAddress = new address[](noOfActors_);

        for (uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actorsAddress[i] = actor;

            vm.startPrank(actor);
            _ensureQuoteAmount(actor, 1e45);

            _collateral.mint(actor, 1e45);
            _collateral.approve(address(_pool), type(uint256).max);

            vm.stopPrank();
        }

        return actorsAddress;
    }

    function _repayBorrowerDebt(
        address borrower_,
        uint256 amount_
    ) updateLocalStateAndPoolInterest internal override {
        try _erc20Pool.repayDebt(borrower_, amount_, 0, borrower_, 7388) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

}