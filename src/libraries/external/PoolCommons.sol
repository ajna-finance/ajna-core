// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import '../Deposits.sol';
import '../Buckets.sol';
import '../Loans.sol';

import '../../base/PoolHelper.sol';
import '../../base/Pool.sol';

/**
    @notice External library containing logic for common pool functionality:
            - interest rate accrual and interest rate params update
            - pool utilization
 */
library PoolCommons {
    uint256 internal constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 internal constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 10**18;
    uint256 internal constant LAMBDA_EMA_7D      = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR = 1e18 - LAMBDA_EMA_7D;
    int256  internal constant PERCENT_102        = 1.02 * 10**18;

    /**
     *  @notice Emitted when pool interest rate is updated.
     *  @param  oldRate Old pool interest rate.
     *  @param  newRate New pool interest rate.
     */
    event UpdateInterestRate(
        uint256 oldRate,
        uint256 newRate
    );

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Calculates new pool interest rate params (EMAs and interest rate value) and saves new values in storage.
     */
    function updateInterestRate(
        Pool.InterestParams storage interestParams_,
        Deposits.Data storage deposits_,
        Pool.PoolState memory poolState_,
        uint256 lup_
    ) external {
        // update pool EMAs for target utilization calculation
        uint256 curDebtEma = Maths.wmul(
                poolState_.accruedDebt,
                    EMA_7D_RATE_FACTOR
            ) + Maths.wmul(interestParams_.debtEma, LAMBDA_EMA_7D
        );
        uint256 curLupColEma = Maths.wmul(
                Maths.wmul(lup_, poolState_.collateral),
                EMA_7D_RATE_FACTOR
            ) + Maths.wmul(interestParams_.lupColEma, LAMBDA_EMA_7D
        );

        interestParams_.debtEma   = curDebtEma;
        interestParams_.lupColEma = curLupColEma;

        // update pool interest rate
        if (poolState_.accruedDebt != 0) {
            int256 mau = int256(                                       // meaningful actual utilization
                _utilization(
                    deposits_,
                    poolState_.accruedDebt,
                    poolState_.collateral
                )
            );
            int256 tu = int256(Maths.wdiv(curDebtEma, curLupColEma));  // target utilization

            if (!poolState_.isNewInterestAccrued) poolState_.rate = interestParams_.interestRate;
            // raise rates if 4*(tu-1.02*mau) < (tu+1.02*mau-1)^2-1
            // decrease rates if 4*(tu-mau) > 1-(tu+mau-1)^2
            int256 mau102 = mau * PERCENT_102 / 10**18;

            uint256 newInterestRate = poolState_.rate;
            if (4 * (tu - mau102) < ((tu + mau102 - 10**18) ** 2) / 10**18 - 10**18) {
                newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
            } else if (4 * (tu - mau) > 10**18 - ((tu + mau - 10**18) ** 2) / 10**18) {
                newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
            }

            if (poolState_.rate != newInterestRate) {
                interestParams_.interestRate       = uint208(newInterestRate);
                interestParams_.interestRateUpdate = uint48(block.timestamp);

                emit UpdateInterestRate(poolState_.rate, newInterestRate);
            }
        }
    }

    /**
     *  @notice Calculates new pool interest and scale the fenwick tree to update amount of debt owed to lenders (saved in storage).
     *  @param  debt_           Pool accrued debt.
     *  @param  collateral_     Collateral pledged in pool.
     *  @param  thresholdPrice_ Current Pool Threshold Price.
     *  @param  inflator_       Current pool inflator.
     *  @param  interestRate_   Current pool interest rate.
     *  @param  elapsed_        Time elapsed since last inflator update.
     *  @return newInflator_   The new value of pool inflator.
     */
    function accrueInterest(
        Deposits.Data storage deposits_,
        uint256 debt_,
        uint256 collateral_,
        uint256 thresholdPrice_,
        uint256 inflator_,
        uint256 interestRate_,
        uint256 elapsed_
    ) external returns (uint256 newInflator_) {
        // Scale the borrower inflator to update amount of interest owed by borrowers
        uint256 pendingFactor = PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
        newInflator_ = Maths.wmul(inflator_, pendingFactor);

        uint256 htp = Maths.wmul(thresholdPrice_, newInflator_);
        uint256 htpIndex = (htp != 0) ? _indexOf(htp) : 7_388; // if HTP is 0 then accrue interest at max index (min price)

        // Scale the fenwick tree to update amount of debt owed to lenders
        uint256 depositAboveHtp = Deposits.prefixSum(deposits_, htpIndex);

        if (depositAboveHtp != 0) {
            uint256 newInterest = Maths.wmul(
                _lenderInterestMargin(_utilization(deposits_, debt_, collateral_)),
                Maths.wmul(pendingFactor - Maths.WAD, debt_)
            );

            Deposits.mult(
                deposits_,
                htpIndex,
                Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD // lender factor
            );
        }
    }

    /**
     *  @notice Calculates pool interest factor for a given interest rate and time elapsed since last inflator update.
     *  @param  interestRate_   Current pool interest rate.
     *  @param  elapsed_        Time elapsed since last inflator update.
     *  @return The value of pool interest factor.
     */
    function pendingInterestFactor(
        uint256 interestRate_,
        uint256 elapsed_
    ) external pure returns (uint256) {
        return PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
    }

    /**
     *  @notice Calculates pool pending inflator given the current inflator, time of last update and current interest rate.
     *  @param  inflatorSnapshot_ Current pool interest rate.
     *  @param  inflatorUpdate    Timestamp when inflator was updated.
     *  @param  interestRate_     The interest rate of the pool.
     *  @return The pending value of pool inflator.
     */
    function pendingInflator(
        uint256 inflatorSnapshot_,
        uint256 inflatorUpdate,
        uint256 interestRate_
    ) external view returns (uint256) {
        return Maths.wmul(
            inflatorSnapshot_,
            PRBMathUD60x18.exp((interestRate_ * (block.timestamp - inflatorUpdate)) / 365 days)
        );
    }

    /**
     *  @notice Calculates lender interest margin for a given meaningful actual utilization.
     *  @dev Wrapper of the internal function.
     */
    function lenderInterestMargin(
        uint256 mau_
    ) external pure returns (uint256) {
        return _lenderInterestMargin(mau_);
    }

    /**
     *  @notice Calculates pool utilization based on pool size, accrued debt and collateral pledged in pool .
     *  @dev Wrapper of the internal function.
     */
    function utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) external view returns (uint256 utilization_) {
        return _utilization(deposits, debt_, collateral_);
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Calculates pool utilization based on pool size, accrued debt and collateral pledged in pool .
     *  @param  debt_        Pool accrued debt.
     *  @param  collateral_  Amount of collateral pledged in pool.
     *  @return utilization_ Pool utilization value.
     */
    function _utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256 utilization_) {
        if (collateral_ != 0) {
            uint256 ptp = _ptp(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits, _indexOf(ptp));

                if (depositAbove != 0) utilization_ = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }
    }

    /**
     *  @notice Calculates lender interest margin.
     *  @param  mau_ Meaningful actual utilization.
     *  @return The lender interest margin value.
     */
    function _lenderInterestMargin(
        uint256 mau_
    ) internal pure returns (uint256) {
        // TODO: Consider pre-calculating and storing a conversion table in a library or shared contract.
        // cubic root of the percentage of meaningful unutilized deposit
        uint256 base = 1000000 * 1e18 - Maths.wmul(Maths.min(mau_, 1e18), 1000000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

}