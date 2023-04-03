// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Pool }             from 'src/base/Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { Maths }            from 'src/libraries/internal/Maths.sol';

import { NFTCollateralToken } from '../../utils/Tokens.sol';

import {
    LENDER_MIN_BUCKET_INDEX,
    LENDER_MAX_BUCKET_INDEX
} from '../base/handlers/unbounded/BaseHandler.sol';

import { BasicERC721PoolHandler } from './handlers/BasicERC721PoolHandler.sol';
import { BasicInvariants }       from '../base/BasicInvariants.t.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';

// contains invariants for the test
contract BasicERC721PoolInvariants is BasicInvariants {

    uint256               internal constant NUM_ACTORS = 10;

    NFTCollateralToken     internal _collateral;
    ERC721Pool             internal _erc721pool;
    ERC721Pool             internal _impl;
    ERC721PoolFactory      internal _erc721poolFactory;
    BasicERC721PoolHandler internal _basicERC721PoolHandler;

    function setUp() public override virtual{

        super.setUp();

        uint256[] memory tokenIds;
        _collateral        = new NFTCollateralToken();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _impl              = _erc721poolFactory.implementation();
        _erc721pool        = ERC721Pool(_erc721poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18));
        _pool              = Pool(address(_erc721pool));

        _basicERC721PoolHandler = new BasicERC721PoolHandler(
            address(_erc721pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_basicERC721PoolHandler);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_erc721pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_impl));

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( , , , , ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_erc721pool), bucketIndex);
            previousBucketExchangeRate[bucketIndex] = exchangeRate;
        }

        (, previousInterestRateUpdate) = _erc721pool.interestRateInfo();

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

}
