// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { console } from "@std/console.sol";

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IPool } from "../base/interfaces/IPool.sol";

import { InterestManager } from "./InterestManager.sol";
import { LenderManager }   from "./LenderManager.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

abstract contract Pool is IPool, InterestManager, Clone, LenderManager {

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
        uint256 amount_, uint256 price_
    ) external override returns (uint256 lpTokens_) {
        require(BucketMath.isValidPrice(price_), "P:AQT:INVALID_PRICE");
        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:AQT:AMT_LT_AVG_DEBT");
        // deposit quote token amount and get awarded LP tokens
        lpTokens_ = _addQuoteTokenToBucket(price_, amount_, curDebt, curInflator);

        // pool level accounting
        totalQuoteToken += amount_;

        // lender accounting
        lpBalance[msg.sender][price_] += lpTokens_;
        lpTimer[msg.sender][price_]   = block.timestamp;

        _updateInterestRate(curDebt);

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(msg.sender, price_, amount_, lup);
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

    // TODO: resolve issue with multiple PM positions in a given price bucket
    function removeQuoteToken(uint256 maxAmount_, uint256 price_) external override returns (uint256) {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // check if lpTokensToRemove was specified, otherwise use lender's entire balance
        // lpTokensToRemove = lpTokensToRemove == 0 ? lpBalance[msg.sender][price_] : lpTokensToRemove;
        uint256 lpTokensToRemove = lpBalance[msg.sender][price_];

        // remove quote token amount and get LP tokens burned
        (uint256 amount, uint256 lpTokens) = _removeQuoteTokenFromBucket(
            price_, maxAmount_, lpTokensToRemove, lpTimer[msg.sender][price_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:RQT:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount;

        // lender accounting
        lpBalance[msg.sender][price_] -= lpTokens;

        _updateInterestRate(curDebt);

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
        emit RemoveQuoteToken(msg.sender, price_, amount, lup);
        return amount / quoteTokenScale;
    }

    // TODO: move this to interface
    event TransferLPTokens(address owner_, address newOwner_, uint256 price_, uint256 tokensToTransfer);

    // TODO: convert this to take an array of args and modify once as opposed to rerunning sig check
    // TODO: since storage layout conflicts precluding use of delegatecall, use signature based access control
    function transferLPTokens(address owner_, address newOwner_, uint256 price_) external {
        // require(owner_ == msg.sender, "P:TLT:NOT_OWNER");
        require(BucketMath.isValidPrice(price_), "P:TLT:INVALID_PRICE");

        // calculate lp tokens to be moved in the given bucket
        uint256 tokensToTransfer = lpBalance[owner_][price_];

        // move lp tokens to the new owners address
        lpBalance[owner_][price_] = 0;
        lpBalance[newOwner_][price_] = tokensToTransfer;

        emit TransferLPTokens(owner_, newOwner_, price_, tokensToTransfer);
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

    function quoteTokenAddress() external view returns (address) {
        return _getArgAddress(0x14);
    }

}
