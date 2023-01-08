// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { IPool, IERC20Token } from './interfaces/pool/IPool.sol';

import {
    _claimableReserves,
    _feeRate,
    _indexOf,
    _lpsToCollateral,
    _lpsToQuoteToken,
    _minDebtAmount,
    _priceAt,
    _reserveAuctionPrice,
    MAX_FENWICK_INDEX,
    MIN_PRICE
} from './libraries/helpers/PoolHelper.sol';

import { Buckets } from './libraries/internal/Buckets.sol';
import { Maths }   from './libraries/internal/Maths.sol';

import { Auctions }    from './libraries/external/Auctions.sol';
import { PoolCommons } from './libraries/external/PoolCommons.sol';

/**
 *  @title  Pool Info Utils contract
 *  @notice Contract for providing pools information for any deployed pool.
 *  @dev    Pool info is calculated using same helper functions / logic as in Pool contracts.
 */
contract PoolInfoUtils {

    function borrowerInfo(address ajnaPool_, address borrower_)
        external
        view
        returns (
            uint256 debt_,             // current debt owed by borrower              (WAD)
            uint256 collateral_,       // deposited collateral including encumbered  (WAD)
            uint256 t0Np_              // Np / inflator, used in neutralPrice calc   (WAD)
        )
    {
        IPool pool = IPool(ajnaPool_);

        (
            uint256 poolInflatorSnapshot,
            uint256 lastInflatorSnapshotUpdate
        ) = pool.inflatorInfo();

        (uint256 interestRate,) = pool.interestRateInfo();

        uint256 pendingInflator = PoolCommons.pendingInflator(poolInflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);

        uint256 t0Debt;
        (t0Debt, collateral_, t0Np_)  = pool.borrowerInfo(borrower_);

        debt_ = Maths.wmul(t0Debt, pendingInflator);
    }

    /**
     *  @notice Get a bucket struct for a given index.
     *  @param  index_             The index of the bucket to retrieve.
     *  @return price_             Bucket price (WAD)
     *  @return quoteTokens_       Amount of quote token in bucket, deposit + interest (WAD)
     *  @return collateral_        Unencumbered collateral in bucket (WAD).
     *  @return bucketLPs_         Outstanding LP balance in bucket (WAD)
     *  @return scale_             Lender interest multiplier (WAD).
     *  @return exchangeRate_      The exchange rate of the bucket, in RAY units.
     */
    function bucketInfo(address ajnaPool_, uint256 index_)
        external
        view
        returns (
            uint256 price_,
            uint256 quoteTokens_,
            uint256 collateral_,
            uint256 bucketLPs_,
            uint256 scale_,
            uint256 exchangeRate_
        )
    {
        IPool pool = IPool(ajnaPool_);

        price_ = _priceAt(index_);

        (bucketLPs_, collateral_, , quoteTokens_, scale_) = pool.bucketInfo(index_);
        if (bucketLPs_ == 0) {
            exchangeRate_ = Maths.RAY;
        } else {
            uint256 bucketSize = quoteTokens_ * 1e18 + price_ * collateral_;  // 10^36 + // 10^36
            exchangeRate_ = bucketSize * 1e18 / bucketLPs_; // 10^27
        }
    }

    /**
     *  @notice Returns info related to pool loans.
     *  @return poolSize_              The total amount of quote tokens in pool (WAD).
     *  @return loansCount_            The number of loans in pool.
     *  @return maxBorrower_           The address with the highest TP in pool.
     *  @return pendingInflator_       Pending inflator in pool.
     *  @return pendingInterestFactor_ Factor used to scale the inflator.
     */
    function poolLoansInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 poolSize_,
            uint256 loansCount_,
            address maxBorrower_,
            uint256 pendingInflator_,
            uint256 pendingInterestFactor_
        )
    {
        IPool pool = IPool(ajnaPool_);

        poolSize_ = pool.depositSize();
        (maxBorrower_, , loansCount_) = pool.loansInfo();

        (
            uint256 inflatorSnapshot,
            uint256 lastInflatorSnapshotUpdate
        ) = pool.inflatorInfo();

        (uint256 interestRate, ) = pool.interestRateInfo();

        pendingInflator_       = PoolCommons.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);
        pendingInterestFactor_ = PoolCommons.pendingInterestFactor(interestRate, block.timestamp - lastInflatorSnapshotUpdate);
    }

    /**
     *  @notice Returns info related to pool prices.
     *  @return hpb_      The price value of the current Highest Price Bucket (HPB), in WAD units.
     *  @return hpbIndex_ The index of the current Highest Price Bucket (HPB), in WAD units.
     *  @return htp_      The price value of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return htpIndex_ The index of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return lup_      The price value of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     *  @return lupIndex_ The index of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     */
    function poolPricesInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 hpb_,
            uint256 hpbIndex_,
            uint256 htp_,
            uint256 htpIndex_,
            uint256 lup_,
            uint256 lupIndex_
        )
    {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt,,) = pool.debtInfo();

        hpbIndex_ = pool.depositIndex(1);
        hpb_      = _priceAt(hpbIndex_);

        (, uint256 maxThresholdPrice,) = pool.loansInfo();
        (uint256 inflatorSnapshot,)    = pool.inflatorInfo();

        htp_      = Maths.wmul(maxThresholdPrice, inflatorSnapshot);
        htpIndex_ = htp_ >= MIN_PRICE ? _indexOf(htp_) : MAX_FENWICK_INDEX;
        lupIndex_ = pool.depositIndex(debt);
        lup_      = _priceAt(lupIndex_);
    }

    /**
     *  @notice Returns info related to Claimaible Reserve Auction.
     *  @return reserves_                   The amount of excess quote tokens.
     *  @return claimableReserves_          Denominated in quote token, or 0 if no reserves can be auctioned.
     *  @return claimableReservesRemaining_ Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice_               Current price at which 1 quote token may be purchased, denominated in Ajna.
     *  @return timeRemaining_              Seconds remaining before takes are no longer allowed.
     */
    function poolReservesInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 reserves_,
            uint256 claimableReserves_,
            uint256 claimableReservesRemaining_,
            uint256 auctionPrice_,
            uint256 timeRemaining_
        )
    {
        IPool pool = IPool(ajnaPool_);

        (,uint256 poolDebt,) = pool.debtInfo();
        uint256 poolSize     = pool.depositSize();

        uint256 quoteTokenBalance = IERC20Token(pool.quoteTokenAddress()).balanceOf(ajnaPool_);

        (uint256 bondEscrowed, uint256 unclaimedReserve, uint256 auctionKickTime) = pool.reservesInfo();

        // due to rounding issues, especially in Auction.settle, this can be slighly negative
        if( poolDebt + quoteTokenBalance >= poolSize + bondEscrowed + unclaimedReserve) {
            reserves_ = poolDebt + quoteTokenBalance - poolSize - bondEscrowed - unclaimedReserve;
        }

        claimableReserves_ = _claimableReserves(
            poolDebt,
            poolSize,
            bondEscrowed,
            unclaimedReserve,
            quoteTokenBalance
        );

        claimableReservesRemaining_ = unclaimedReserve;
        auctionPrice_               = _reserveAuctionPrice(auctionKickTime);
        timeRemaining_              = 3 days - Maths.min(3 days, block.timestamp - auctionKickTime);
    }

    /**
     *  @notice Returns info related to Claimaible Reserve Auction.
     *  @return poolMinDebtAmount_     Minimum debt amount.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function poolUtilizationInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 poolMinDebtAmount_,
            uint256 poolCollateralization_,
            uint256 poolActualUtilization_,
            uint256 poolTargetUtilization_
        )
    {
        IPool pool = IPool(ajnaPool_);

        (uint256 poolDebt,,)    = pool.debtInfo();
        uint256 poolCollateral  = pool.pledgedCollateral();
        (, , uint256 noOfLoans) = pool.loansInfo();

        if (poolDebt != 0) poolMinDebtAmount_ = _minDebtAmount(poolDebt, noOfLoans);

        uint256 currentLup = _priceAt(pool.depositIndex(poolDebt));

        poolCollateralization_ = _collateralization(poolDebt, poolCollateral, currentLup);
        poolActualUtilization_ = pool.depositUtilization(poolDebt, poolCollateral);

        (uint256 debtEma, uint256 lupColEma) = pool.emasInfo();
        poolTargetUtilization_ = _targetUtilization(debtEma, lupColEma);
    }

    /**
     *  @notice Returns the proportion of interest rate which is awarded to lenders;
     *          the remainder accumulates in reserves.
    */
    function lenderInterestMargin(address ajnaPool_)
        external
        view
        returns (uint256 lenderInterestMargin_)
    {
        IPool pool = IPool(ajnaPool_);

        (uint256 poolDebt,,)   = pool.debtInfo();
        uint256 poolCollateral = pool.pledgedCollateral();
        uint256 utilization    = pool.depositUtilization(poolDebt, poolCollateral);

        lenderInterestMargin_ = PoolCommons.lenderInterestMargin(utilization);
    }

    function indexToPrice(
        uint256 index_
    ) external pure returns (uint256)
    {
        return _priceAt(index_);
    }

    function priceToIndex(
        uint256 price_
    ) external pure returns (uint256)
    {
        return _indexOf(price_);
    }

    function lup(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt,,) = pool.debtInfo();
        uint256 currentLupIndex = pool.depositIndex(debt);

        return _priceAt(currentLupIndex);
    }

    function lupIndex(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt,,) = pool.debtInfo();

        return pool.depositIndex(debt);
    }

    function hpb(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        uint256 hbpIndex = pool.depositIndex(1);

        return _priceAt(hbpIndex);
    }

    function hpbIndex(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        return pool.depositIndex(1);
    }

    function htp(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (, uint256 maxThresholdPrice, ) = pool.loansInfo();
        (uint256 inflatorSnapshot, )    = pool.inflatorInfo();

        return Maths.wmul(maxThresholdPrice, inflatorSnapshot);
    }

    function momp(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt, , )       = pool.debtInfo();
        ( , , uint256 noOfLoans) = pool.loansInfo();
        return _priceAt(pool.depositIndex(Maths.wdiv(debt, noOfLoans * 1e18)));
    }

    /**
     *  @notice Calculates fee rate for a pool.
     *  @notice Calculated as greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps.
     *  @return Fee rate applied to the given interest rate.
     */
    function feeRate(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 interestRate,) = pool.interestRateInfo();

        return _feeRate(interestRate);
    }

    /**
     *  @notice Calculate the amount of quote tokens in bucket for a given amount of LP Tokens.
     *  @param  lpTokens_    The number of lpTokens to calculate amounts for.
     *  @param  index_       The price bucket index for which the value should be calculated.
     *  @return quoteAmount_ The exact amount of quote tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToQuoteTokens(
        address ajnaPool_,
        uint256 lpTokens_,
        uint256 index_
    ) external view returns (uint256 quoteAmount_) {
        IPool pool = IPool(ajnaPool_);
        (uint256 bucketLPs_, uint256 bucketCollateral , , uint256 bucketDeposit, ) = pool.bucketInfo(index_);
        quoteAmount_ = _lpsToQuoteToken(
            bucketLPs_,
            bucketCollateral,
            bucketDeposit,
            lpTokens_,
            bucketDeposit,
            _priceAt(index_)
        );
    }

    /**
     *  @notice Calculate the amount of collateral tokens in bucket for a given amount of LP Tokens.
     *  @param  lpTokens_         The number of lpTokens to calculate amounts for.
     *  @param  index_            The price bucket index for which the value should be calculated.
     *  @return collateralAmount_ The exact amount of collateral tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToCollateral(
        address ajnaPool_,
        uint256 lpTokens_,
        uint256 index_
    ) external view returns (uint256 collateralAmount_) {
        IPool pool = IPool(ajnaPool_);
        (uint256 bucketLPs_, uint256 bucketCollateral , , uint256 bucketDeposit, ) = pool.bucketInfo(index_);
        collateralAmount_ = _lpsToCollateral(
            bucketCollateral,
            bucketLPs_,
            bucketDeposit,
            lpTokens_,
            _priceAt(index_)
        );
    }
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
