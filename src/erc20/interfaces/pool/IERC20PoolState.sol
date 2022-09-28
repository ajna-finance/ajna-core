// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC20 Pool State
 */
interface IERC20PoolState {

    /**
     *  @notice Returns the `collateralScale` state variable.
     *  @return The precision of the collateral ERC-20 token based on decimals.
     */
    function collateralScale() external view returns (uint256);

    /**
     *  @notice Mapping of borrower under liquidation to {LiquidationInfo} structs.
     *  @param  borrower            Address of the borrower.
     *  @return kickTime            Time the liquidation was initiated.
     *  @return referencePrice      Highest Price Bucket at time of liquidation.
     *  @return remainingCollateral Amount of collateral which has not yet been taken.
     *  @return remainingDebt       Amount of debt which has not been covered by the liquidation.
     */
    // TODO: Instead of just returning the struct, should also calculate and include auction price.
    // TODO: Need to implement this for NFT pool.
    function liquidations(address borrower) external view returns (
        uint128 kickTime,
        uint128 referencePrice,
        uint256 remainingCollateral,
        uint256 remainingDebt
    );

}