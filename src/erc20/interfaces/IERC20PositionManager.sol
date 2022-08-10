// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IPositionManager } from "../../base/interfaces/IPositionManager.sol";

/**
 *  @title Ajna ERC20 Position Manager
 *  @dev   TODO
 */
interface IERC20PositionManager is IPositionManager {

    /**************/
    /*** Events ***/
    /**************/

    /**
     *  @notice Emitted when liquidity of the pool was increased.
     *  @param  lender_     Lender address.
     *  @param  price_      The price at quote tokens were added.
     *  @param  collateral_ The amount of collateral removed from the pool.
     *  @param  quote_      The amount of quote tokens removed from the pool.
     */
    event DecreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 collateral_, uint256 quote_);

    /***************/
    /*** Structs ***/
    /***************/

    /**
     *  @notice Struct holding parameters for decreasing liquidity.
     *  @param  tokenId   The tokenId of the NFT to burn.
     *  @param  recipient The NFT owner address.
     *  @param  pool      The pool address to remove quote tokens from.
     *  @param  index     The price bucket index from where liquidity should be removed.
     *  @param  lpTokens  The number of LP tokens to use.
     */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        address recipient;
        address pool;
        uint256 index;
        uint256 lpTokens;
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    /**
     *  @notice Called by lenders to remove liquidity from an existing position.
     *  @dev    Called to operate on an ERC20 type pool.
     *  @param  params_ Calldata struct supplying inputs required to update the underlying assets owed to an NFT.
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external payable;

}
