// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { BoundedLenderHandler } from './handlers/Lenders.sol';
import { InvariantTest } from './InvariantTest.sol';

contract TestBase is InvariantTest, Test {

    // Mainnet ajna address
    address              internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    Token                internal _quote;
    Token                internal _collateral;

    ERC20Pool            internal _pool;
    ERC20Pool            internal _impl;
    PoolInfoUtils        internal _poolInfo;
    ERC20PoolFactory     internal _poolFactory;

    BoundedLenderHandler internal _lenderHandler;

    function setUp() public virtual {
        _collateral     = new Token("Collateral", "C");
        _quote          = new Token("Quote", "Q");
        _poolFactory    = new ERC20PoolFactory(_ajna);
        _impl           = _poolFactory.implementation();
        _pool           = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolInfo       = new PoolInfoUtils();
        _lenderHandler  = new BoundedLenderHandler(address(_pool), address(_quote), address(_collateral), address(_poolInfo), 20);
    }

    // // checks pool lps are equal to sum of all lender lps in a bucket 
    // function invariant_Lps() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     for(uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
    //         uint256 totalLps;
    //         for(uint256 i = 0; i < actorCount; i++) {
    //             address lender = _invariantActorManager._actors(i);
    //             (uint256 lps, ) = _pool.lenderInfo(bucketIndex, lender);
    //             totalLps += lps;
    //         }
    //         (uint256 poolLps, , , , ) = _pool.bucketInfo(bucketIndex);
    //         require(poolLps == totalLps, "Incorrect Lps");
    //     }
    // }

    // // checks pool quote token balance is greater than equals total deposits in pool
    // function invariant_quoteTokenBalance() public {
    //     uint256 poolBalance = _quote.balanceOf(address(_pool));
    //     (uint256 pooldebt, , ) = _pool.debtInfo();
    //     // poolBalance == poolDeposit will fail due to rounding issue while converting LPs to Quote
    //     require(poolBalance >= _pool.depositSize() - pooldebt, "Incorrect pool Balance");
    // }

    // // checks pools collateral Balance to be equal to collateral pledged
    // function invariant_collateralBalance() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     uint256 totalCollateralPledged;
    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address borrower = _invariantActorManager._actors(i);
    //         ( , uint256 borrowerCollateral, ) = _pool.borrowerInfo(borrower);
    //         totalCollateralPledged += borrowerCollateral;
    //     }

    //     require(_pool.pledgedCollateral() == totalCollateralPledged, "Incorrect Collateral Pledged");
    // }

    // // checks pool debt is equal to sum of all borrowers debt
    // function invariant_pooldebt() public {
    //     uint256 actorCount = _invariantActorManager.getActorsCount();
    //     uint256 totalDebt;
    //     for(uint256 i = 0; i < actorCount; i++) {
    //         address borrower = _invariantActorManager._actors(i);
    //         (uint256 debt, , ) = _pool.borrowerInfo(borrower);
    //         totalDebt += debt;
    //     }

    //     uint256 poolDebt = _pool.totalDebt();

    //     require(poolDebt == totalDebt, "Incorrect pool debt");
    // }
}