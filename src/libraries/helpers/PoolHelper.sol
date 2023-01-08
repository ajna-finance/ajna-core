// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";

import { PoolType } from '../../interfaces/pool/IPool.sol';

import { Buckets } from '../internal/Buckets.sol';
import { Maths }   from '../internal/Maths.sol';

    error BucketIndexOutOfBounds();
    error BucketPriceOutOfBounds();

    /*************************/
    /*** Price Conversions ***/
    /*************************/

    /**
        @dev constant price indices defining the min and max of the potential price range
     */
    int256  constant MAX_BUCKET_INDEX  =  4_156;
    int256  constant MIN_BUCKET_INDEX  = -3_232;
    uint256 constant MAX_FENWICK_INDEX =  7_388;

    uint256 constant MIN_PRICE = 99_836_282_890;
    uint256 constant MAX_PRICE = 1_004_968_987.606512354182109771 * 1e18;
    /**
        @dev step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
     */
    int256 constant FLOAT_STEP_INT = 1.005 * 1e18;

    /**
     *  @notice Calculates the price for a given Fenwick index
     *  @dev    Throws if index exceeds maximum constant
     *  @dev    Uses fixed-point math to get around lack of floating point numbers in EVM
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    Fenwick index is converted to bucket index
     *  @dev    Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     *  @dev    V1: price = MIN_PRICE + (FLOAT_STEP * index)
     *          V2: price = MAX_PRICE * (FLOAT_STEP ** (abs(int256(index - MAX_PRICE_INDEX))));
     *          V3 (final): x^y = 2^(y*log_2(x))
     */
    function _priceAt(
        uint256 index_
    ) pure returns (uint256) {
        // Lowest Fenwick index is highest price, so invert the index and offset by highest bucket index.
        int256 bucketIndex = MAX_BUCKET_INDEX - int256(index_);
        if (bucketIndex < MIN_BUCKET_INDEX || bucketIndex > MAX_BUCKET_INDEX) revert BucketIndexOutOfBounds();

        return uint256(
            PRBMathSD59x18.exp2(
                PRBMathSD59x18.mul(
                    PRBMathSD59x18.fromInt(bucketIndex),
                    PRBMathSD59x18.log2(FLOAT_STEP_INT)
                )
            )
        );
    }

    /**
     *  @notice Calculates the Fenwick index for a given price
     *  @dev    Throws if price exceeds maximum constant
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    V1: bucket index = (price - MIN_PRICE) / FLOAT_STEP
     *          V2: bucket index = (log(FLOAT_STEP) * price) /  MAX_PRICE
     *          V3 (final): bucket index =  log_2(price) / log_2(FLOAT_STEP)
     *  @dev    Fenwick index = 7388 - bucket index + 3232
     */
    function _indexOf(
        uint256 price_
    ) pure returns (uint256) {
        if (price_ < MIN_PRICE || price_ > MAX_PRICE) revert BucketPriceOutOfBounds();

        int256 index = PRBMathSD59x18.div(
            PRBMathSD59x18.log2(int256(price_)),
            PRBMathSD59x18.log2(FLOAT_STEP_INT)
        );

        int256 ceilIndex = PRBMathSD59x18.ceil(index);
        if (index < 0 && ceilIndex - index > 0.5 * 1e18) {
            return uint256(4157 - PRBMathSD59x18.toInt(ceilIndex));
        }
        return uint256(4156 - PRBMathSD59x18.toInt(ceilIndex));
    }

    /**********************/
    /*** Pool Utilities ***/
    /**********************/

    /**
     *  @notice Calculates the minimum debt amount that can be borrowed or can remain in a loan in pool.
     *  @param  debt_          The debt amount to calculate minimum debt amount for.
     *  @param  loansCount_    The number of loans in pool.
     *  @return minDebtAmount_ Minimum debt amount value of the pool.
     */
    function _minDebtAmount(
        uint256 debt_,
        uint256 loansCount_
    ) pure returns (uint256 minDebtAmount_) {
        if (loansCount_ != 0) {
            minDebtAmount_ = Maths.wdiv(Maths.wdiv(debt_, Maths.wad(loansCount_)), 10**19);
        }
    }

    /**
     *  @notice Calculates fee rate for a given interest rate.
     *  @notice Calculated as greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps.
     *  @param  interestRate_ The current interest rate.
     *  @return Fee rate applied to the given interest rate.
     */
    function _feeRate(
        uint256 interestRate_
    ) pure returns (uint256) {
        // greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps
        return Maths.max(Maths.wdiv(interestRate_, 52 * 1e18), 0.0005 * 1e18);
    }

    /**
     *  @notice Calculates Pool Threshold Price (PTP) for a given debt and collateral amount.
     *  @param  debt_       The debt amount to calculate PTP for.
     *  @param  collateral_ The amount of collateral to calculate PTP for.
     *  @return ptp_        Pool Threshold Price value.
     */
    function _ptp(
        uint256 debt_,
        uint256 collateral_
    ) pure returns (uint256 ptp_) {
        if (collateral_ != 0) ptp_ = Maths.wdiv(debt_, collateral_);
    }

    /**
     *  @notice Collateralization calculation.
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @param type_       Type of the pool.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_,
        uint8 type_
    ) pure returns (bool) {
        if (type_ == uint8(PoolType.ERC20)) return Maths.wmul(collateral_, price_) >= debt_;
        else {
            //slither-disable-next-line divide-before-multiply
            collateral_ = (collateral_ / Maths.WAD) * Maths.WAD; // use collateral floor
            return Maths.wmul(collateral_, price_) >= debt_;
        }
    }

    /**
     *  @notice Price precision adjustment used in calculating collateral dust for a bucket.
     *          To ensure the accuracy of the exchange rate calculation, buckets with smaller prices require
     *          larger minimum amounts of collateral.  This formula imposes a lower bound independent of token scale.
     *  @param  bucketIndex_              Index of the bucket, or 0 for encumbered collateral with no bucket affinity.
     *  @return pricePrecisionAdjustment_ Unscaled integer of the minimum number of decimal places the dust limit requires.
     */
    function _getCollateralDustPricePrecisionAdjustment(
        uint256 bucketIndex_
    ) pure returns (uint256 pricePrecisionAdjustment_) {
        // conditional is a gas optimization
        if (bucketIndex_ > 3900) {
            int256 bucketOffset = int256(bucketIndex_ - 3900);
            int256 result = PRBMathSD59x18.sqrt(PRBMathSD59x18.div(bucketOffset * 1e18, int256(36 * 1e18)));
            pricePrecisionAdjustment_ = uint256(result / 1e18);
        }
    }

    /**
     *  @notice Returns the amount of collateral calculated for the given amount of LPs.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate collateral for.
     *  @param  bucketPrice_      Bucket price.
     *  @return collateralAmount_ Amount of collateral calculated for the given LPs amount.
     */
    function _lpsToCollateral(
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 bucketPrice_
    ) pure returns (uint256 collateralAmount_) {
        // max collateral to lps
        uint256 rate = Buckets.getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_);

        collateralAmount_ = Maths.rwdivw(Maths.rmul(lenderLPsBalance_, rate), bucketPrice_);

        if (collateralAmount_ > bucketCollateral_) {
            // user is owed more collateral than is available in the bucket
            collateralAmount_ = bucketCollateral_;
        }
    }

    /**
     *  @notice Returns the amount of quote tokens calculated for the given amount of LPs.
     *  @param  bucketLPs_        Amount of LPs in bucket.
     *  @param  bucketCollateral_ Amount of collateral in bucket.
     *  @param  deposit_          Current bucket deposit (quote tokens). Used to calculate bucket's exchange rate / LPs.
     *  @param  lenderLPsBalance_ The amount of LPs to calculate quote token amount for.
     *  @param  maxQuoteToken_    The max quote token amount to calculate LPs for.
     *  @param  bucketPrice_      Bucket price.
     *  @return quoteTokenAmount_ Amount of quote tokens calculated for the given LPs amount.
     */
    function _lpsToQuoteToken(
        uint256 bucketLPs_,
        uint256 bucketCollateral_,
        uint256 deposit_,
        uint256 lenderLPsBalance_,
        uint256 maxQuoteToken_,
        uint256 bucketPrice_
    ) pure returns (uint256 quoteTokenAmount_) {
        uint256 rate = Buckets.getExchangeRate(bucketCollateral_, bucketLPs_, deposit_, bucketPrice_);

        quoteTokenAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance_, rate));

        if (quoteTokenAmount_ > deposit_)       quoteTokenAmount_ = deposit_;
        if (quoteTokenAmount_ > maxQuoteToken_) quoteTokenAmount_ = maxQuoteToken_;
    }

    /**
     *  @notice Rounds a token amount down to the minimum amount permissible by the token scale.
     *  @param  amount_       Value to be rounded.
     *  @param  tokenScale_   Scale of the token, presented as a power of 10.
     *  @return scaledAmount_ Rounded value.
     */
    function _roundToScale(
        uint256 amount_,
        uint256 tokenScale_
    ) pure returns (uint256 scaledAmount_) {
        scaledAmount_ = (amount_ / tokenScale_) * tokenScale_;
    }

    /**
     *  @notice Rounds a token amount up to the next amount permissible by the token scale.
     *  @param  amount_       Value to be rounded.
     *  @param  tokenScale_   Scale of the token, presented as a power of 10.
     *  @return scaledAmount_ Rounded value.
     */
    function _roundUpToScale(
        uint256 amount_,
        uint256 tokenScale_
    ) pure returns (uint256 scaledAmount_) {
        if (amount_ % tokenScale_ == 0)
            scaledAmount_ = amount_;
        else
            scaledAmount_ = _roundToScale(amount_, tokenScale_) + tokenScale_;
    }

    /*********************************/
    /*** Reserve Auction Utilities ***/
    /*********************************/

    uint256 constant MINUTE_HALF_LIFE    = 0.988514020352896135_356867505 * 1e27;  // 0.5^(1/60)

    function _claimableReserves(
        uint256 debt_,
        uint256 poolSize_,
        uint256 totalBondEscrowed_,
        uint256 reserveAuctionUnclaimed_,
        uint256 quoteTokenBalance_
    ) pure returns (uint256 claimable_) {
        claimable_ = Maths.wmul(0.995 * 1e18, debt_) + quoteTokenBalance_;

        claimable_ -= Maths.min(claimable_, poolSize_ + totalBondEscrowed_ + reserveAuctionUnclaimed_);
    }

    function _reserveAuctionPrice(
        uint256 reserveAuctionKicked_
    ) view returns (uint256 _price) {
        if (reserveAuctionKicked_ != 0) {
            uint256 secondsElapsed   = block.timestamp - reserveAuctionKicked_;
            uint256 hoursComponent   = 1e27 >> secondsElapsed / 3600;
            uint256 minutesComponent = Maths.rpow(MINUTE_HALF_LIFE, secondsElapsed % 3600 / 60);

            _price = Maths.rayToWad(1_000_000_000 * Maths.rmul(hoursComponent, minutesComponent));
        }
    }