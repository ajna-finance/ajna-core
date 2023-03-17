// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { InterestState, EmaState, PoolState, DepositsState } from '../../interfaces/pool/commons/IPoolState.sol';

import { _dwatp, _indexOf, MAX_FENWICK_INDEX, MIN_PRICE, MAX_PRICE } from '../helpers/PoolHelper.sol';

import { Deposits } from '../internal/Deposits.sol';
import { Buckets }  from '../internal/Buckets.sol';
import { Loans }    from '../internal/Loans.sol';
import { Maths }    from '../internal/Maths.sol';

/**
    @title  PoolCommons library
    @notice External library containing logic for common pool functionality:
            - interest rate accrual and interest rate params update
            - pool utilization
 */
library PoolCommons {

    /*****************/
    /*** Constants ***/
    /*****************/

    uint256 internal constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 internal constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 1e18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 1e18;
    int256  internal constant PERCENT_102          = 1.02 * 1e18;
    int256  internal constant NEG_H_MAU_HOURS      = -0.057762265046662105 * 1e18; // -ln(2)/12
    int256  internal constant NEG_H_TU_HOURS       = -0.008251752149523158 * 1e18; // -ln(2)/84

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct UpdateInterestLocalVars {
        uint256 debtEma;
        uint256 depositEma;
        uint256 debtColEma;
        uint256 lupt0DebtEma;
        uint256 t0Debt2ToCollateral;
        uint256 newMeaningfulDeposit;
        uint256 newDebt;
        uint256 newDebtCol;
        uint256 newLupt0Debt;
        uint256 lastEmaUpdate;
        int256 elapsed;
        int256 weightMau;
        int256 weightTu;
        uint256 newInterestRate;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Calculates EMAs, caches values required for calculating interest rate, and saves new values in storage.
     *  @notice Calculates new pool interest rate (Never called more than once every 12 hours) and saves new values in storage.
     *  @dev    write state:
     *              - EMAs state
     *              - interest rate accumulator and interestRateUpdate state
     *  @dev    emit events:
     *              - UpdateInterestRate
     */
    function updateInterestState(
        InterestState storage interestParams_,
        EmaState      storage emaParams_,
        DepositsState storage deposits_,
        PoolState memory poolState_,
        uint256 lup_
    ) external {
        UpdateInterestLocalVars memory vars;
        // load existing EMA values
        vars.debtEma       = emaParams_.debtEma;
        vars.depositEma    = emaParams_.depositEma;
        vars.debtColEma    = emaParams_.debtColEma;
        vars.lupt0DebtEma  = emaParams_.lupt0DebtEma;
        vars.lastEmaUpdate = emaParams_.emaUpdate;

        vars.t0Debt2ToCollateral = interestParams_.t0Debt2ToCollateral;

        // calculate new interest params
        vars.newMeaningfulDeposit = _meaningfulDeposit(
            deposits_,
            poolState_.t0Debt,
            poolState_.inflator,
            vars.t0Debt2ToCollateral
        );
        vars.newDebt      = poolState_.debt;
        vars.newDebtCol   = Maths.wmul(poolState_.inflator, vars.t0Debt2ToCollateral);
        vars.newLupt0Debt = Maths.wmul(lup_, poolState_.t0Debt);

        // update EMAs only once per block
        if (vars.lastEmaUpdate != block.timestamp) {

            // We do not need to calculate these during initialization, 
            // but the conditional to check each time would be more expensive thereafter.
            vars.elapsed   = int256(Maths.wdiv(block.timestamp - vars.lastEmaUpdate, 1 hours));
            vars.weightMau = PRBMathSD59x18.exp(PRBMathSD59x18.mul(NEG_H_MAU_HOURS, vars.elapsed));
            vars.weightTu  = PRBMathSD59x18.exp(PRBMathSD59x18.mul(NEG_H_TU_HOURS,  vars.elapsed));

            // calculate the t0 debt EMA, used for MAU
            vars.debtEma = vars.debtEma == 0 ? vars.newDebt :
                uint256(
                    PRBMathSD59x18.mul(vars.weightMau, int256(vars.debtEma)) +
                    PRBMathSD59x18.mul(1e18 - vars.weightMau, int256(interestParams_.debt))
                );

            // update the meaningful deposit EMA, used for MAU
            vars.depositEma = vars.depositEma == 0 ? vars.newMeaningfulDeposit :
                uint256(
                    PRBMathSD59x18.mul(vars.weightMau, int256(vars.depositEma)) +
                    PRBMathSD59x18.mul(1e18 - vars.weightMau, int256(interestParams_.meaningfulDeposit))
                );

            // calculate the debt squared to collateral EMA, used for TU
            vars.debtColEma = vars.debtColEma == 0 ? vars.newDebtCol :
                uint256(
                    PRBMathSD59x18.mul(vars.weightTu, int256(vars.debtColEma)) +
                    PRBMathSD59x18.mul(1e18 - vars.weightTu, int256(interestParams_.debtCol))
                );

            // calculate the EMA of LUP * t0 debt
            vars.lupt0DebtEma = vars.lupt0DebtEma == 0 ? vars.newLupt0Debt :
                uint256(
                    PRBMathSD59x18.mul(vars.weightTu, int256(vars.lupt0DebtEma)) +
                    PRBMathSD59x18.mul(1e18 - vars.weightTu, int256(interestParams_.lupt0Debt))
                );

            // save EMAs in storage
            emaParams_.debtEma      = vars.debtEma;
            emaParams_.depositEma   = vars.depositEma;
            emaParams_.debtColEma   = vars.debtColEma;
            emaParams_.lupt0DebtEma = vars.lupt0DebtEma;

            // save last EMA update time
            emaParams_.emaUpdate = block.timestamp;
        }

        // calculate and update interest rate if it has been more than 12 hours since the last update
        if (block.timestamp - interestParams_.interestRateUpdate > 12 hours) {
            vars.newInterestRate = _calculateInterestRate(
                poolState_,
                interestParams_.interestRate,
                vars.debtEma,
                vars.depositEma,
                vars.debtColEma,
                vars.lupt0DebtEma
            );

            if (poolState_.rate != vars.newInterestRate) {
                interestParams_.interestRate       = uint208(vars.newInterestRate);
                interestParams_.interestRateUpdate = uint48(block.timestamp);

                emit UpdateInterestRate(poolState_.rate, vars.newInterestRate);
            }
        }

        // save new interest rate params to storage
        interestParams_.debt              = vars.newDebt;
        interestParams_.meaningfulDeposit = vars.newMeaningfulDeposit;
        interestParams_.debtCol           = vars.newDebtCol;
        interestParams_.lupt0Debt         = vars.newLupt0Debt;
    }

    /**
     *  @notice Calculates new pool interest and scale the fenwick tree to update amount of debt owed to lenders (saved in storage).
     *  @dev write state:
     *       - Deposits.mult (scale Fenwick tree with new interest accrued):
     *         - update scaling array state
     *  @param  thresholdPrice_ Current Pool Threshold Price.
     *  @param  elapsed_        Time elapsed since last inflator update.
     *  @return newInflator_   The new value of pool inflator.
     */
    function accrueInterest(
        EmaState      storage emaParams_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        uint256 thresholdPrice_,
        uint256 elapsed_
    ) external returns (uint256 newInflator_, uint256 newInterest_) {
        // Scale the borrower inflator to update amount of interest owed by borrowers
        uint256 pendingFactor = PRBMathUD60x18.exp((poolState_.rate * elapsed_) / 365 days);

        // calculate the highest threshold price
        newInflator_ = Maths.wmul(poolState_.inflator, pendingFactor);
        uint256 htp = Maths.wmul(thresholdPrice_, newInflator_);

        uint256 htpIndex;
        if (htp > MAX_PRICE)
            // if HTP is over the highest price bucket then no buckets earn interest
            htpIndex = 1;
        else if (htp < MIN_PRICE)
            // if HTP is under the lowest price bucket then all buckets earn interest
            htpIndex = MAX_FENWICK_INDEX;
        else
            htpIndex = _indexOf(htp);

        uint256 depositAboveHtp   = Deposits.prefixSum(deposits_, htpIndex);

        if (depositAboveHtp != 0) {
            newInterest_ = Maths.wmul(
                _lenderInterestMargin(_utilization(emaParams_.debtEma, emaParams_.depositEma)),
                Maths.wmul(pendingFactor - Maths.WAD, poolState_.debt)
            );

            // Scale the fenwick tree to update amount of debt owed to lenders
            Deposits.mult(
                deposits_,
                htpIndex,
                Maths.wdiv(newInterest_, depositAboveHtp) + Maths.WAD // lender factor
            );
        }
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Calculates new pool interest rate.
     */
    function _calculateInterestRate(
        PoolState memory poolState_,
        uint256 interestRate_,
        uint256 debtEma_,
        uint256 depositEma_,
        uint256 debtColEma_,
        uint256 lupt0DebtEma_
    ) internal pure returns (uint256 newInterestRate_)  {
        // meaningful actual utilization
        int256 mau;
        // meaningful actual utilization * 1.02
        int256 mau102;

        if (poolState_.debt != 0) {
            // calculate meaningful actual utilization for interest rate update
            mau    = int256(_utilization(debtEma_, depositEma_));
            mau102 = mau * PERCENT_102 / 1e18;
        }

        // calculate target utilization
        int256 tu = (lupt0DebtEma_ != 0) ? 
            int256(Maths.wdiv(debtColEma_, lupt0DebtEma_)) : int(Maths.WAD);

        if (!poolState_.isNewInterestAccrued) poolState_.rate = interestRate_;

        newInterestRate_ = poolState_.rate;

        // raise rates if 4*(tu-1.02*mau) < (tu+1.02*mau-1)^2-1
        if (4 * (tu - mau102) < ((tu + mau102 - 1e18) ** 2) / 1e18 - 1e18) {
            newInterestRate_ = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
        // decrease rates if 4*(tu-mau) > 1-(tu+mau-1)^2
        } else if (4 * (tu - mau) > 1e18 - ((tu + mau - 1e18) ** 2) / 1e18) {
            newInterestRate_ = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
        }

        // bound rates between 10 bps and 50000%
        newInterestRate_ = Maths.min(500 * 1e18, Maths.max(0.001 * 1e18, newInterestRate_));
    }

    /**
     *  @notice Calculates pool meaningful actual utilization.
     *  @param  debtEma_     EMA of pool debt.
     *  @param  depositEma_  EMA of meaningful pool deposit.
     *  @return utilization_ Pool meaningful actual utilization value.
     */
    function _utilization(
        uint256 debtEma_,
        uint256 depositEma_
    ) internal pure returns (uint256 utilization_) {
        if (depositEma_ != 0) utilization_ = Maths.wdiv(debtEma_, depositEma_);
    }

    /**
     *  @notice Calculates lender interest margin.
     *  @param  mau_ Meaningful actual utilization.
     *  @return The lender interest margin value.
     */
    function _lenderInterestMargin(
        uint256 mau_
    ) internal pure returns (uint256) {
        // Net Interest Margin = ((1 - MAU1)^(1/3) * 0.15)
        // Where MAU1 is MAU capped at 100% (min(MAU,1))
        // Lender Interest Margin = 1 - Net Interest Margin

        // PRBMath library forbids raising a number < 1e18 to a power.  Using the product and quotient rules of 
        // exponents, rewrite the equation with a coefficient s which provides sufficient precision:
        // Net Interest Margin = ((s - MAU1) * s)^(1/3) / s^(1/3) * 0.15

        uint256 base = 1_000_000 * 1e18 - Maths.wmul(Maths.min(mau_, 1e18), 1_000_000 * 1e18);
        // If unutilized deposit is infinitessimal, lenders get 100% of interest.
        if (base < 1e18) {
            return 1e18;
        } else {
            // cubic root of the percentage of meaningful unutilized deposit
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            // finish calculating Net Interest Margin, and then convert to Lender Interest Margin
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

    function _meaningfulDeposit(
        DepositsState storage deposits_,
        uint256 t0Debt_,
        uint256 inflator_,
        uint256 t0Debt2ToCollateral_
    ) internal view returns (uint256 meaningfulDeposit_) {
        uint256 dwatp = _dwatp(t0Debt_, inflator_, t0Debt2ToCollateral_);
        if (dwatp == 0) {
            meaningfulDeposit_ = Deposits.treeSum(deposits_);
        } else {
            if      (dwatp >= MAX_PRICE) meaningfulDeposit_ = 0;
            else if (dwatp >= MIN_PRICE) meaningfulDeposit_ = Deposits.prefixSum(deposits_, _indexOf(dwatp));
            else                         meaningfulDeposit_ = Deposits.treeSum(deposits_);
        }
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

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
     *  @param  inflator_      Current pool inflator.
     *  @param  inflatorUpdate Timestamp when inflator was updated.
     *  @param  interestRate_  The interest rate of the pool.
     *  @return The pending value of pool inflator.
     */
    function pendingInflator(
        uint256 inflator_,
        uint256 inflatorUpdate,
        uint256 interestRate_
    ) external view returns (uint256) {
        return Maths.wmul(
            inflator_,
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
     *  @notice Calculates pool meaningful actual utilization.
     *  @dev Wrapper of the internal function.
     */
    function utilization(
        EmaState storage emaParams_
    ) external view returns (uint256 utilization_) {
        return _utilization(emaParams_.debtEma, emaParams_.depositEma);
    }
}
