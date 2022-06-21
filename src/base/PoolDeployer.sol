// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

abstract contract PoolDeployer {

    uint256 public constant MIN_RATE = 0.01 * 10**18;
    uint256 public constant MAX_RATE = 0.1 * 10**18;

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

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_, uint256 interestRate_) {
        require(collateral_ != address(0) && quote_ != address(0),             "PF:DP:ZERO_ADDR");
        require(deployedPools[subsetHash_][collateral_][quote_] == address(0), "PF:DP:POOL_EXISTS");
        require(MIN_RATE <= interestRate_ && interestRate_ <= MAX_RATE,        "PF:DP:INVALID_RATE");
        _;
    }

    /*********************************/
    /*** Pool Creation Functions ***/
    /*********************************/

    function getNFTSubsetHash(uint256[] memory tokenIds_) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds_));
    }
}
