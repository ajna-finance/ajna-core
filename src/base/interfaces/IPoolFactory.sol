// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

/**
 *  @title Pool Factory Interface
 *  @dev   Used to deploy both funigible and non fungible pools.
 */
interface IPoolFactory {

    /**************/
    /*** Errors ***/
    /**************/

    /**
     *  @notice Can't deploy with one of the args pointing to the 0x0 address.
     */
    error DeployWithZeroAddress();

    /**
     *  @notice Pool with this combination of quote and collateral already exists.
     */
    error PoolAlreadyExists();

    /**
     *  @notice Pool starting interest rate is invalid.
     */
    error PoolInterestRateInvalid();

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when a new pool is created.
     *  @param  pool_ The address of the new pool.
     */
    event PoolCreated(address pool_);

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Deploys a cloned pool for the given collateral and quote token.
     *  @dev    Pool must not already exist, and must use WETH instead of ETH.
     *  @param  collateral   Address of ERC20 collateral token.
     *  @param  quote        Address of ERC20 quote token.
     *  @param  interestRate Initial interest rate of the pool.
     *  @return pool         Address of the newly created pool.
     */
    function deployPool(
        address collateral,
        address quote,
        uint256 interestRate
    ) external returns (address pool);
}
