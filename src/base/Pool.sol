// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

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

    /** @dev Used for tracking LP token ownership structs for transferLPTokens access control */
    mapping(address => LpTokenOwnership) public lpTokenOwnership;

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
        uint256 maxAmount_, uint256 fromPrice_, uint256 toPrice_
    ) external override {
        require(BucketMath.isValidPrice(toPrice_), "P:MQT:INVALID_TO_PRICE");
        require(fromPrice_ != toPrice_, "P:MQT:SAME_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // move quote tokens between buckets and get LP tokens
        (uint256 fromLpTokens, uint256 toLpTokens, uint256 movedAmount) = _moveQuoteTokenFromBucket(
            fromPrice_, toPrice_, maxAmount_, lpBalance[msg.sender][fromPrice_], lpTimer[msg.sender][fromPrice_], curInflator
        );
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:MQT:POOL_UNDER_COLLAT");

        // lender accounting
        lpBalance[msg.sender][fromPrice_] -= fromLpTokens;
        lpBalance[msg.sender][toPrice_]   += toLpTokens;

        _updateInterestRate(curDebt);

        emit MoveQuoteToken(msg.sender, fromPrice_, toPrice_, movedAmount, lup);
    }

    function removeQuoteToken(uint256 maxAmount_, uint256 price_, uint256 lpTokensToRemove) external override returns (uint256, uint256) {
        require(BucketMath.isValidPrice(price_), "P:RQT:INVALID_PRICE");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

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
        uint256 scaledAmount = amount / quoteTokenScale;
        quoteToken().safeTransfer(msg.sender, scaledAmount);
        emit RemoveQuoteToken(msg.sender, price_, amount, lup);
        return (scaledAmount, lpTokens);
    }

    function approveNewPositionOwner(address owner_, address allowedNewOwner_) external {
        require(msg.sender == owner_, "P:ANPO:NOT_OWNER");

        LpTokenOwnership storage tokenOwnership = lpTokenOwnership[owner_];

        tokenOwnership.owner = owner_;
        tokenOwnership.allowedNewOwner = allowedNewOwner_;

        lpTokenOwnership[owner_] = tokenOwnership;
    }

    function transferLPTokens(address owner_, address newOwner_, uint256[] calldata prices_) external {
        require(lpTokenOwnership[owner_].owner == owner_ && lpTokenOwnership[owner_].allowedNewOwner == newOwner_, "P:TLT:NOT_OWNER");

        uint256 tokensTransferred;

        uint256 pricesLength = prices_.length;
        for (uint256 i = 0; i < pricesLength; ) {
            require(BucketMath.isValidPrice(prices_[i]), "P:TLT:INVALID_PRICE");

            // calculate lp tokens to be moved in the given bucket
            uint256 tokensToTransfer = lpBalance[owner_][prices_[i]];

            // move lp tokens to the new owners address
            delete lpBalance[owner_][prices_[i]];
            lpBalance[newOwner_][prices_[i]] += tokensToTransfer;

            tokensTransferred += tokensToTransfer;

            unchecked {
                ++i;
            }
        }

        emit TransferLPTokens(owner_, newOwner_, prices_, tokensTransferred);
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

    function quoteTokenAddress() external pure returns (address) {
        return _getArgAddress(0x14);
    }

}
