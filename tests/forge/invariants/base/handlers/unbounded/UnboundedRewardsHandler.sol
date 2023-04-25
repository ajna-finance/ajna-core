// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { _depositFeeRate }   from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }             from "src/libraries/internal/Maths.sol";

import { BaseHandler } from './BaseHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedRewardsHandler is BaseHandler {


    function _stake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.stake']++;

        try _rewards.stake(tokenId_) {

            //TODO: store staked tokenId's

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _unstake(
        uint256 tokenId_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.unstake']++;

        uint256 actorBalanceBeforeClaim = _quote.balanceOf(_actor);

        try _rewards.unstake(tokenId_) {

            // add to total rewards if actor received reward
            if ((_quote.balanceOf(_actor) - actorBalanceBeforeClaim) != 0) {
                (,,uint256 lastClaimedEpoch) = _rewards.getStakeInfo(tokenId_);
                totalRewardPerEpoch[lastClaimedEpoch] += _quote.balanceOf(_actor) - actorBalanceBeforeClaim;
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}