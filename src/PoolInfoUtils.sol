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

    /**********************/
    /*** Borrowers Info ***/
    /**********************/

    /**
     *  @notice Get borrower info in a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @param  borrower_ Borrower address.
     *  @return debt_       Current debt owed by borrower in given pool (WAD).
     *  @return collateral_ Collateral pledged by borrower in given pool (WAD).
     *  @return t0Np_       t0 Neutral price of the borrower (WAD).
     */
    function borrowerInfo(
        address ajnaPool_,
        address borrower_
    ) external view returns (
        uint256 debt_,
        uint256 collateral_,
        uint256 t0Np_
    ) {
        IPool pool = IPool(ajnaPool_);
        (
            uint256 inflator,
            uint256 inflatorUpdateTime
        ) = pool.inflatorInfo();

        (uint256 interestRate,) = pool.interestRateInfo();

        uint256 pendingInflator = PoolCommons.pendingInflator(inflator, inflatorUpdateTime, interestRate);

        uint256 t0Debt;
        (t0Debt, collateral_, t0Np_) = pool.borrowerInfo(borrower_);

        debt_ = Maths.wmul(t0Debt, pendingInflator);
    }

    /********************/
    /*** Buckets Info ***/
    /********************/

    /**
     *  @notice Get a bucket struct for a given index.
     *  @param  ajnaPool_         Address of the pool.
     *  @param  index_            The index of the bucket to retrieve.
     *  @return bucketPrice_      Bucket price (WAD)
     *  @return bucketDeposit_    Unscaled amount of quote token in bucket (WAD).
     *  @return bucketCollateral_ Unencumbered collateral in bucket (WAD).
     *  @return bucketLPs_        Outstanding LP balance in bucket (RAY).
     *  @return bucketScale_      Lender interest multiplier (WAD).
     *  @return bucketRate_       The exchange rate of the bucket (RAY).
     */
    function bucketInfo(
        address ajnaPool_,
        uint256 index_
    ) external view returns (
        uint256 bucketPrice_,
        uint256 bucketDeposit_,
        uint256 bucketCollateral_,
        uint256 bucketLPs_,
        uint256 bucketScale_,
        uint256 bucketRate_
    ) {
        IPool pool = IPool(ajnaPool_);

        bucketPrice_ = _priceAt(index_);

        (bucketLPs_, bucketCollateral_, , bucketDeposit_, bucketScale_) = pool.bucketInfo(index_);
        if (bucketLPs_ == 0) {
            bucketRate_ = Maths.RAY;
        } else {
            uint256 bucketSize = bucketDeposit_ * 1e18 + bucketPrice_ * bucketCollateral_;  // 10^36 + // 10^36
            bucketRate_ = bucketSize * 1e18 / bucketLPs_; // 10^27
        }
    }

    /******************/
    /*** Pools Info ***/
    /******************/

    /**
     *  @notice Returns info related to pool loans.
     *  @param  ajnaPool_              Address of the pool.
     *  @return poolSize_              The total amount of quote tokens in pool (WAD).
     *  @return loansCount_            The number of loans in pool.
     *  @return maxBorrower_           The address with the highest TP in pool.
     *  @return pendingInflator_       Pending inflator in pool (WAD).
     *  @return pendingInterestFactor_ Factor used to scale the inflator (WAD).
     */
    function poolLoansInfo(
        address ajnaPool_
    ) external view returns (
        uint256 poolSize_,
        uint256 loansCount_,
        address maxBorrower_,
        uint256 pendingInflator_,
        uint256 pendingInterestFactor_
    ) {
        IPool pool = IPool(ajnaPool_);

        poolSize_ = pool.depositSize();
        (maxBorrower_, , loansCount_) = pool.loansInfo();

        (
            uint256 inflator,
            uint256 inflatorUpdate
        ) = pool.inflatorInfo();

        (uint256 interestRate, ) = pool.interestRateInfo();

        pendingInflator_       = PoolCommons.pendingInflator(inflator, inflatorUpdate, interestRate);
        pendingInterestFactor_ = PoolCommons.pendingInterestFactor(interestRate, block.timestamp - inflatorUpdate);
    }

    /**
     *  @notice Returns info related to pool prices.
     *  @param  ajnaPool_ Address of the pool.
     *  @return hpb_      The price value of the current Highest Price Bucket (HPB), in WAD units.
     *  @return hpbIndex_ The index of the current Highest Price Bucket (HPB), in WAD units.
     *  @return htp_      The price value of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return htpIndex_ The index of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return lup_      The price value of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     *  @return lupIndex_ The index of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     */
    function poolPricesInfo(
        address ajnaPool_
    ) external view returns (
        uint256 hpb_,
        uint256 hpbIndex_,
        uint256 htp_,
        uint256 htpIndex_,
        uint256 lup_,
        uint256 lupIndex_
    ) {
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
     *  @param  ajnaPool_                   Address of the pool.
     *  @return reserves_                   The amount of excess quote tokens.
     *  @return claimableReserves_          Denominated in quote token, or 0 if no reserves can be auctioned.
     *  @return claimableReservesRemaining_ Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice_               Current price at which 1 quote token may be purchased, denominated in Ajna.
     *  @return timeRemaining_              Seconds remaining before takes are no longer allowed.
     */
    function poolReservesInfo(
        address ajnaPool_
    ) external view returns (
        uint256 reserves_,
        uint256 claimableReserves_,
        uint256 claimableReservesRemaining_,
        uint256 auctionPrice_,
        uint256 timeRemaining_
    ) {
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
     *  @param  ajnaPool_              Address of the pool.
     *  @return poolMinDebtAmount_     Minimum debt amount.
     *  @return poolCollateralization_ Current pool collateralization ratio.
     *  @return poolActualUtilization_ The current pool actual utilization, in WAD units.
     *  @return poolTargetUtilization_ The current pool Target utilization, in WAD units.
     */
    function poolUtilizationInfo(
        address ajnaPool_
    ) external view returns (
        uint256 poolMinDebtAmount_,
        uint256 poolCollateralization_,
        uint256 poolActualUtilization_,
        uint256 poolTargetUtilization_
    ) {
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
     *  @notice Returns the proportion of interest rate which is awarded to lenders in a given pool;
     *          the remainder accumulates in reserves.
     *  @param  ajnaPool_ Address of the pool.
    */
    function lenderInterestMargin(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 poolDebt,,)   = pool.debtInfo();
        uint256 poolCollateral = pool.pledgedCollateral();
        uint256 utilization    = pool.depositUtilization(poolDebt, poolCollateral);

        return  PoolCommons.lenderInterestMargin(utilization);
    }

    /**
     *  @notice Calculates fee rate for a given pool.
     *  @notice Calculated as greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps.
     *  @param  ajnaPool_ Address of the pool.
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
     *  @notice Calculate the amount of quote tokens in bucket for a given pool and given amount of LP Tokens.
     *  @param  ajnaPool_    Address of the pool.
     *  @param  lpTokens_    The number of lpTokens to calculate amounts for.
     *  @param  index_       The price bucket index for which the value should be calculated.
     *  @return The exact amount of quote tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToQuoteTokens(
        address ajnaPool_,
        uint256 lpTokens_,
        uint256 index_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);
        (uint256 bucketLPs_, uint256 bucketCollateral , , uint256 bucketDeposit, ) = pool.bucketInfo(index_);
        return _lpsToQuoteToken(
            bucketLPs_,
            bucketCollateral,
            bucketDeposit,
            lpTokens_,
            bucketDeposit,
            _priceAt(index_)
        );
    }

    /**
     *  @notice Calculate the amount of collateral tokens in bucket for a given pool and given amount of LP Tokens.
     *  @param  ajnaPool_         Address of the pool.
     *  @param  lpTokens_         The number of lpTokens to calculate amounts for.
     *  @param  index_            The price bucket index for which the value should be calculated.
     *  @return The exact amount of collateral tokens that can be exchanged for the given LP Tokens, WAD units.
     */
    function lpsToCollateral(
        address ajnaPool_,
        uint256 lpTokens_,
        uint256 index_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);
        (uint256 bucketLPs_, uint256 bucketCollateral , , uint256 bucketDeposit, ) = pool.bucketInfo(index_);
        return _lpsToCollateral(
            bucketCollateral,
            bucketLPs_,
            bucketDeposit,
            lpTokens_,
            _priceAt(index_)
        );
    }

    /************************/
    /*** Prices Utilities ***/
    /************************/

    /**
     *  @notice Calculates the price for a given index.
     *  @param  index_ Bucket index.
     *  @return Bucket price.
     */
    function indexToPrice(
        uint256 index_
    ) external pure returns (uint256) {
        return _priceAt(index_);
    }

    /**
     *  @notice Calculates the index for a given price.
     *  @param  price_ Price to retrieve index for.
     *  @return Bucket index.
     */
    function priceToIndex(
        uint256 price_
    ) external pure returns (uint256) {
        return _indexOf(price_);
    }

    /**
     *  @notice Returns the LUP of a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return LUP in pool.
     */
    function lup(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt,,) = pool.debtInfo();
        uint256 currentLupIndex = pool.depositIndex(debt);

        return _priceAt(currentLupIndex);
    }

    /**
     *  @notice Returns the LUP index for a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return LUP index of the pool.
     */
    function lupIndex(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt,,) = pool.debtInfo();

        return pool.depositIndex(debt);
    }

    /**
     *  @notice Returns the HPB of a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return HPB of the pool.
     */
    function hpb(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        uint256 hbpIndex = pool.depositIndex(1);

        return _priceAt(hbpIndex);
    }

    /**
     *  @notice Returns the HPB index of a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return HPB index of the pool.
     */
    function hpbIndex(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        return pool.depositIndex(1);
    }

    /**
     *  @notice Returns the HTP of a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return HTP of the pool.
     */
    function htp(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (, uint256 maxThresholdPrice, ) = pool.loansInfo();
        (uint256 inflatorSnapshot, )    = pool.inflatorInfo();

        return Maths.wmul(maxThresholdPrice, inflatorSnapshot);
    }

    /**
     *  @notice Returns the MOMP of a given pool.
     *  @param  ajnaPool_ Address of the pool.
     *  @return MOMP of the pool.
     */
    function momp(
        address ajnaPool_
    ) external view returns (uint256) {
        IPool pool = IPool(ajnaPool_);

        (uint256 debt, , )       = pool.debtInfo();
        ( , , uint256 noOfLoans) = pool.loansInfo();
        return _priceAt(pool.depositIndex(Maths.wdiv(debt, noOfLoans * 1e18)));
    }
}

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @notice Calculates encumberance for a debt amount at a given price.
     *  @param  debt_         The debt amount to calculate encumberance for.
     *  @param  price_        The price to calculate encumberance at.
     *  @return Encumberance value.
     */
    function _encumberance(
        uint256 debt_,
        uint256 price_
    ) pure returns (uint256) {
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
