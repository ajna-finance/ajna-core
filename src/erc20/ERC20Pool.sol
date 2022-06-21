// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC20BorrowerManager } from "./ERC20BorrowerManager.sol";
import { ERC20BucketsManager }  from "./ERC20BucketsManager.sol";
import { IERC20Pool }           from "./interfaces/IERC20Pool.sol";

import { Pool } from "../base/Pool.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

contract ERC20Pool is IERC20Pool, ERC20BorrowerManager, ERC20BucketsManager, Pool {

    using SafeERC20 for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override collateralScale;


    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    function initialize(uint256 rate_) external override {
        require(_poolInitializations == 0, "P:INITIALIZED");
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**27;
        lastInflatorSnapshotUpdate = block.timestamp;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 amount_) external override {
        // pool level accounting
        (uint256 curDebt, ) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        totalCollateral += amount_;

        // borrower accounting
        borrowers[msg.sender].collateralDeposited += amount_;

        _updateInterestRate(curDebt);

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
        uint256 fee = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
        _borrowFromBucket(amount_, fee, limitPrice_, curInflator);
        require(borrower.collateralDeposited > Maths.rayToWad(_encumberedCollateral(borrower.debt + amount_ + fee)), "P:B:INSUF_COLLAT");
        curDebt += amount_ + fee;
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:B:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;
        totalDebt       = curDebt;

        // borrower accounting
        if (borrower.debt == 0) totalBorrowers += 1;
        borrower.debt         += amount_ + fee;
        borrowers[msg.sender] = borrower; // save borrower to storage

        _updateInterestRate(curDebt);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function removeCollateral(uint256 amount_) external override {
        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        BorrowerInfo memory borrower = borrowers[msg.sender];
        _accumulateBorrowerInterest(borrower, curInflator);

        uint256 encumberedBorrowerCollateral = Maths.rayToWad(_encumberedCollateral(borrower.debt));
        require(borrower.collateralDeposited - encumberedBorrowerCollateral >= amount_, "P:RC:AMT_GT_AVAIL_COLLAT");

        // pool level accounting
        totalCollateral -= amount_;

        // borrower accounting
        borrower.collateralDeposited -= amount_;        
        borrowers[msg.sender]        = borrower; // save borrower to storage

        _updateInterestRate(curDebt);

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
        curDebt -= Maths.min(curDebt, amount);

        // pool level accounting
        totalQuoteToken += amount;
        totalDebt       = curDebt;

        // borrower accounting
        if (remainingDebt == 0) totalBorrowers -= 1;
        borrower.debt         = remainingDebt;
        borrowers[msg.sender] = borrower; // save borrower to storage

        _updateInterestRate(curDebt);

        // move amount to repay from sender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, lup, amount);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        uint256 maxClaim = lpBalance[recipient_][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        uint256 claimedLpTokens = _claimCollateralFromBucket(price_, amount_, maxClaim);

        // lender accounting
        lpBalance[recipient_][price_] -= claimedLpTokens;

        _updateInterestRate(totalDebt);

        // move claimed collateral from pool to claimer
        collateral().safeTransfer(recipient_, amount_ / collateralScale);
        emit ClaimCollateral(recipient_, price_, amount_, claimedLpTokens);
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
            getBorrowerCollateralization(borrower.collateralDeposited, debt) <= Maths.WAD,
            "P:L:BORROWER_OK"
        );

        // liquidate borrower and get collateral required to liquidate
        uint256 requiredCollateral = _liquidateAtBucket(debt, borrower.collateralDeposited, curInflator);
        curDebt -= debt;

        // pool level accounting
        totalCollateral -= requiredCollateral;
        totalDebt       = curDebt;

        // borrower accounting
        totalBorrowers               -= 1;
        borrower.debt                = 0;
        borrower.collateralDeposited -= requiredCollateral;
        borrowers[borrower_]         = borrower; // save borrower to storage

        _updateInterestRate(curDebt);

        emit Liquidate(borrower_, debt, requiredCollateral);
    }

    function purchaseBid(uint256 amount_, uint256 price_) external override {
        require(BucketMath.isValidPrice(price_), "P:PB:INVALID_PRICE");

        uint256 collateralRequired = Maths.wdiv(amount_, price_);
        require(collateral().balanceOf(msg.sender) * collateralScale >= collateralRequired, "P:PB:INSUF_COLLAT");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        // purchase bid from bucket
        _purchaseBidFromBucket(price_, amount_, collateralRequired, curInflator);
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:PB:POOL_UNDER_COLLAT");

        // pool level accounting
        totalQuoteToken -= amount_;

        _updateInterestRate(curDebt);

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

}
