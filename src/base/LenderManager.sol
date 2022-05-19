// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import { Buckets } from "./Buckets.sol";

import { ILenderManager } from "../interfaces/ILenderManager.sol";
import { IPool }          from "../interfaces/IPool.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

/**
 * @notice Lender Management related functionality
*/
abstract contract LenderManager is ILenderManager, Buckets {

    /**
     *  @dev    lender address -> price bucket [WAD] -> lender lp [RAY]
     */
    mapping(address => mapping(uint256 => uint256)) public lpBalance;

    function getLPTokenBalance(address owner_, uint256 price_) external view override returns (uint256 lpBalance_) {
        return lpBalance[owner_][price_];
    }

    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view override returns (uint256 collateralTokens_, uint256 quoteTokens_) {
        require(BucketMath.isValidPrice(price_), "P:GLPTEV:INVALID_PRICE");

        (
            ,
            ,
            ,
            uint256 onDeposit,
            uint256 debt,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = bucketAt(price_);

        // calculate lpTokens share of all outstanding lpTokens for the bucket
        uint256 lenderShare = Maths.rdiv(lpTokens_, lpOutstanding);

        // calculate the amount of collateral and quote tokens equivalent to the lenderShare
        collateralTokens_ = Maths.radToWad(bucketCollateral * lenderShare);
        quoteTokens_      = Maths.radToWad((onDeposit + debt) * lenderShare);
    }

}
