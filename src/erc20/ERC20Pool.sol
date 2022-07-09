// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IERC20Pool }           from "./interfaces/IERC20Pool.sol";

import { Pool } from "../base/Pool.sol";

import { BucketMath } from "../libraries/BucketMath.sol";
import { Maths }      from "../libraries/Maths.sol";

// Added
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ERC20Pool is IERC20Pool, Pool {

    using SafeERC20     for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    event log_named_uint(string key, uint256 val);

    struct LiquidationInfo {
        uint128 kickTime;
        uint128 referencePrice;
        uint256 remainingCollateral;
    }

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override collateralScale;

    // borrowers book: borrower address -> BorrowerInfo
    mapping (address => BorrowerInfo) public override borrowers;

    mapping (address => LiquidationInfo) public liquidations;

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

        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function borrow(uint256 amount_, uint256 limitPrice_) external override {
        require(amount_ <= totalQuoteToken, "P:B:INSUF_LIQ");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);
        require(amount_ > _poolMinDebtAmount(curDebt, totalBorrowers), "P:B:AMT_LT_MIN_DEBT");

        BorrowerInfo memory borrower = borrowers[msg.sender];

        _accumulateBorrowerInterest(msg.sender, curInflator);

        // Borrow amount from buckets with limit price and apply the origination fee
        uint256 fee = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
        _borrowFromBucket(amount_, fee, limitPrice_, curInflator);

        // Update total debt and interest rate
        curDebt += amount_ + fee;
        _updateInterestRate(curDebt);

        // Check resulting collateralization
        require(
            borrower.collateralDeposited > Maths.rayToWad(_encumberedCollateral(borrower.debt + amount_ + fee)),
            "P:B:INSUF_COLLAT"
        );
        require(_poolCollateralization(curDebt) >= Maths.WAD, "P:B:POOL_UNDER_COLLAT");

        // Pool level accounting
        totalQuoteToken -= amount_;
        totalDebt        = curDebt;

        // Borrower accounting
        if (borrower.debt == 0) totalBorrowers += 1;
        borrowers[msg.sender].debt += amount_ + fee;

        // Move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function removeCollateral(uint256 amount_) external override {
        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        BorrowerInfo memory borrower = borrowers[msg.sender];
        _accumulateBorrowerInterest(msg.sender, curInflator);

        uint256 encumberedBorrowerCollateral = Maths.rayToWad(_encumberedCollateral(borrower.debt));
        require(borrower.collateralDeposited - encumberedBorrowerCollateral >= amount_, "P:RC:AMT_GT_AVAIL_COLLAT");

        // Pool level accounting
        totalCollateral -= amount_;

        // Borrower accounting
        borrowers[msg.sender].collateralDeposited -= amount_;

        _updateInterestRate(curDebt);

        // move collateral from pool to sender
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    function repay(uint256 maxAmount_) external override {
        _repayDebt(msg.sender, maxAmount_);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function claimCollateral(uint256 amount_, uint256 price_) external override returns (uint256 claimedLpTokens) {
        require(BucketMath.isValidPrice(price_), "P:CC:INVALID_PRICE");

        uint256 maxClaim = lpBalance[msg.sender][price_];
        require(maxClaim != 0, "P:CC:NO_CLAIM_TO_BUCKET");

        // claim collateral and get amount of LP tokens burned for claim
        claimedLpTokens = _claimCollateralFromBucket(price_, amount_, maxClaim);

        // lender accounting
        lpBalance[msg.sender][price_] -= claimedLpTokens;

        _updateInterestRate(totalDebt);

        // move claimed collateral from pool to claimer
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit ClaimCollateral(msg.sender, price_, amount_, claimedLpTokens);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function kick(address borrower_) external {
        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        _accumulateBorrowerInterest(borrower_, curInflator);

        BorrowerInfo memory borrower = borrowers[borrower_];

        require(borrower.debt != 0, "P:L:NO_DEBT");

        emit log_named_uint("bleh", 1);
        emit log_named_uint("borrower.collateralDeposited", borrower.collateralDeposited);
        emit log_named_uint("borrower.debt               ",  borrower.debt);
        emit log_named_uint("collateralization           ", getBorrowerCollateralization(borrower.collateralDeposited, borrower.debt));

        require(
            getBorrowerCollateralization(borrower.collateralDeposited, borrower.debt) <= Maths.WAD,
            "P:L:BORROWER_OK"
        );

        liquidations[borrower_] = LiquidationInfo({
            kickTime:            uint128(block.timestamp),
            referencePrice:      uint128(hpb),
            remainingCollateral: _repossessCollateral(borrower.debt, borrower.collateralDeposited, borrower.inflatorSnapshot)
        });

        // TODO: Post liquidation bond
        // TODO: Account for repossessed collateral

        // Post the liquidation bond
        // Repossess the borrowers collateral, initialize the auction cooldown timer
    }

    // TODO: Remove
    function liquidate(address borrower_) external override {}

    // Need a condition in the take funciton for the cooldown period
    // If the loan is under collateralized for a certain amount of time, then we're allowd to start the auction
    // Refer to docs
    // "Cooldown" function before liquidations can actually occur
    // Time between kick and take
    // Leave debt on the books
    // Lender needs to be "locked" - cannot move/remove quote token
    // Total debt must accounted for until it is covered by the collateral liquidation
    // Specify an amount to liquidate
    // When the collateral gets liquidated for quote token, remove the corresponding debt from (which bucket)
    // Reduce total debt by same amount
    // Set aside quote token for the kicker
    // How to reward/penalize kicker (depends on NP)?
    // Quote token that is recovered from each take should be deposited into the LUP bucket
    // Max time for auction (review doc)
    // With bad debt remaining in the book after an auction, it is wiped from the top of the book, incurring a loss for the LPs

    // TODO: Add reentrancy guard
    function take(address borrower_, uint256 collateralToLiquidate_, bytes memory swapCalldata_) external {
        BorrowerInfo    memory borrower    = borrowers[borrower_];
        LiquidationInfo memory liquidation = liquidations[borrower_];

        require(
            liquidation.kickTime != 0 &&
            block.timestamp - uint256(liquidation.kickTime) > 1 hours,
            "P:T:NOT_PAST_COOLDOWN"
        );

        require(
            getBorrowerCollateralization(borrower.collateralDeposited, borrower.debt) <= Maths.WAD,
            "P:L:BORROWER_OK"
        );

        uint256 collateralForLiquidation = Maths.min(collateralToLiquidate_, liquidation.remainingCollateral);

        // Reduce liquidation's remaining collateral
        liquidations[borrower_].remainingCollateral -= collateralForLiquidation;

        // Flash loan full amount to liquidate to borrower
        collateral().safeTransfer(msg.sender, collateralForLiquidation);

        // Execute arbitrary code at msg.sender address, allowing atomic conversion of asset
        msg.sender.call(swapCalldata_);

        // Get current swap price
        uint256 quoteTokenReturnAmount = _getQuoteTokenReturnAmount(uint256(liquidation.kickTime), uint256(liquidation.referencePrice), collateralForLiquidation);

        // Pull funds from msg.sender
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenReturnAmount);

        _repayDebt(borrower_, quoteTokenReturnAmount);
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

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
     *  @dev    Only adds debt if a borrower has already initiated a debt position
     *  @dev    Only used by Borrowers using fungible tokens as collateral
     *  @param  borrowerAddress_ Address of the borrower.
     *  @param  inflator_        Pool inflator.
     *  @return borrowerDebt_    Updated borrower debt.
     */
    function _accumulateBorrowerInterest(address borrowerAddress_, uint256 inflator_) internal returns (uint256 borrowerDebt_) {
        BorrowerInfo memory borrower = borrowers[borrowerAddress_];

        uint256 accruedInterest =
            borrower.debt != 0 && borrower.inflatorSnapshot != 0
             ? _pendingInterest(borrower.debt, inflator_, borrower.inflatorSnapshot)
             : 0;

        borrowers[borrowerAddress_].inflatorSnapshot = inflator_;

        // Add accrued interest to borrower's debt and return updated value
        borrowerDebt_ = borrowers[borrowerAddress_].debt += accruedInterest;
    }

    /**
     *  @notice Called by a lender to claim accumulated collateral
     *  @param  price_        The price bucket from which collateral should be claimed
     *  @param  amount_       The amount of collateral tokens to be claimed, WAD
     *  @param  lpBalance_    The claimers current LP balance, RAY
     *  @return lpRedemption_ The amount of LP tokens that will be redeemed
     */
    function _claimCollateralFromBucket(
        uint256 price_, uint256 amount_, uint256 lpBalance_
    ) internal returns (uint256 lpRedemption_) {
        Bucket memory bucket = _buckets[price_];

        require(amount_ <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        lpRedemption_ = Maths.wrdivr(Maths.wmul(amount_, bucket.price), _exchangeRate(bucket));

        require(lpRedemption_ <= lpBalance_, "B:CC:INSUF_LP_BAL");

        // bucket accounting
        bucket.collateral    -= amount_;
        bucket.lpOutstanding -= lpRedemption_;

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) {
            _deactivateBucket(bucket); // cleanup if bucket no longer used
        } else {
            _buckets[price_] = bucket; // save bucket to storage
        }
    }

    /**
     *  @notice Liquidate a given position's collateral
     *  @param  debt_               The amount of debt to cover, WAD
     *  @param  collateral_         The amount of collateral deposited, WAD
     *  @param  inflator_           The current pool inflator rate, RAY
     *  @return requiredCollateral_ The amount of collateral to be liquidated
     */
    function _liquidateAtBucket(
        uint256 debt_, uint256 collateral_, uint256 inflator_
    ) internal returns (uint256 requiredCollateral_) {
        uint256 curPrice = hpb;

        while (true) {
            Bucket storage bucket   = _buckets[curPrice];
            uint256 curDebt         = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
            bucket.inflatorSnapshot = inflator_;

            uint256 bucketDebtToPurchase     = Maths.min(debt_, curDebt);
            uint256 bucketRequiredCollateral = Maths.min(Maths.wdiv(debt_, bucket.price), collateral_);

            debt_               -= bucketDebtToPurchase;
            collateral_         -= bucketRequiredCollateral;
            requiredCollateral_ += bucketRequiredCollateral;

            // bucket accounting
            curDebt           -= bucketDebtToPurchase;
            bucket.collateral += bucketRequiredCollateral;

            // forgive the debt when borrower has no remaining collateral but still has debt
            if (debt_ != 0 && collateral_ == 0) {
                bucket.debt = 0;
                break;
            }

            bucket.debt = curDebt;

            if (debt_ == 0) break; // stop if all debt reconciliated

            curPrice = bucket.down;
        }

        // HPB and LUP management
        uint256 newHpb = getHpb();
        if (hpb != newHpb) hpb = newHpb;
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given collateral tokens
     *  @param  price_      The price bucket at which the exchange will occur, WAD
     *  @param  amount_     The amount of quote tokens to receive, WAD
     *  @param  collateral_ The amount of collateral to exchange, WAD
     *  @param  inflator_   The current pool inflator rate, RAY
     */
    function _purchaseBidFromBucket(
        uint256 price_, uint256 amount_, uint256 collateral_, uint256 inflator_
    ) internal {
        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 available = bucket.onDeposit + bucket.debt;

        require(amount_ <= available, "B:PB:INSUF_BUCKET_LIQ");

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket.onDeposit);

        amount_          -= purchaseFromDeposit;
        // bucket accounting
        bucket.onDeposit -= purchaseFromDeposit;
        bucket.collateral += collateral_;

        // debt reallocation
        uint256 newLup = _reallocateDown(bucket, amount_, inflator_);

        _buckets[price_] = bucket;

        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, bucket.price);
    }

    function _repayDebt(address borrowerAddress_, uint256 maxAmount_) internal {
        uint256 availableAmount = quoteToken().balanceOf(borrowerAddress_) * quoteTokenScale;
        require(availableAmount >= maxAmount_,         "P:R:INSUF_BAL");
        require(borrowers[borrowerAddress_].debt != 0, "P:R:NO_DEBT");

        (uint256 curDebt, uint256 curInflator) = _accumulatePoolInterest(totalDebt, inflatorSnapshot);

        uint256 borrowerDebt = _accumulateBorrowerInterest(borrowerAddress_, curInflator);

        uint256 amount        = Maths.min(maxAmount_, borrowerDebt);
        uint256 remainingDebt = borrowerDebt - amount;
        require(remainingDebt == 0 || remainingDebt > _poolMinDebtAmount(curDebt, totalBorrowers), "P:R:AMT_LT_MIN_DEBT");

        // Repay amount to buckets and update interest rate
        _repayBucket(amount, curInflator, amount >= curDebt);
        curDebt -= Maths.min(curDebt, amount);
        _updateInterestRate(curDebt);

        // Pool level accounting
        totalQuoteToken += amount;
        totalDebt        = curDebt;

        // Borrower accounting
        if (remainingDebt == 0) totalBorrowers -= 1;
        borrowers[borrowerAddress_].debt = remainingDebt;

        // Move amount to repay from sender to pool
        quoteToken().safeTransferFrom(borrowerAddress_, address(this), amount / quoteTokenScale);
        emit Repay(borrowerAddress_, lup, amount);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getBorrowerInfo(address borrower_)
        public view override returns (
            uint256 debt_,
            uint256 pendingDebt_,
            uint256 collateralDeposited_,
            uint256 collateralEncumbered_,
            uint256 collateralization_,
            uint256 borrowerInflatorSnapshot_,
            uint256 inflatorSnapshot_
        )
    {
        BorrowerInfo memory borrower = borrowers[borrower_];

        debt_                     = borrower.debt;
        pendingDebt_              = borrower.debt;
        collateralDeposited_      = borrower.collateralDeposited;
        collateralization_        = Maths.WAD;
        borrowerInflatorSnapshot_ = borrower.inflatorSnapshot;
        inflatorSnapshot_         = inflatorSnapshot;

        if (debt_ != 0 && borrowerInflatorSnapshot_ != 0) {
            pendingDebt_          += _pendingInterest(debt_, getPendingInflator(), borrowerInflatorSnapshot_);
            collateralEncumbered_ = getEncumberedCollateral(pendingDebt_);
            collateralization_    = Maths.wrdivw(collateralDeposited_, collateralEncumbered_);
        }

    }

    function _getQuoteTokenReturnAmount(uint256 kickTime_, uint256 referencePrice_, uint256 collateralForLiquidation_) internal view returns (uint256 price_) {
        uint256 hoursSinceKick = (block.timestamp - kickTime_) / 1 hours;
        uint256 currentPrice   = 10 * referencePrice_ * 2 ** (hoursSinceKick - 1 hours);

        price_ = collateralForLiquidation_ * currentPrice * quoteTokenScale / collateralScale;
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

    function collateralTokenAddress() external pure returns (address) {
        return _getArgAddress(0);
    }

}
