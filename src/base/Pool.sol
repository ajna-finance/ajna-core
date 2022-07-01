// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPool } from "../base/interfaces/IPool.sol";

import { InterestManager } from "./InterestManager.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

// Added

abstract contract Pool is IPool, InterestManager, Clone {

    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Counter used by onlyOnce modifier
    uint256 internal _poolInitializations = 0;

    uint256 public override quoteTokenScale;

    /********************************/
    /*** LenderManager State Vars ***/
    /********************************/

    /**
     *  @dev lender address -> price bucket [WAD] -> lender lp [RAY]
     */
    mapping(address => mapping(uint256 => uint256)) public override lpBalance;
    /**
     *  @dev lender address -> price bucket [WAD] -> timer
     */
    mapping(address => mapping(uint256 => uint256)) public lpTimer;  // TODO: override


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
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:MQT:POOL_UNDER_COLLAT");

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
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:RQT:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount;

        // lender accounting
        lpBalance[recipient_][price_] -= lpTokens;

        _updateInterestRate(curDebt);

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view override returns (uint256 collateralTokens_, uint256 quoteTokens_) {
        require(BucketMath.isValidPrice(price_), "P:GLPTEV:INVALID_PRICE");

        ( , , , uint256 onDeposit, uint256 debt, , uint256 lpOutstanding, uint256 bucketCollateral) = bucketAt(price_);

        // calculate lpTokens share of all outstanding lpTokens for the bucket
        uint256 lenderShare = Maths.rdiv(lpTokens_, lpOutstanding);

        // calculate the amount of collateral and quote tokens equivalent to the lenderShare
        collateralTokens_ = Maths.radToWad(bucketCollateral * lenderShare);
        quoteTokens_      = Maths.radToWad((onDeposit + debt) * lenderShare);
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
