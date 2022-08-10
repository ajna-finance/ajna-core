// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool }            from "./interfaces/IERC20Pool.sol";
import { IERC20PositionManager } from "./interfaces/IERC20PositionManager.sol";

import { PositionManager } from "../base/PositionManager.sol";

contract ERC20PositionManager is IERC20PositionManager, PositionManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for ERC20;

    /************************/
    /*** Lender Functions ***/
    /************************/

    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) nonReentrant {
        require(params_.lpTokens <= positions[params_.tokenId].lpTokens[params_.index], "PM:DL:INSUF_LP_BAL");

        IERC20Pool pool = IERC20Pool(params_.pool);

        // calculate equivalent underlying assets for given lpTokens
        (uint256 collateralToRemove, ) = pool.getLPTokenExchangeValue(params_.lpTokens, params_.index);

        uint256 lpTokensRemoved;

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // claim any unencumbered collateral accrued to the price bucket
            uint256 lpTokensClaimed = pool.claimCollateral(collateralToRemove, params_.index);

            lpTokensRemoved += lpTokensClaimed;

            // transfer claimed collateral to recipient
            ERC20(pool.collateralTokenAddress()).safeTransfer(params_.recipient, collateralToRemove);
        }

        // update position with lp tokens removed
        lpTokensRemoved += params_.lpTokens;
        positions[params_.tokenId].lpTokens[params_.index] -= lpTokensRemoved;

        // update price set for liquidity removed
        if (positions[params_.tokenId].lpTokens[params_.index] == 0) {
            positionPrices[params_.tokenId].remove(params_.index);
        }

        // remove and transfer quote tokens to recipient
        uint256 quoteRemoved = pool.removeQuoteToken(params_.lpTokens, params_.index);
        ERC20(pool.quoteTokenAddress()).safeTransfer(params_.recipient, quoteRemoved);
        emit DecreaseLiquidity(params_.recipient, pool.indexToPrice(params_.index), collateralToRemove, quoteRemoved);
    }

}
