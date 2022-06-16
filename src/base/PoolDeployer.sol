// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

abstract contract PoolDeployer {

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

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_) {
        require(collateral_ != address(0) && quote_ != address(0), "PF:DP:ZERO_ADDR");
        require(deployedPools[subsetHash_][collateral_][quote_] == address(0),  "PF:DP:POOL_EXISTS");
        _;
    }

    /*********************************/
    /*** Pool Creation Functions ***/
    /*********************************/

    function getNFTSubsetHash(uint256[] memory tokenIds_) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds_));
    }
}
