// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { InterestState, PoolState, DepositsState } from 'src/base/interfaces/IPool.sol';

import 'src/libraries/Deposits.sol';
import 'src/libraries/Buckets.sol';
import 'src/libraries/Loans.sol';

import 'src/base/PoolHelper.sol';

/**
    @notice External library containing logic for common pool functionality:
            - interest rate accrual and interest rate params update
            - pool utilization
 */
library PoolCommons {
    uint256 internal constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 internal constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 1e18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 1e18;
    uint256 internal constant LAMBDA_EMA_7D        = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR   = 1e18 - LAMBDA_EMA_7D;
    int256  internal constant PERCENT_102          = 1.02 * 1e18;

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
        InterestState storage interestParams_,
        DepositsState storage deposits_,
        PoolState memory poolState_,
        uint256 lup_
    ) external {

        // current values of EMA samples
        uint256 curDebtEma   = interestParams_.debtEma;
        uint256 curLupColEma = interestParams_.lupColEma;

        // meaningful actual utilization
        int256 mau;
        // meaningful actual utilization * 1.02
        int256 mau102;

        if (poolState_.debt != 0) {
            // update pool EMAs for target utilization calculation

            curDebtEma =
                Maths.wmul(poolState_.debt,  EMA_7D_RATE_FACTOR) +
                Maths.wmul(curDebtEma,       LAMBDA_EMA_7D
            );

            // lup * collateral EMA sample max value is 10 times current debt
            uint256 maxLupColEma = Maths.wmul(poolState_.debt, Maths.wad(10));

            // current lup * collateral value
            uint256 lupCol = Maths.wmul(poolState_.collateral, lup_);

            curLupColEma =
                Maths.wmul(Maths.min(lupCol, maxLupColEma), EMA_7D_RATE_FACTOR) +
                Maths.wmul(curLupColEma,                    LAMBDA_EMA_7D);

            // save EMA samples in storage
            interestParams_.debtEma   = curDebtEma;
            interestParams_.lupColEma = curLupColEma;

            // calculate meaningful actual utilization for interest rate update
            mau    = int256(_utilization(deposits_, poolState_.debt, poolState_.collateral));
            mau102 = mau * PERCENT_102 / 1e18;

        }

        // calculate target utilization
        int256 tu = (curDebtEma != 0 && curLupColEma != 0) ? int256(Maths.wdiv(curDebtEma, curLupColEma)) : int(Maths.WAD);

        if (!poolState_.isNewInterestAccrued) poolState_.rate = interestParams_.interestRate;

        uint256 newInterestRate = poolState_.rate;

        // raise rates if 4*(tu-1.02*mau) < (tu+1.02*mau-1)^2-1
        if (4 * (tu - mau102) < ((tu + mau102 - 1e18) ** 2) / 1e18 - 1e18) {
            newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
        }
        // decrease rates if 4*(tu-mau) > 1-(tu+mau-1)^2
        else if (4 * (tu - mau) > 1e18 - ((tu + mau - 1e18) ** 2) / 1e18) {
            newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
        }

        newInterestRate = Maths.min(500 * 1e18, Maths.max(0.001 * 1e18, newInterestRate));

        if (poolState_.rate != newInterestRate) {
            interestParams_.interestRate       = uint208(newInterestRate);
            interestParams_.interestRateUpdate = uint48(block.timestamp);

            emit UpdateInterestRate(poolState_.rate, newInterestRate);
        }
    }

    /**
     *  @notice Calculates new pool interest and scale the fenwick tree to update amount of debt owed to lenders (saved in storage).
     *  @param  thresholdPrice_ Current Pool Threshold Price.
     *  @param  elapsed_        Time elapsed since last inflator update.
     *  @return newInflator_   The new value of pool inflator.
     */
    function accrueInterest(
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        uint256 thresholdPrice_,
        uint256 elapsed_
    ) external returns (uint256 newInflator_, uint256 newInterest_) {
        // Scale the borrower inflator to update amount of interest owed by borrowers
        uint256 pendingFactor = PRBMathUD60x18.exp((poolState_.rate * elapsed_) / 365 days);

        newInflator_ = Maths.wmul(poolState_.inflator, pendingFactor);

        uint256 htp = Maths.wmul(thresholdPrice_, newInflator_);

        // if HTP is under the lowest price bucket then accrue interest at max index (min price)
        uint256 htpIndex = (htp >= MIN_PRICE) ? _indexOf(htp) : MAX_FENWICK_INDEX;

        // Scale the fenwick tree to update amount of debt owed to lenders
        uint256 depositAboveHtp = Deposits.prefixSum(deposits_, htpIndex);

        if (depositAboveHtp != 0) {
            newInterest_ = Maths.wmul(
                _lenderInterestMargin(_utilization(deposits_, poolState_.debt, poolState_.collateral)),
                Maths.wmul(pendingFactor - Maths.WAD, poolState_.debt)
            );

            Deposits.mult(
                deposits_,
                htpIndex,
                Maths.wdiv(newInterest_, depositAboveHtp) + Maths.WAD // lender factor
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
        DepositsState storage deposits,
        uint256 poolDebt_,
        uint256 collateral_
    ) external view returns (uint256 utilization_) {
        return _utilization(deposits, poolDebt_, collateral_);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Calculates pool utilization based on pool size, accrued debt and collateral pledged in pool .
     *  @param  poolDebt_    Pool accrued debt.
     *  @param  collateral_  Amount of collateral pledged in pool.
     *  @return utilization_ Pool utilization value.
     */
    function _utilization(
        DepositsState storage deposits,
        uint256 poolDebt_,
        uint256 collateral_
    ) internal view returns (uint256 utilization_) {
        if (collateral_ != 0) {
            uint256 ptp = _ptp(poolDebt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = ptp >= MIN_PRICE ? Deposits.prefixSum(deposits, _indexOf(ptp))
                    : Deposits.treeSum(deposits);

                if (depositAbove != 0) utilization_ = Maths.wdiv(
                    poolDebt_,
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
        uint256 base = 1000000 * 1e18 - Maths.wmul(Maths.min(mau_, 1e18), 1000000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            // cubic root of the percentage of meaningful unutilized deposit
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

}
