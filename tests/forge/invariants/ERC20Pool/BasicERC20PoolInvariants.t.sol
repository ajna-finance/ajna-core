// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Pool }             from 'src/base/Pool.sol';
import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Maths }            from 'src/libraries/internal/Maths.sol';

import { TokenWithNDecimals } from '../../utils/Tokens.sol';

import { BasicERC20PoolHandler } from './handlers/BasicERC20PoolHandler.sol';
import { BasicInvariants }       from '../base/BasicInvariants.t.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';

// contains invariants for the test
contract BasicERC20PoolInvariants is BasicInvariants {

    TokenWithNDecimals    internal _collateral;
    ERC20Pool             internal _erc20pool;
    ERC20Pool             internal _impl;
    ERC20PoolFactory      internal _erc20poolFactory;
    BasicERC20PoolHandler internal _basicERC20PoolHandler;

    function setUp() public override virtual{

        super.setUp();

        _collateral       = new TokenWithNDecimals("Collateral", "C", uint8(vm.envOr("COLLATERAL_PRECISION", uint256(18))));
        _erc20poolFactory = new ERC20PoolFactory(address(_ajna));
        _impl             = _erc20poolFactory.implementation();
        _erc20pool        = ERC20Pool(_erc20poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _pool             = Pool(address(_erc20pool));

        _basicERC20PoolHandler = new BasicERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_poolInfo),
            _numOfActors,
            address(this)
        );

        _handler = address(_basicERC20PoolHandler);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc20pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_impl));

        LENDER_MIN_BUCKET_INDEX = IBaseHandler(_handler).LENDER_MIN_BUCKET_INDEX();
        LENDER_MAX_BUCKET_INDEX = IBaseHandler(_handler).LENDER_MAX_BUCKET_INDEX();

        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            ( , , , , ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_erc20pool), bucketIndex);
            previousBucketExchangeRate[bucketIndex] = exchangeRate;
        }

        (, previousInterestRateUpdate) = _erc20pool.interestRateInfo();

    }

    /***********************************/
    /*** ERC20 Collateral Invariants ***/
    /***********************************/

    /// @dev checks pools collateral Balance to be equal to collateral pledged
    function invariant_collateral_CT1_CT7() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        uint256 totalCollateralPledged;
        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);

            ( , uint256 borrowerCollateral, ) = _erc20pool.borrowerInfo(borrower);

            totalCollateralPledged += borrowerCollateral;
        }

        require(_erc20pool.pledgedCollateral() == totalCollateralPledged, "Collateral Invariant CT7");

        // convert pool collateral balance into WAD
        uint256 normalizedCollateralBalance = _collateral.balanceOf(address(_erc20pool)) * _erc20pool.collateralScale();
        uint256 bucketCollateral;

        uint256[] memory buckets = IBaseHandler(_handler).getBuckets();
        for (uint256 i = 0; i < buckets.length; i++) {
            uint256 bucketIndex = buckets[i];
            (, uint256 collateral, , , ) = _erc20pool.bucketInfo(bucketIndex);

            bucketCollateral += collateral;
        }

        require(normalizedCollateralBalance >= bucketCollateral + _erc20pool.pledgedCollateral(), "Collateral Invariant CT1");
    }

}
