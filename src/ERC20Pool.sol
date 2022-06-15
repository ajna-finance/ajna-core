// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BorrowerManager } from "./base/BorrowerManager.sol";
import { LenderManager }   from "./base/LenderManager.sol";

import { IPool } from "./interfaces/IPool.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";

contract ERC20Pool is IPool, BorrowerManager, Clone, LenderManager {

    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Counter used by onlyOnce modifier
    uint256 private _poolInitializations = 0;

    /// @notice The precision of the collateral ERC-20 token based on decimals.
    /// @dev Only used by ERC20 type pools.
    uint256 public collateralScale;

    uint256 public override quoteTokenScale;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
     *  @notice Modifier to protect a clone's initialize method from repeated updates.
     */
    modifier onlyOnce() {
        require(_poolInitializations == 0, "P:INITIALIZED");
        _;
    }

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    function initialize() external override onlyOnce {
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = 0.05 * 10**18;
        previousRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 amount_) external override {
        // pool level accounting
        _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        totalCollateral += amount_;

        // borrower accounting
        borrowers[msg.sender].collateralDeposited += amount_;

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function borrow(uint256 amount_, uint256 limitPrice_) external override {
        require(amount_ <= totalQuoteToken, "P:B:INSUF_LIQ");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:B:AMT_LT_AVG_DEBT");

        BorrowerInfo memory borrower = borrowers[msg.sender];
        _accumulateBorrowerInterest(borrower, curInflator);

        // borrow amount from buckets with limit price and apply the origination fee
        uint256 fee = Maths.max(Maths.wdiv(previousRate, WAD_WEEKS_PER_YEAR), minFee);
        _borrowFromBucket(amount_, fee, limitPrice_, curInflator);
        require(borrower.collateralDeposited > Maths.rayToWad(_encumberedCollateral(borrower.debt + amount_ + fee)), "P:B:INSUF_COLLAT");
        curDebt += amount_ + fee;
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:B:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalDebt       = curDebt;

        // borrower accounting
        if (borrower.debt == 0) totalBorrowers += 1;
        borrower.debt         += amount_ + fee;
        borrowers[msg.sender] = borrower; // save borrower to storage

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function removeCollateral(uint256 amount_) external override {
        ( , uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        BorrowerInfo memory borrower = borrowers[msg.sender];
        _accumulateBorrowerInterest(borrower, curInflator);

        uint256 encumberedBorrowerCollateral = Maths.rayToWad(_encumberedCollateral(borrower.debt));
        require(borrower.collateralDeposited - encumberedBorrowerCollateral >= amount_, "P:RC:AMT_GT_AVAIL_COLLAT");

        // pool level accounting
        totalCollateral -= amount_;

        // borrower accounting
        borrower.collateralDeposited -= amount_;        
        borrowers[msg.sender]        = borrower; // save borrower to storage

        // move collateral from pool to sender
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    function repay(uint256 maxAmount_) external override {
        uint256 availableAmount = quoteToken().balanceOf(msg.sender) * quoteTokenScale;
        require(availableAmount >= maxAmount_, "P:R:INSUF_BAL");

        BorrowerInfo memory borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "P:R:NO_DEBT");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        _accumulateBorrowerInterest(borrower, curInflator);
        uint256 amount        = Maths.min(maxAmount_, borrower.debt);
        uint256 remainingDebt = borrower.debt - amount;
        require(remainingDebt == 0 || remainingDebt > _poolMinDebtAmount(curDebt, totalBorrowers),"P:R:AMT_LT_AVG_DEBT");

        // repay amount to buckets
        _repayBucket(amount, curInflator, amount >= curDebt);

        // pool level accounting
        totalQuoteToken += amount;
        totalDebt       = curDebt - Maths.min(curDebt, amount);

        // borrower accounting
        if (remainingDebt == 0) totalBorrowers -= 1;
        borrower.debt         -= amount;
        borrowers[msg.sender] = borrower; // save borrower to storage

        // move amount to repay from sender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, lup, amount);
    }

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

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(recipient_, price_, amount_, lup);
    }

    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        uint256 maxClaim = lpBalance[recipient_][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        uint256 claimedLpTokens = _claimCollateralFromBucket(price_, amount_, maxClaim);

        // lender accounting
        lpBalance[recipient_][price_] -= claimedLpTokens;

        // move claimed collateral from pool to claimer
        collateral().safeTransfer(recipient_, amount_ / collateralScale);
        emit ClaimCollateral(recipient_, price_, amount_, claimedLpTokens);
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

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    // TODO: replace local variables with references to borrower.<> (CHECK GAS SAVINGS)
    function liquidate(address borrower_) external override {
        BorrowerInfo memory borrower = borrowers[borrower_];
        require(borrower.debt != 0, "P:L:NO_DEBT");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        _accumulateBorrowerInterest(borrower, curInflator);
        uint256 debt = borrower.debt;
        require(
            getBorrowerCollateralization(borrower.collateralDeposited, debt) <= Maths.ONE_WAD,
            "P:L:BORROWER_OK"
        );

        // liquidate borrower and get collateral required to liquidate
        uint256 requiredCollateral = _liquidateAtBucket(debt, borrower.collateralDeposited, curInflator);

        // pool level accounting
        totalCollateral -= requiredCollateral;
        totalDebt       = curDebt - debt;

        // borrower accounting
        totalBorrowers               -= 1;
        borrower.debt                = 0;
        borrower.collateralDeposited -= requiredCollateral;
        borrowers[borrower_]         = borrower; // save borrower to storage

        emit Liquidate(borrower_, debt, requiredCollateral);
    }

    function purchaseBid(uint256 amount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:PB:INVALID_PRICE");

        uint256 collateralRequired = Maths.wdiv(amount_, price_);
        require(collateral().balanceOf(msg.sender) * collateralScale >= collateralRequired, "P:PB:INSUF_COLLAT");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // purchase bid from bucket
        _purchaseBidFromBucket(price_, amount_, collateralRequired, curInflator);
        require(_poolCollateralization(curDebt) >= Maths.ONE_WAD, "P:PB:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;

        // move required collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), collateralRequired / collateralScale);
        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Purchase(msg.sender, price_, amount_, collateralRequired);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function collateral() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0));
    }

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

}
