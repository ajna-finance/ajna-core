// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import './interfaces/IPoolFactory.sol';

abstract contract PoolDeployer {

    uint256 public constant MIN_RATE = 0.01 * 10**18;
    uint256 public constant MAX_RATE = 0.1 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    /**
     *  @notice Address of the Ajna token, needed for Claimable Reserve Auctions.
     */
    address immutable ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_, uint256 interestRate_) {
        if (collateral_ == address(0) || quote_ == address(0))             revert IPoolFactory.DeployWithZeroAddress();
        if (deployedPools[subsetHash_][collateral_][quote_] != address(0)) revert IPoolFactory.PoolAlreadyExists();
        if (MIN_RATE >= interestRate_ || interestRate_ >= MAX_RATE)        revert IPoolFactory.PoolInterestRateInvalid();
        _;
    }
}
