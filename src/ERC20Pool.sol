// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { Clone } from "@clones/Clone.sol";

import { console } from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { Buckets }    from "./base/Buckets.sol";
import { Interest } from "./base/Interest.sol";

import { IPool } from "./interfaces/IPool.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";

contract ERC20Pool is IPool, Buckets, Clone, Interest {

    using SafeERC20 for ERC20;

    /// @dev Counter used by onlyOnce modifier
    uint8 private _poolInitializations = 0;

    uint256 public override collateralScale;
    uint256 public override quoteTokenScale;

    uint256 public override hpb; // [WAD]
    uint256 public override lup; // [WAD]

    uint256 public override previousRateUpdate;
    uint256 public override totalCollateral;    // [WAD]
    uint256 public override totalQuoteToken;    // [WAD]
    uint256 public override totalDebt;          // [WAD]

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public override borrowers;

    // lenders lp token balances: lender address -> price bucket [WAD] -> lender lp [RAY]
    mapping(address => mapping(uint256 => uint256)) public override lpBalance;

    /**
     *  @notice Modifier to protect a clone's initialize method from repeated updates.
     */
    modifier onlyOnce() {
        if (_poolInitializations != 0) {
            revert AlreadyInitialized();
        }
        _;
    }

    function initialize() external override onlyOnce {
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

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

    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external override returns (uint256) {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        accumulatePoolInterest();

        // deposit amount
        bool reallocate = (totalDebt != 0 && price_ > lup);
        (uint256 newHpb, uint256 newLup, uint256 lpTokens) = addQuoteTokenToBucket(price_, amount_, hpb, lup, inflatorSnapshot, reallocate);

        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        lpBalance[recipient_][price_] += lpTokens;  // update lender lp balance for current price bucket
        totalQuoteToken               += amount_;   // update quote token accumulator

        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);

        //  TODO: emit _amount / quoteTokenScale
        emit AddQuoteToken(recipient_, price_, amount_, lup);
        return lpTokens;
    }

    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external override {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        accumulatePoolInterest();

        // remove from bucket
        (uint256 amount, uint256 newLup, uint256 lpTokens, bool updateHpb, bool deactivate) = removeQuoteTokenFromBucket(
            price_, maxAmount_, lpBalance[recipient_][price_], hpb, inflatorSnapshot
        );

        // move lup down only if removal happened at or above lup and new lup different than current
        if (price_ >= lup && newLup < lup) lup = newLup;

        // update hpb if required
        if (updateHpb) hpb = getHpb();

        // deactivate bucket if required
        if (deactivate) deactivateBucket(price_);

        totalQuoteToken -= amount;
        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_WAD) {
            revert PoolUndercollateralized({collateralization_: col});
        }

        lpBalance[recipient_][price_] -= lpTokens;

        //  TODO: emit _amount / quoteTokenScale
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    function addCollateral(uint256 amount_) external override {
        accumulatePoolInterest();

        borrowers[msg.sender].collateralDeposited += amount_;
        totalCollateral                           += amount_;

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function removeCollateral(uint256 amount_) external override {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        uint256 encumberedBorrowerCollateral = Maths.rayToWad(getEncumberedCollateral(borrower.debt));

        if (borrower.collateralDeposited - encumberedBorrowerCollateral < amount_) {
            revert AmountExceedsAvailableCollateral({
                availableCollateral_: borrower.collateralDeposited - encumberedBorrowerCollateral
            });
        }

        borrower.collateralDeposited -= amount_;
        totalCollateral              -= amount_;

        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external override {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        uint256 maxClaim = lpBalance[recipient_][price_];
        if (maxClaim == 0) {
            revert NoClaimToBucket();
        }

        uint256 claimedLpTokens = claimCollateralFromBucket(price_, amount_, maxClaim);
        lpBalance[recipient_][price_] -= claimedLpTokens;

        collateral().safeTransfer(recipient_, amount_ / collateralScale);
        emit ClaimCollateral(recipient_, price_, amount_, claimedLpTokens);
    }

    function borrow(uint256 amount_, uint256 limitPrice_) external override {
        if (amount_ > totalQuoteToken) {
            revert InsufficientLiquidity({amountAvailable_: totalQuoteToken});
        }

        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        // if first loan then borrow at HPB
        lup = borrowFromBucket(amount_, limitPrice_, lup == 0 ? hpb : lup, inflatorSnapshot);

        if (
            borrower.collateralDeposited <=
            Maths.rayToWad(getEncumberedCollateral(borrower.debt + amount_))
        ) {
            revert InsufficientCollateralForBorrow();
        }

        borrower.debt   += amount_;
        totalQuoteToken -= amount_;
        totalDebt       += amount_;

        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_WAD) {
            revert PoolUndercollateralized({collateralization_: col});
        }

        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function repay(uint256 maxAmount_) external override {
        uint256 availableAmount = quoteToken().balanceOf(msg.sender) * quoteTokenScale;

        if (availableAmount < maxAmount_) {
            revert InsufficientBalanceForRepay();
        }

        BorrowerInfo storage borrower = borrowers[msg.sender];
        if (borrower.debt == 0) {
            revert NoDebtToRepay();
        }
        accumulatePoolInterest();
        accumulateBorrowerInterest(borrower);

        uint256 amount = Maths.min(maxAmount_, borrower.debt);
        lup = repayBucket(amount, lup, inflatorSnapshot);

        borrower.debt   -= amount;
        totalQuoteToken += amount;
        totalDebt       -= Maths.min(totalDebt, amount);

        // reset LUP if no debt in pool
        if (totalDebt == 0) lup = 0;

        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, lup, amount);
    }

    function purchaseBid(uint256 amount_, uint256 price_) external override {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        // convert amount from WAD to pool precision - RAD
        uint256 collateralRequired = Maths.wdiv(amount_, price_);
        if (collateral().balanceOf(msg.sender) * collateralScale < collateralRequired) {
            revert InsufficientCollateralBalance();
        }

        accumulatePoolInterest();

        (uint256 newLup, bool isEmpty) = purchaseBidFromBucket(price_, amount_, collateralRequired, inflatorSnapshot);

        // move lup down only if removal happened at lup or higher and new lup different than current
        if (price_ >= lup && newLup < lup) lup = newLup;

        // update HPB if removed from current, if no deposit nor debt in current HPB and if LUP not 0
        if (price_ == hpb && isEmpty && lup != 0) hpb = getHpb();

        totalQuoteToken -= amount_;

        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_WAD) {
            revert PoolUndercollateralized({collateralization_: col});
        }

        // move required collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), collateralRequired / collateralScale);

        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Purchase(msg.sender, price_, amount_, collateralRequired);
    }

    // TODO: replace local variables with references to borrower.<> (CHECK GAS SAVINGS)
    function liquidate(address borrower_) external override {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[borrower_];
        accumulateBorrowerInterest(borrower);

        uint256 debt                = borrower.debt;
        uint256 collateralDeposited = borrower.collateralDeposited;

        if (debt == 0) {
            revert NoDebtToLiquidate();
        }

        uint256 collateralization = getBorrowerCollateralization(borrower.collateralDeposited, debt);

        if (collateralization > Maths.ONE_WAD) {
            revert BorrowerIsCollateralized({collateralization_: collateralization});
        }

        uint256 requiredCollateral = liquidateAtBucket(debt, collateralDeposited, hpb, inflatorSnapshot);

        // pool level accounting
        totalDebt       -= borrower.debt;
        totalCollateral -= requiredCollateral;

        // borrower accounting
        borrower.debt                = 0;
        borrower.collateralDeposited -= requiredCollateral;

        // update HPB
        uint256 curHpb = getHpb();
        if (hpb != curHpb) hpb = curHpb;

        emit Liquidate(borrower_, debt, requiredCollateral);
    }

    /*************************/
    /*** Bucket Management ***/
    /*************************/

    function getPendingBucketInterest(uint256 price_) external view override returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        interest_ = debt != 0 ? getPendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

    /*****************************/
    /*** Pool State Management ***/
    /*****************************/

    /**
     *  @notice Update the global borrower inflator
     *  @dev    Requires time to have passed between update calls
     */
    function accumulatePoolInterest() private {
        if (block.timestamp - lastInflatorSnapshotUpdate != 0) {
            uint256 pendingInflator    = getPendingInflator();                                              // RAY
            totalDebt                  += getPendingInterest(totalDebt, pendingInflator, inflatorSnapshot); // WAD
            inflatorSnapshot           = pendingInflator;                                                   // RAY
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    function getHup() public view override returns (uint256 hup_) {
        hup_ = lup;
        while (true) {
            (uint256 price, , uint256 down, uint256 onDeposit, , , , ) = bucketAt(hup_);

            if (price == down || onDeposit != 0) break;

            // check that there are available quote tokens on deposit in down bucket
            (, , , uint256 downAmount, , , , ) = bucketAt(down);

            if (downAmount == 0) break;

            hup_ = down;
        }
    }

    function getHpb() public view override returns (uint256 hpb_) {
        hpb_ = hpb;
        while (true) {
            (, , uint256 down, uint256 onDeposit, uint256 debt, , , ) = bucketAt(hpb_);
            if (onDeposit != 0 || debt != 0) {
                break;
            } else if (down == 0) {
                hpb_ = 0;
                break;
            }
            hpb_ = down;
        }
    }

    // TODO: Add a test for this
    function getMinimumPoolPrice() public view override returns (uint256 minPrice_) {
        minPrice_ = totalDebt != 0 ? Maths.wdiv(totalDebt, totalCollateral) : 0;
    }

    function getEncumberedCollateral(uint256 debt_) public view override returns (uint256 encumbrance_) {
        // Calculate encumbrance as RAY to maintain precision
        encumbrance_ = debt_ != 0 ? Maths.wdiv(debt_, lup) : 0;
    }

    function getPendingPoolInterest() external view override returns (uint256 interest_) {
        interest_ = totalDebt != 0 ? getPendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

    function getPoolCollateralization() public view override returns (uint256 poolCollateralization_) {
        if (lup != 0 && totalDebt != 0) {
            return Maths.wdiv(totalCollateral, getEncumberedCollateral(totalDebt));
        }
        return Maths.ONE_WAD;
    }

    function getPoolActualUtilization() public view override returns (uint256 poolActualUtilization_) {
        if (totalDebt == 0) {
            return 0;
        }
        return Maths.wdiv(totalDebt, totalQuoteToken + totalDebt);
    }

    function getPoolTargetUtilization() public view override returns (uint256 poolTargetUtilization_) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
    }

    function updateInterestRate() external override {
        // RAY
        uint256 actualUtilization = getPoolActualUtilization();
        if (
            actualUtilization != 0 &&
            previousRateUpdate < block.timestamp &&
            getPoolCollateralization() > Maths.ONE_WAD
        ) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(
                previousRate,
                (
                    Maths.rayToWad(actualUtilization) + Maths.ONE_WAD
                        - Maths.rayToWad(getPoolTargetUtilization())
                )
            );
            previousRateUpdate = block.timestamp;
            emit UpdateInterestRate(oldRate, previousRate);
        }
    }

    /*****************************/
    /*** Borrower Management ***/
    /*****************************/

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
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization = Maths.ONE_WAD;

        if (borrower.debt > 0 && borrower.inflatorSnapshot != 0) {
            borrowerPendingDebt  += getPendingInterest(borrower.debt, getPendingInflator(), borrower.inflatorSnapshot);
            collateralEncumbered  = getEncumberedCollateral(borrowerPendingDebt);
            collateralization     = Maths.wdiv(borrower.collateralDeposited, collateralEncumbered);
        }

        return (
            borrower.debt,
            borrowerPendingDebt,
            borrower.collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
    }

    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_) public view override returns (uint256 borrowerCollateralization_) {
        if (lup != 0 && debt_ != 0) {
            return Maths.wdiv(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.ONE_WAD;
    }

    function estimatePriceForLoan(uint256 amount_) public view override returns (uint256 price_) {
        // convert amount from WAD to collateral pool precision - RAD
        return estimatePrice(amount_, lup == 0 ? hpb : lup);
    }

    /*****************************/
    /*** Lender Management ***/
    /*****************************/

    function getLPTokenBalance(address owner_, uint256 price_) external view override returns (uint256 lpBalance_) {
        return lpBalance[owner_][price_];
    }

    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view override returns (uint256 collateralTokens_, uint256 quoteTokens_) {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

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
