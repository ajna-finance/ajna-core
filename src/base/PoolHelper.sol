// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";

import '../libraries/Maths.sol';

    /*************************/
    /*** Price Conversions ***/
    /*************************/

    /**
        @dev constant price indices defining the min and max of the potential price range
     */
    int256 constant MAX_BUCKET_INDEX = 4_156;
    int256 constant MIN_BUCKET_INDEX = -3_232;

    uint256 constant MIN_PRICE = 99_836_282_890;
    uint256 constant MAX_PRICE = 1_004_968_987.606512354182109771 * 10**18;
    /**
        @dev step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
     */
    int256 constant FLOAT_STEP_INT = 1.005 * 10**18;

    /**
     *  @notice Calculates the price for a given Fenwick index
     *  @dev    Throws if index exceeds maximum constant
     *  @dev    Uses fixed-point math to get around lack of floating point numbers in EVM
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    Fenwick index is converted to bucket index
     *  @dev Fenwick index to bucket index conversion
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
        int256 bucketIndex = (index_ != 8191) ? MAX_BUCKET_INDEX - int256(index_) : MIN_BUCKET_INDEX;
        require(bucketIndex >= MIN_BUCKET_INDEX && bucketIndex <= MAX_BUCKET_INDEX, "BM:ITP:OOB");

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
        require(price_ >= MIN_PRICE && price_ <= MAX_PRICE, "BM:PTI:OOB");

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
     *  @notice Calculates encumberance for a debt amount at a given price.
     *  @param  debt_         The debt amount to calculate encumberance for.
     *  @param  price_        The price to calculate encumberance at.
     *  @return encumberance_ Encumberance value.
     */
    function _encumberance(
        uint256 debt_,
        uint256 price_
    ) pure returns (uint256 encumberance_) {
        return price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    /**
     *  @notice Calculates collateralization for a given debt and collateral amounts, at a given price.
     *  @param  debt_       The debt amount.
     *  @param  collateral_ The collateral amount.
     *  @param  price_      The price to calculate collateralization at.
     *  @return Collateralization value. 1**18 if debt amount is 0.
     */
    function _collateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) pure returns (uint256) {
        uint256 encumbered = _encumberance(debt_, price_);
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

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
        return Maths.max(Maths.wdiv(interestRate_, 52 * 10**18), 0.0005 * 10**18);
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
     *  @notice Calculates target utilization for given EMA values.
     *  @param  debtEma_   The EMA of debt value.
     *  @param  lupColEma_ The EMA of lup * collateral value.
     *  @return Target utilization of the pool.
     */
    function _targetUtilization(
        uint256 debtEma_,
        uint256 lupColEma_
    ) pure returns (uint256) {
        return (debtEma_ != 0 && lupColEma_ != 0) ? Maths.wdiv(debtEma_, lupColEma_) : Maths.WAD;
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
            uint256 secondsElapsed = block.timestamp - reserveAuctionKicked_;
            uint256 hoursComponent = 1e27 >> secondsElapsed / 3600;
            uint256 minutesComponent = Maths.rpow(MINUTE_HALF_LIFE, secondsElapsed % 3600 / 60);
            _price = Maths.rayToWad(1_000_000_000 * Maths.rmul(hoursComponent, minutesComponent));
        }
    }
