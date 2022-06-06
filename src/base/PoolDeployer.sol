// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

abstract contract PoolDeployer {

    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    /// @dev Default bytes32 hash used by Non NFTSubset pool types
    bytes32 public constant NON_SUBSET_HASH = keccak256("NON_SUBSET_HASH");

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_) {
        require(collateral_ != address(0) && quote_ != address(0), "PF:DP:ZERO_ADDR");
        require(deployedPools[subsetHash_][collateral_][quote_] == address(0),  "PF:DP:POOL_EXISTS");
        _;
    }

    function getNFTSubsetHash(uint256[] memory tokenIds_) public returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds_));
    }
}
