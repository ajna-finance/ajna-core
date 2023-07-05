// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { ERC20Pool }         from 'src/ERC20Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { PositionManager } from 'src/PositionManager.sol';

import { PositionPoolHandler }  from  './PositionPoolHandler.sol';
import { BaseERC20PoolHandler } from '../../ERC20Pool/handlers/unbounded/BaseERC20PoolHandler.sol';
import { BaseERC721PoolHandler } from '../../ERC721Pool/handlers/unbounded/BaseERC721PoolHandler.sol';
import { MultiplePoolHandler } from './MultiplePoolHandler.sol';

contract MultiplePoolPositionHandler is PositionPoolHandler, MultiplePoolHandler {

    constructor(
        address positions_,
        PoolInfo[] memory pools_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) MultiplePoolHandler(pools_, ajna_, poolInfo_, numOfActors_, testContract_) {

        // Position manager
        _positionManager = PositionManager(positions_);

        // TODO: replace usage of _poolHash variable with calls to tokenId to find out pool type and then the appropriate hash automatically.
        // pool hash for mint() call
        _poolHash = bytes32(keccak256("ERC20_NON_SUBSET_HASH"));
    }

    function _repayBorrowerDebt(
        address borrower_,
        uint256 amount_
    ) updateLocalStateAndPoolInterest internal override {
        address pool = _findBorrowerPool(borrower_);

        if (pool == address(0)) {
            return;
        }

        PoolInfo memory poolInfo = poolInfos[pool];
        if (poolInfo.is721) {
            try ERC721Pool(poolInfo.pool).repayDebt(borrower_, amount_, 0, borrower_, 7388) {
            } catch (bytes memory err) {
                _ensurePoolError(err);
            }
        } else {
            try ERC20Pool(poolInfo.pool).repayDebt(borrower_, amount_, 0, borrower_, 7388) {
            } catch (bytes memory err) {
                _ensurePoolError(err);
            }
        }
    }

    function _findBorrowerPool(address borrower_) internal view returns (address pool_) {
        // find an ERC20 or ERC721 Pool that the borrower has a position in
        for (uint256 i = 0; i < _pools.length; i++) {
            (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo( _pools[i].pool, borrower_);

            if (debt != 0 || collateral != 0) {
                pool_ = _pools[i].pool;
                break;
            }
        }
    }

}
