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

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev SubsetHash => CollateralAddress => QuoteAddress => Pool Address
    mapping(bytes32 => mapping(address => mapping(address => address))) public deployedPools;

    /**
     *  @notice Address of the Ajna token, needed for Claimable Reserve Auctions.
     */
    address internal ajnaTokenAddress = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier canDeploy(bytes32 subsetHash_, address collateral_, address quote_, uint256 interestRate_) {
        if (collateral_ == address(0) || quote_ == address(0))              revert DeployWithZeroAddress();
        if (deployedPools[subsetHash_][collateral_][quote_] != address(0)) revert PoolAlreadyExists();
        if (MIN_RATE >= interestRate_ || interestRate_ >= MAX_RATE)         revert PoolInterestRateInvalid();
        _;
    }
}
