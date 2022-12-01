// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';

import '../base/interfaces/IPoolFactory.sol';
import '../base/PoolDeployer.sol';

import './interfaces/IERC721PoolFactory.sol';
import './ERC721Pool.sol';
import '../base/FlashloanablePool.sol';

contract ERC721PoolFactory is IERC721PoolFactory, PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;
    FlashloanablePool public poolImplementation;

    /// @dev Default bytes32 hash used by ERC721 Non-NFTSubset pool types
    bytes32 public constant ERC721_NON_SUBSET_HASH = keccak256("ERC721_NON_SUBSET_HASH");

    constructor() {
        poolImplementation = new FlashloanablePool();
        implementation = new ERC721Pool(address(poolImplementation));
    }

    function deployPool(
        address collateral_, address quote_, uint256[] memory tokenIds_, uint256 interestRate_
    ) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_, interestRate_) returns (address pool_) {
        uint256 quoteTokenScale = 10**(18 - IERC20Token(quote_).decimals());

        bytes memory data = abi.encodePacked(
            collateral_,
            quote_,
            quoteTokenScale
        );

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool_ = address(pool);
        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);

        pool.initialize(tokenIds_, interestRate_);
    }

    /*********************************/
    /*** Pool Creation Functions ***/
    /*********************************/

    function getNFTSubsetHash(uint256[] memory tokenIds_) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds_));
    }
}
