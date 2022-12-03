// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './PoolLogic.sol';

library PoolUtils {
    uint256 internal constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;

    // minimum fee that can be applied for early withdraw penalty
    uint256 internal constant MIN_FEE = 0.0005 * 10**18;

    function encumberance(
        uint256 debt_,
        uint256 price_
    ) internal pure returns (uint256 encumberance_) {
        return price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    function collateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure returns (uint256) {
        uint256 encumbered = encumberance(debt_, price_);
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function poolTargetUtilization(
        uint256 debtEma_,
        uint256 lupColEma_
    ) internal pure returns (uint256) {
        return (debtEma_ != 0 && lupColEma_ != 0) ? Maths.wdiv(debtEma_, lupColEma_) : Maths.WAD;
    }

    function feeRate(
        uint256 interestRate_
    ) internal pure returns (uint256) {
        // greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps
        return Maths.max(Maths.wdiv(interestRate_, WAD_WEEKS_PER_YEAR), MIN_FEE);
    }

    function ptp(
        uint256 debt_,
        uint256 collateral_
    ) internal pure returns (uint256 ptp_) {
        if (collateral_ != 0) ptp_ = Maths.wdiv(debt_, collateral_);
    }

    function minDebtAmount(
        uint256 debt_,
        uint256 loansCount_
    ) internal pure returns (uint256 minDebtAmount_) {
        if (loansCount_ != 0) {
            minDebtAmount_ = Maths.wdiv(Maths.wdiv(debt_, Maths.wad(loansCount_)), 10**19);
        }
    }

    /**
     *  @dev Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     */
    function indexToPrice(
        uint256 index_
    ) internal pure returns (uint256) {
        return PoolLogic.indexToPrice(index_);
    }

    function priceToIndex(
        uint256 price_
    ) internal pure returns (uint256) {
        return PoolLogic.priceToIndex(price_);
    }

}
