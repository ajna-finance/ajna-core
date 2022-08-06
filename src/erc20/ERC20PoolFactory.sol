// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IPoolFactory } from "../base/interfaces/IPoolFactory.sol";

import { ERC20Pool } from "./ERC20Pool.sol";

import { ClonesWithImmutableArgs } from "@clones/ClonesWithImmutableArgs.sol";

contract ERC20PoolFactory is IPoolFactory {

    using ClonesWithImmutableArgs for address;

    /// @dev Default bytes32 hash used by ERC20 Non-NFTSubset pool types
    bytes32 public constant ERC20_NON_SUBSET_HASH = keccak256("ERC20_NON_SUBSET_HASH");
    uint256 public constant MIN_RATE              = 0.01 * 10**18;
    uint256 public constant MAX_RATE              = 0.1 * 10**18;

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when a new pool is created.
     *  @param  pool_ The address of the new pool.
     */
    event PoolCreated(address pool_);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    ERC20Pool public implementation;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_, uint256 interestRate_) {
        require(collateral_ != address(0) && quote_ != address(0),             "PF:DP:ZERO_ADDR");
        require(deployedPools[subsetHash_][collateral_][quote_] == address(0), "PF:DP:POOL_EXISTS");
        require(MIN_RATE <= interestRate_ && interestRate_ <= MAX_RATE,        "PF:DP:INVALID_RATE");
        _;
    }

    constructor() {
        implementation = new ERC20Pool();
    }

    function deployPool(
        address collateral_, address quote_, uint256 interestRate_
    ) external canDeploy(ERC20_NON_SUBSET_HASH, collateral_, quote_, interestRate_) returns (address pool_) {
        bytes memory data = abi.encodePacked(collateral_, quote_);

        ERC20Pool pool = ERC20Pool(address(implementation).clone(data));
        pool.initialize(interestRate_);
        pool_ = address(pool);

        deployedPools[ERC20_NON_SUBSET_HASH][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);
    }
}
