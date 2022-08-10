// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 }        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC721Pool }            from "./interfaces/IERC721Pool.sol";
import { IERC721PositionManager } from "./interfaces/IERC721PositionManager.sol";

import { PositionManager } from "../base/PositionManager.sol";

import { Maths } from "../libraries/Maths.sol";

contract ERC721PositionManager is IERC721PositionManager, PositionManager {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for ERC20;

    /************************/
    /*** Lender Functions ***/
    /************************/

    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) nonReentrant {
        require(params_.lpTokens <= positions[params_.tokenId].lpTokens[params_.index], "PM:DL:INSUF_LP_BAL");

        IERC721Pool pool = IERC721Pool(params_.pool);

        // calculate equivalent underlying assets for given lpTokens
        (uint256 collateralToRemove, ) = pool.getLPTokenExchangeValue(params_.lpTokens, params_.index);

        uint256[] memory tokensToRemove;
        uint256 lpTokensClaimed;

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // slice incoming tokens to only use as many as are required
            uint256 indexToUse = Maths.wadToIntRoundingDown(collateralToRemove);
            tokensToRemove = new uint256[](indexToUse);
            tokensToRemove = params_.tokenIdsToRemove[:indexToUse];

            // claim any unencumbered collateral accrued to the price bucket
            lpTokensClaimed = pool.claimCollateral(tokensToRemove, params_.index);

            // transfer claimed collateral to recipient
            uint256 tokensToRemoveLength = tokensToRemove.length;
            for (uint256 i = 0; i < tokensToRemoveLength; ) {
                ERC721(pool.collateralTokenAddress()).safeTransferFrom(address(this), params_.recipient, tokensToRemove[i]);
                unchecked {
                    ++i;
                }
            }
        } else {
            tokensToRemove = new uint[](0);
        }

        // update position with newly removed lp tokens
        positions[params_.tokenId].lpTokens[params_.index] -= (params_.lpTokens + lpTokensClaimed);

        // update price set for liquidity removed
        if (positions[params_.tokenId].lpTokens[params_.index] == 0) {
            positionPrices[params_.tokenId].remove(params_.index);
        }

        // remove and transfer quote tokens to recipient
        uint256 quoteRemoved = pool.removeQuoteToken(params_.lpTokens, params_.index);
        ERC20(pool.quoteTokenAddress()).safeTransfer(params_.recipient, quoteRemoved);
        emit DecreaseLiquidity(params_.recipient, pool.indexToPrice(params_.index), tokensToRemove, quoteRemoved);
    }

}
