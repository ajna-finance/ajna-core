// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { Clone } from "@clones/Clone.sol";

import { console } from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { BitMaps }   from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import { Interest } from "./base/Interest.sol";

import { IPool } from "./interfaces/IPool.sol";

import { Buckets }    from "./libraries/Buckets.sol";
import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";

contract ERC20Pool is IPool, Clone, Interest {

    using SafeERC20 for ERC20;

    using Buckets for mapping(uint256 => Buckets.Bucket);

    /// @dev Counter used by onlyOnce modifier
    uint8 private _poolInitializations = 0;

    // price (WAD) -> bucket
    mapping(uint256 => Buckets.Bucket) private _buckets;

    BitMaps.BitMap private _bitmap;

    uint256 public collateralScale;
    uint256 public quoteTokenScale;

    uint256 public hpb; // WAD
    uint256 public lup; // WAD

    uint256 public previousRateUpdate;
    uint256 public totalCollateral;    // RAY
    uint256 public totalQuoteToken;    // RAY
    uint256 public totalDebt;          // RAY

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    // lenders lp token balances: lender address -> price bucket (WAD) -> lender lp (RAY)
    mapping(address => mapping(uint256 => uint256)) public lpBalance;

    /// @notice Modifier to protect a clone's initialize method from repeated updates
    modifier onlyOnce() {
        if (_poolInitializations != 0) {
            revert AlreadyInitialized();
        }
        _;
    }

    function initialize() external onlyOnce {
        collateralScale = 10**(27 - collateral().decimals());
        quoteTokenScale = 10**(27 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /// @dev Pure function used to facilitate accessing token via clone state
    function collateral() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0));
    }

    /// @dev Pure function used to facilitate accessing token via clone state
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    /// @notice Called by lenders to add an amount of credit at a specified price bucket
    /// @param recipient_ The recipient adding quote tokens
    /// @param amount_ The amount of quote token to be added by a lender
    /// @param price_ The bucket to which the quote tokens will be added
    /// @return The amount of LP Tokens received for the added quote tokens
    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external returns (uint256) {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        accumulatePoolInterest();

        // create bucket if doesn't exist
        if (!BitMaps.get(_bitmap, price_)) {
            hpb = _buckets.initializeBucket(hpb, price_);
            BitMaps.setTo(_bitmap, price_, true);
        }

        // deposit amount with RAY precision
        amount_ = Maths.wadToRay(amount_);
        bool reallocate = (totalDebt != 0 && price_ > lup);
        (uint256 newLup, uint256 lpTokens) = _buckets.addQuoteToken(price_, amount_, lup, inflatorSnapshot, reallocate);

        if (reallocate) {
            lup = newLup;
        }

        lpBalance[recipient_][price_] += lpTokens;  // update lender lp balance for current price bucket
        totalQuoteToken               += amount_;   // update quote token accumulator

        quoteToken().safeTransferFrom(recipient_, address(this), amount_ / quoteTokenScale);

        //  TODO: emit _amount / quoteTokenScale
        emit AddQuoteToken(recipient_, price_, amount_, lup);
        return lpTokens;
    }

    /// @notice Called by lenders to remove an amount of credit at a specified price bucket
    /// @param recipient_ The recipient removing quote tokens
    /// @param maxAmount_ The maximum amount of quote token to be removed by a lender
    /// @param price_ The bucket from which quote tokens will be removed
    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        accumulatePoolInterest();

        // remove from bucket with RAD precision
        maxAmount_ = Maths.wadToRay(maxAmount_);
        Buckets.Bucket storage bucket = _buckets[price_];
        (uint256 amount, uint256 newLup, uint256 lpTokens) = _buckets.removeQuoteToken(
            bucket,
            maxAmount_,
            lpBalance[recipient_][price_],
            inflatorSnapshot
        );

        // move lup down only if removal happened at or above lup and new lup different than current
        if (price_ >= lup && newLup < lup) {
            lup = newLup;
        }

        // update HPB if removed from current, if no deposit nor debt in current HPB
        if (price_ == hpb && bucket.onDeposit == 0 && bucket.debt == 0) {
            hpb = getHpb();
        }

        totalQuoteToken -= amount;
        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_RAY) {
            revert PoolUndercollateralized({collateralization: col});
        }

        lpBalance[recipient_][price_] -= lpTokens;

        //  TODO: emit _amount / quoteTokenScale
        quoteToken().safeTransfer(recipient_, amount / quoteTokenScale);
        emit RemoveQuoteToken(recipient_, price_, amount, lup);
    }

    /// @notice Called by borrowers to add collateral to the pool
    /// @param amount_ The amount of collateral in deposit tokens to be added to the pool
    function addCollateral(uint256 amount_) external {
        accumulatePoolInterest();
        // convert amount from WAD to collateral pool precision - RAY
        amount_ = Maths.wadToRay(amount_);

        borrowers[msg.sender].collateralDeposited += amount_;
        totalCollateral                           += amount_;

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    /// @notice Called by borrowers to remove an amount of collateral
    /// @param amount_ The amount of collateral in deposit tokens to be removed from a position
    function removeCollateral(uint256 amount_) external {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        uint256 encumberedBorrowerCollateral = getEncumberedCollateral(borrower.debt);

        // convert amount from WAD to collateral pool precision - RAY
        amount_ = Maths.wadToRay(amount_);

        if (borrower.collateralDeposited - encumberedBorrowerCollateral < amount_) {
            revert AmountExceedsAvailableCollateral({
                availableCollateral: borrower.collateralDeposited - encumberedBorrowerCollateral
            });
        }

        borrower.collateralDeposited -= amount_;
        totalCollateral              -= amount_;

        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    /// @notice Called by lenders to claim unencumbered collateral from a price bucket
    /// @param recipient_ The recipient claiming collateral
    /// @param amount_ The amount of unencumbered collateral to claim
    /// @param price_ The bucket from which unencumbered collateral will be claimed
    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        uint256 maxClaim = lpBalance[recipient_][price_];
        if (maxClaim == 0) {
            revert NoClaimToBucket();
        }

        // convert amount from WAD to collateral pool precision - RAY
        amount_ = Maths.wadToRay(amount_);
        uint256 claimedLpTokens = _buckets.claimCollateral(price_, amount_, maxClaim);

        lpBalance[recipient_][price_] -= claimedLpTokens;

        collateral().safeTransfer(recipient_, amount_ / collateralScale);
        emit ClaimCollateral(recipient_, price_, amount_, claimedLpTokens);
    }

    /// @notice Called by a borrower to open or expand a position
    /// @dev Can only be called if quote tokens have already been added to the pool
    /// @param amount_ The amount of quote token to borrow
    /// @param limitPrice_ Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position
    function borrow(uint256 amount_, uint256 limitPrice_) external {
        // convert amount from WAD to pool precision - RAD
        amount_ = Maths.wadToRay(amount_);

        if (amount_ > totalQuoteToken) {
            revert InsufficientLiquidity({amountAvailable: totalQuoteToken});
        }

        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        // if first loan then borrow at HPB
        lup = _buckets.borrow(amount_, limitPrice_, lup == 0 ? hpb : lup, inflatorSnapshot);

        if (
            borrower.collateralDeposited <=
            getEncumberedCollateral(Maths.add(borrower.debt, amount_))
        ) {
            revert InsufficientCollateralForBorrow();
        }

        borrower.debt   += amount_;
        totalQuoteToken -= amount_;
        totalDebt       += amount_;

        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_RAY) {
            revert PoolUndercollateralized({collateralization: col});
        }

        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    /// @notice Called by a borrower to repay some amount of their borrowed quote tokens
    /// @param maxAmount_ WAD The maximum amount of quote token to repay
    function repay(uint256 maxAmount_) external {
        uint256 availableAmount = quoteToken().balanceOf(msg.sender) * quoteTokenScale;

        // convert amount from WAD to pool precision - RAD
        maxAmount_ = Maths.wadToRay(maxAmount_);
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
        lup = _buckets.repay(amount, lup, inflatorSnapshot);

        borrower.debt   -= amount;
        totalQuoteToken += amount;
        totalDebt       -= Maths.min(totalDebt, amount);

        // reset LUP if no debt in pool
        if (totalDebt == 0) {
            lup = 0;
        }

        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, lup, amount);
    }

    /// @notice Exchanges collateral for quote token
    /// @param amount_ WAD The amount of quote token to purchase
    /// @param price_ The purchasing price of quote token
    function purchaseBid(uint256 amount_, uint256 price_) external {
        if (!BucketMath.isValidPrice(price_)) {
            revert InvalidPrice();
        }

        // convert amount from WAD to pool precision - RAD
        amount_ = Maths.wadToRay(amount_);
        uint256 collateralRequired = Maths.rdiv(Maths.radToRay(amount_), Maths.wadToRay(price_));
        if (collateral().balanceOf(msg.sender) * collateralScale < collateralRequired) {
            revert InsufficientCollateralBalance();
        }

        accumulatePoolInterest();

        Buckets.Bucket storage bucket = _buckets[price_];
        uint256 newLup = _buckets.purchaseBid(bucket, amount_, collateralRequired, inflatorSnapshot);

        // move lup down only if removal happened at lup or higher and new lup different than current
        if (price_ >= lup && newLup < lup) {
            lup = newLup;
        }

        // update HPB if removed from current, if no deposit nor debt in current HPB and if LUP not 0
        if (price_ == hpb && bucket.onDeposit == 0 && bucket.debt == 0 && lup != 0) {
            hpb = getHpb();
        }

        totalQuoteToken -= amount_;

        uint256 col = getPoolCollateralization();
        if (col < Maths.ONE_RAY) {
            revert PoolUndercollateralized({collateralization: col});
        }

        // move required collateral from sender to pool
        collateral().safeTransferFrom(
            msg.sender,
            address(this),
            collateralRequired / collateralScale
        );

        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Purchase(msg.sender, price_, amount_, collateralRequired);
    }

    // TODO: replace local variables with references to borrower.<> (CHECK GAS SAVINGS)
    /// @notice Liquidates a given borrower's position
    /// @param borrower_ The address of the borrower being liquidated
    function liquidate(address borrower_) external {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[borrower_];
        accumulateBorrowerInterest(borrower);

        uint256 debt                = borrower.debt;
        uint256 collateralDeposited = borrower.collateralDeposited;

        if (debt == 0) {
            revert NoDebtToLiquidate();
        }

        uint256 collateralization = getBorrowerCollateralization(
            borrower.collateralDeposited,
            debt
        );

        if (collateralization > Maths.ONE_RAY) {
            revert BorrowerIsCollateralized({collateralization: collateralization});
        }

        uint256 requiredCollateral = _buckets.liquidate(debt, collateralDeposited, hpb, inflatorSnapshot);

        // pool level accounting
        totalDebt       -= borrower.debt;
        totalCollateral -= requiredCollateral;

        // borrower accounting
        borrower.debt                = 0;
        borrower.collateralDeposited -= requiredCollateral;

        emit Liquidate(borrower_, debt, requiredCollateral);
    }

    /*************************/
    /*** Bucket Management ***/
    /*************************/

    // TODO: rename bucketAtPrice & add bucketAtIndex
    // TODO: add return type
    /// @notice Get a bucket struct for a given price
    /// @param price_ The price of the bucket to retrieve
    function bucketAt(uint256 price_)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 onDeposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        )
    {
        return _buckets.bucketAt(price_);
    }

    function isBucketInitialized(uint256 price_) public view returns (bool) {
        return BitMaps.get(_bitmap, price_);
    }

    /// @notice Calculate unaccrued interest for a particular bucket, which may be added to
    /// @notice bucket debt to discover pending bucket debt
    /// @param price_ The price bucket for which interest should be calculated, WAD
    /// @return interest_ - Unaccumulated bucket interest, RAY
    function getPendingBucketInterest(uint256 price_) external view returns (uint256 interest_) {
        (, , , , uint256 debt, uint256 bucketInflator, , ) = bucketAt(price_);
        interest_ = debt != 0 ? getPendingInterest(debt, getPendingInflator(), bucketInflator) : 0;
    }

                /*****************************/
                /*** Pool State Management ***/
                /*****************************/

    /// @notice Update the global borrower inflator
    /// @dev Requires time to have passed between update calls
    function accumulatePoolInterest() private {
        if (block.timestamp - lastInflatorSnapshotUpdate != 0) {
            // RAY
            uint256 pendingInflator = getPendingInflator();
            // RAD
            totalDebt                  += getPendingInterest(totalDebt, pendingInflator, inflatorSnapshot);
            inflatorSnapshot           = pendingInflator;
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    /// @notice Returns the current Hight Utilizable Price (HUP) bucket
    /// @dev Starting at the LUP, iterate through down pointers until no quote tokens are available
    /// @dev LUP should always be >= HUP
    /// @return The current HUP
    function getHup() public view returns (uint256) {
        uint256 curPrice = lup;
        while (true) {
            (uint256 price, , uint256 down, uint256 onDeposit, , , , ) = _buckets.bucketAt(
                curPrice
            );
            if (price == down || onDeposit != 0) {
                break;
            }

            // check that there are available quote tokens on deposit in down bucket
            (, , , uint256 downAmount, , , , ) = _buckets.bucketAt(down);
            if (downAmount == 0) {
                break;
            }
            curPrice = down;
        }
        return curPrice;
    }

    /// @notice Returns the next Highest Deposited Bucket (HPB)
    /// @dev Starting at the current HPB, iterate through down pointers until a new HPB found
    /// @dev HPB should have at on deposit or debt different than 0
    /// @return The next HPB
    function getHpb() public view returns (uint256) {
        uint256 curHpb = hpb;
        while (true) {
            (, , uint256 down, uint256 onDeposit, uint256 debt, , , ) = _buckets.bucketAt(curHpb);
            if (onDeposit != 0 || debt != 0) {
                break;
            } else if (down == 0) {
                curHpb = 0;
                break;
            }

            curHpb = down;
        }
        return curHpb;
    }

    // TODO: add a test for this
    /// @return minPrice_ RAY - The current minimum pool price
    function getMinimumPoolPrice() public view returns (uint256 minPrice_) {
        minPrice_ = totalDebt != 0 ? Maths.rdiv(totalDebt, totalCollateral) : 0;
    }

    /// @dev Used for both pool and borrower level debt
    /// @param debt_ - Debt to check encumberance of
    /// @return encumberance_ RAY - The current encumberance of a given debt balance
    function getEncumberedCollateral(uint256 debt_) public view returns (uint256 encumberance_) {
        encumberance_ = debt_ != 0 ? Maths.rdiv(debt_, Maths.wadToRay(lup)) : 0;
    }


    /// @notice Calculate unaccrued interest for the pool, which may be added to totalDebt
    /// @notice to discover pending pool debt
    /// @return interest_ - Unaccumulated pool interest, RAY
    function getPendingPoolInterest() external view returns (uint256 interest_) {
        interest_ = totalDebt != 0 ? getPendingInterest(totalDebt, getPendingInflator(), inflatorSnapshot) : 0;
    }

    /// @return RAY - The current collateralization of the pool given totalCollateral and totalDebt
    function getPoolCollateralization() public view returns (uint256) {
        if (lup != 0 && totalDebt != 0) {
            return Maths.rdiv(totalCollateral, getEncumberedCollateral(totalDebt));
        }
        return Maths.ONE_RAY;
    }

    /// @notice Gets the current utilization of the pool
    /// @dev Will return 0 unless the pool has been borrowed from
    /// @return RAY - The current pool actual utilization
    function getPoolActualUtilization() public view returns (uint256) {
        if (totalDebt == 0) {
            return 0;
        }
        return
            Maths.rdiv(
                totalDebt,
                Maths.add(totalQuoteToken, totalDebt)
            );
    }

    /// @return RAY - The current pool target utilization
    function getPoolTargetUtilization() public view returns (uint256) {
        return Maths.rdiv(Maths.ONE_RAY, getPoolCollateralization());
    }

    /// @notice Called by lenders to update interest rate of the pool when actual > target utilization
    function updateInterestRate() external {
        // RAY
        uint256 actualUtilization = getPoolActualUtilization();
        if (
            actualUtilization != 0 &&
            previousRateUpdate < block.timestamp &&
            getPoolCollateralization() > Maths.ONE_RAY
        ) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(
                previousRate,
                (
                    Maths.sub(
                        Maths.add(Maths.rayToWad(actualUtilization), Maths.ONE_WAD),
                        Maths.rayToWad(getPoolTargetUtilization())
                    )
                )
            );
            previousRateUpdate = block.timestamp;
            emit UpdateInterestRate(oldRate, previousRate);
        }
    }

                /*****************************/
                /*** Borrower Management ***/
                /*****************************/

    /// @notice Returns a Tuple representing a given borrower's info struct
    function getBorrowerInfo(address borrower_)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        BorrowerInfo memory borrower = borrowers[borrower_];
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization = Maths.ONE_RAY;

        if (borrower.debt > 0 && borrower.inflatorSnapshot != 0) {
            borrowerPendingDebt  += getPendingInterest(borrower.debt, getPendingInflator(), borrower.inflatorSnapshot);
            collateralEncumbered  = getEncumberedCollateral(borrowerPendingDebt);
            collateralization     = Maths.rdiv(borrower.collateralDeposited, collateralEncumbered);
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

    /// @dev Supports passage of collateralDeposited and debt to enable calculation of potential borrower collateralization states, not just current.
    /// @param collateralDeposited_ RAY - Collateral amount to calculate a collateralization ratio for
    /// @param debt_ RAD - Debt position to calculate encumbered quotient
    /// @return RAY - The current collateralization of the borrowers given totalCollateral and totalDebt
    function getBorrowerCollateralization(uint256 collateralDeposited_, uint256 debt_)
        public
        view
        returns (uint256)
    {
        if (lup != 0 && debt_ != 0) {
            return Maths.rdiv(collateralDeposited_, getEncumberedCollateral(debt_));
        }
        return Maths.ONE_RAY;
    }

    /// @notice Estimate the price at which a loan can be taken
    function estimatePriceForLoan(uint256 amount_) public view returns (uint256) {
        // convert amount from WAD to collateral pool precision - RAD
        return _buckets.estimatePrice(Maths.wadToRay(amount_), lup == 0 ? hpb : lup);
    }

                /*****************************/
                /*** Lender Management ***/
                /*****************************/

    /// @notice Returns a given lender's LP tokens in a given price bucket
    /// @param owner_ The EOA to check token balance for
    /// @param price_ The price bucket for which the value should be calculated, WAD
    /// @return lpTokens - The EOA's lp token balance in the bucket, RAY
    function getLPTokenBalance(address owner_, uint256 price_) external view returns (uint256) {
        return lpBalance[owner_][price_];
    }

    /// @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens
    /// @param lpTokens_ The number of lpTokens to calculate amounts for
    /// @param price_ The price bucket for which the value should be calculated
    /// @return collateralTokens_ - The equivalent value of collateral tokens for the given LP Tokens, RAY
    /// @return quoteTokens_ - The equivalent value of quote tokens for the given LP Tokens, RAY
    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_)
        external
        view
        returns (uint256 collateralTokens_, uint256 quoteTokens_)
    {
        require(BucketMath.isValidPrice(price_), "ajna/invalid-bucket-price");

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
        collateralTokens_ = Maths.rmul(bucketCollateral, lenderShare);
        quoteTokens_      = Maths.rmul(Maths.add(onDeposit, debt), lenderShare);
    }

}
