// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BorrowerManager } from "./BorrowerManager.sol";
import { LenderManager }   from "./LenderManager.sol";

import { IPool } from "../interfaces/IPool.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

abstract contract BasePool is IPool, BorrowerManager, Clone, LenderManager {

    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Counter used by onlyOnce modifier
    uint256 internal _poolInitializations = 0;

    uint256 public override quoteTokenScale;


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        address recipient_, uint256 amount_, uint256 price_
    ) external override returns (uint256 lpTokens_) {
        require(BucketMath.isValidPrice(price_), "P:AQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:AQT:AMT_LT_AVG_DEBT");

        // deposit quote token amount and get awarded LP tokens
        lpTokens_ = _addQuoteTokenToBucket(price_, amount_, curDebt, curInflator);

        // pool level accounting
        totalQuoteToken += amount_;

        // lender accounting
        lpBalance[recipient_][price_] += lpTokens_;
        lpTimer[recipient_][price_]   = block.timestamp;

        _updateInterestRate(curDebt);

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(recipient_, price_, amount_, lup);
    }

    function moveQuoteToken(
        address recipient_, uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_
    ) external override {
        require(BucketMath.isValidPrice(toPrice_), "P:MQT:INVALID_TO_PRICE");
        require(fromPrice_ != toPrice_, "P:MQT:SAME_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // move quote tokens between buckets and get LP tokens
        (uint256 fromLpTokens, uint256 toLpTokens, uint256 movedAmount) = _moveQuoteTokenFromBucket(
            fromPrice_, toPrice_, maxAmount_, lpBalance[recipient_][fromPrice_], lpTimer[recipient_][fromPrice_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:MQT:POOL_UNDER_COLLAT");

        // lender accounting
        lpBalance[recipient_][fromPrice_] -= fromLpTokens;
        lpBalance[recipient_][toPrice_]   += toLpTokens;

        _updateInterestRate(curDebt);

        emit MoveQuoteToken(recipient_, fromPrice_, toPrice_, movedAmount, lup);
    }

    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // remove quote token amount and get LP tokens burned
        (uint256 amount, uint256 lpTokens) = _removeQuoteTokenFromBucket(
            price_, maxAmount_, lpBalance[recipient_][price_], lpTimer[recipient_][price_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:RQT:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount;

        // lender accounting
        lpBalance[recipient_][price_] -= lpTokens;

        _updateInterestRate(curDebt);

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

}
