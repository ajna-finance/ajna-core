// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IPool } from "../../base/interfaces/IPool.sol";

/**
 * @title Ajna ERC20 Pool
 */
interface IERC20Pool is IPool {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral locked in the pool.
     */
    event AddCollateral(address indexed borrower_, uint256 amount_);

    /**
     *  @notice Emitted when lender claims unencumbered collateral.
     *  @param  claimer_ Recipient that claimed collateral.
     *  @param  price_   Price at which unencumbered collateral was claimed.
     *  @param  amount_  The amount of Quote tokens transferred to the claimer.
     *  @param  lps_     The amount of LP tokens burned in the claim.
     */
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);

    /**
     *  @notice Emitted when collateral is exchanged for quote tokens.
     *  @param  bidder_     `msg.sender`.
     *  @param  price_      Price at which collateral was exchanged for quote tokens.
     *  @param  amount_     Amount of quote tokens purchased.
     *  @param  collateral_ Amount of collateral exchanged for quote tokens.
     */
    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);

    /**
     *  @notice Emitted when borrower removes collateral from the pool.
     *  @param  borrower_ `msg.sender`.
     *  @param  amount_   Amount of collateral removed from the pool.
     */
    event RemoveCollateral(address indexed borrower_, uint256 amount_);

    /***********************/
    /*** State Variables ***/
    /***********************/

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return collateralScale_ The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256 collateralScale_);

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @notice Called by borrowers to add collateral to the pool.
     *  @param  amount_ The amount of collateral in deposit tokens to be added to the pool.
     */
    function addCollateral(uint256 amount_) external;

    /**
     *  @notice Called by borrowers to remove an amount of collateral.
     *  @param  amount_ The amount of collateral in deposit tokens to be removed from a position.
     */
    function removeCollateral(uint256 amount_) external;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Called by lenders to claim unencumbered collateral from a price bucket.
     *  @param  recipient_ The recipient claiming collateral.
     *  @param  amount_    The amount of unencumbered collateral to claim.
     *  @param  price_     The bucket from which unencumbered collateral will be claimed.
     */
    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external;

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    /**
     *  @notice Exchanges collateral for quote token.
     *  @param  amount_ WAD The amount of quote token to purchase.
     *  @param  price_  The purchasing price of quote token.
     */
    function purchaseBid(uint256 amount_, uint256 price_) external;

}
