// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';

import './interfaces/IERC20PoolFactory.sol';
import '../base/PoolDeployer.sol';

import './ERC20Pool.sol';

contract ERC20PoolFactory is IERC20PoolFactory, PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC20Pool public implementation;

    /// @dev Default bytes32 hash used by ERC20 Non-NFTSubset pool types
    bytes32 public constant ERC20_NON_SUBSET_HASH = keccak256("ERC20_NON_SUBSET_HASH");

    constructor(address ajna_) {
        ajna           = ajna_;
        implementation = new ERC20Pool();
    }

    function deployPool(
        address collateral_, address quote_, uint256 interestRate_
    ) external canDeploy(ERC20_NON_SUBSET_HASH, collateral_, quote_, interestRate_) returns (address pool_) {
        uint256 quoteTokenScale = 10**(18 - IERC20Token(quote_).decimals());
        uint256 collateralScale = 10**(18 - IERC20Token(collateral_).decimals());

        bytes memory data = abi.encodePacked(
            collateral_,
            quote_,
            quoteTokenScale,
            ajna
        );

        ERC20Pool pool = ERC20Pool(address(implementation).clone(data));
        pool_ = address(pool);
        deployedPools[ERC20_NON_SUBSET_HASH][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);

        pool.initialize(collateralScale, interestRate_);
    }
}
