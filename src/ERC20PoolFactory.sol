// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';

import { IERC20PoolFactory } from './interfaces/pool/erc20/IERC20PoolFactory.sol';

import { IERC20Token, PoolType } from './interfaces/pool/IPool.sol';

import { ERC20Pool }    from './ERC20Pool.sol';
import { PoolDeployer } from './base/PoolDeployer.sol';

/**
 *  @title  ERC20 Pool Factory
 *  @notice Pool factory contract for creating ERC20 pools. Actors actions:
 *          - Pool creators: create pool by providing a fungible token for quote and collateral and an interest rate between 1-10%
 *  @dev    Reverts if pool is already created or if params to deploy new pool are invalid.
 */
contract ERC20PoolFactory is PoolDeployer, IERC20PoolFactory {

    using ClonesWithImmutableArgs for address;

    ERC20Pool public implementation;

    /// @dev Default bytes32 hash used by ERC20 Non-NFTSubset pool types
    bytes32 public constant ERC20_NON_SUBSET_HASH = keccak256("ERC20_NON_SUBSET_HASH");

    constructor(address ajna_) {
        if (ajna_ == address(0)) revert DeployWithZeroAddress();

        ajna = ajna_;

        implementation = new ERC20Pool();
    }

    /**
     *  @inheritdoc IERC20PoolFactory
     *  @dev  immutable args: pool type; ajna, collateral and quote address; quote and collateral scale
     *  @dev  write state:
     *          - deployedPools mapping
     *          - deployedPoolsList array
     *  @dev reverts on:
     *          - 0x address provided as quote or collateral DeployWithZeroAddress()
     *          - pool with provided quote / collateral pair already exists PoolAlreadyExists()
     *          - invalid interest rate provided PoolInterestRateInvalid()
     *  @dev emit events:
     *          - PoolCreated
     */
    function deployPool(
        address collateral_, address quote_, uint256 interestRate_
    ) external canDeploy(ERC20_NON_SUBSET_HASH, collateral_, quote_, interestRate_) returns (address pool_) {
        uint256 quoteTokenScale = 10 ** (18 - IERC20Token(quote_).decimals());
        uint256 collateralScale = 10 ** (18 - IERC20Token(collateral_).decimals());

        bytes memory data = abi.encodePacked(
            PoolType.ERC20,
            ajna,
            collateral_,
            quote_,
            quoteTokenScale,
            collateralScale
        );

        ERC20Pool pool = ERC20Pool(address(implementation).clone(data));

        pool_ = address(pool);

        // Track the newly deployed pool
        deployedPools[ERC20_NON_SUBSET_HASH][collateral_][quote_] = pool_;
        deployedPoolsList.push(pool_);

        emit PoolCreated(pool_);

        pool.initialize(interestRate_);
    }
}
