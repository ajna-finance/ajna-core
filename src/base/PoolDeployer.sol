// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IPoolFactory } from '../interfaces/pool/IPoolFactory.sol';

/**
 *  @title  Pool Deployer base contract
 *  @notice Base contract for Pool Deployer, contains logic used by both ERC20 and ERC721 Pool Factories.
 */
abstract contract PoolDeployer {

    uint256 public constant MIN_RATE = 0.01 * 1e18;
    uint256 public constant MAX_RATE = 0.1  * 1e18;

    address public ajna; // Ajna token contract address on a network.

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    // slither-disable-next-line uninitialized-state
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    /// @notice List of all deployed pools. Separate list is maintained for each factory.
    // slither-disable-next-line uninitialized-state
    address[] public deployedPoolsList;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
     * @notice Ensures that pools are deployed according to specifications.
     * @dev    Used by both ERC20, and ERC721 pool factory types.
     */
    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_, uint256 interestRate_) {
        if (collateral_ == address(0) || quote_ == address(0))              revert IPoolFactory.DeployWithZeroAddress();
        if (deployedPools[subsetHash_][collateral_][quote_] != address(0)) revert IPoolFactory.PoolAlreadyExists();
        if (MIN_RATE >= interestRate_ || interestRate_ >= MAX_RATE)         revert IPoolFactory.PoolInterestRateInvalid();
        _;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     * @notice Returns the list of all deployed pools.
     * @dev    This function is used by integrations to access deployed pools.
     * @dev    Each factory implementation maintains its own list of deployed pools.
     * @return address[] memory List of all deployed pools.
     */
    function getDeployedPoolsList() external view returns (address[] memory) {
        return deployedPoolsList;
    }

    /**
     * @notice Returns the number of deployed pools that have been deployed by a factory.
     * @return uint256 length of deployedPoolsList array.
     */
    function getNumberOfDeployedPools() external view returns (uint256) {
        return deployedPoolsList.length;
    }

}
