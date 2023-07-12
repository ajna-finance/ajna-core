// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { RewardsManager }  from 'src/RewardsManager.sol';
import { PositionManager } from 'src/PositionManager.sol';
import { Pool }            from 'src/base/Pool.sol';
import { ERC20Pool }       from 'src/ERC20Pool.sol';

import { TokenWithNDecimals }          from '../../../utils/Tokens.sol';

import { RewardsPoolHandler }      from './RewardsPoolHandler.sol';
import { ReserveERC20PoolHandler } from '../../ERC20Pool/handlers/ReserveERC20PoolHandler.sol';

contract ERC20PoolRewardsHandler is RewardsPoolHandler, ReserveERC20PoolHandler {

    constructor(
        address rewards_,
        address positions_,
        PoolInfo[10] memory pools_,
        address ajna_,
        address poolInfoUtils_,
        uint256 numOfActors_,
        address testContract_
    ) ReserveERC20PoolHandler(pools_[0].pool, ajna_, pools_[0].quote, pools_[0].collateral, poolInfoUtils_, numOfActors_, testContract_) {

        for (uint256 i = 0; i < pools_.length; i++) {
            _pools.push(pools_[i]);
        }

        // Position manager
        _positionManager = PositionManager(positions_); 

        // Rewards manager
        _rewardsManager = RewardsManager(rewards_);

        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC20_NON_SUBSET_HASH"));
    }

    function _advanceEpochRewardStakers(
        uint256 amountToAdd_,
        uint256[] memory indexes_,
        uint256 numberOfEpochs_,
        uint256 bucketSubsetToUpdate_
    ) internal override {

        numberOfEpochs_ = constrictToRange(numberOfEpochs_, 1, vm.envOr("MAX_EPOCH_ADVANCE", uint256(5)));

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

    modifier useRandomPool(uint256 poolIndex) override {
        poolIndex   = bound(poolIndex, 0, _pools.length - 1);
        _pool       = Pool(_pools[poolIndex].pool);
        _collateral = TokenWithNDecimals(_pools[poolIndex].collateral);
        _quote      = TokenWithNDecimals(_pools[poolIndex].quote);
        _erc20Pool = ERC20Pool(_pools[poolIndex].pool);

        _;
    }

}
