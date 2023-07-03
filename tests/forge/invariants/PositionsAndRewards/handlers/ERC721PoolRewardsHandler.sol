// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { RewardsManager }  from 'src/RewardsManager.sol';
import { PositionManager } from 'src/PositionManager.sol';

import { RewardsPoolHandler }       from './RewardsPoolHandler.sol';
import { ReserveERC721PoolHandler } from '../../ERC721Pool/handlers/ReserveERC721PoolHandler.sol';

contract ERC721PoolRewardsHandler is RewardsPoolHandler, ReserveERC721PoolHandler {

    constructor(
        address rewards_,
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) ReserveERC721PoolHandler(pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_); 

        // Rewards manager
        _rewardsManager = RewardsManager(rewards_);

        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC721_NON_SUBSET_HASH"));
    }

    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_,
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) internal override {
        
        numberOfEpochs_ = constrictToRange(numberOfEpochs_, 1, vm.envOr("MAX_EPOCH_ADVANCE", uint256(2)));

        for (uint256 epoch = 0; epoch <= numberOfEpochs_; epoch ++) {
            // draw some debt and then repay after some times to increase pool earning / reserves 
            (, uint256 claimableReserves, , ) = _pool.reservesInfo();
            if (claimableReserves == 0) {
                uint256 amountToBorrow = _preDrawDebt(amountToAdd_);
                _drawDebt(amountToBorrow);
 
                _repayDebt(type(uint256).max);
            }

            skip(20 days); // epochs are spaced a minimum of 14 days apart

            (, claimableReserves, , ) = _pool.reservesInfo();

            _kickReserveAuction();

            // skip time for price to decrease, large price decrease reduces chances of rewards exceeding rewards contract balance
            skip(60 hours);

            uint256 boundedTakeAmount = constrictToRange(amountToAdd_, claimableReserves / 2, claimableReserves);
            _takeReserves(boundedTakeAmount);

            // exchange rates must be updated so that rewards can be claimed
            indexes_ = _randomizeExchangeRateIndexes(indexes_, bucketSubsetToUpdate_);
            if (indexes_.length != 0) { _updateExchangeRate(indexes_); }
        }
    }
}
