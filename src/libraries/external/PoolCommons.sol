// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;
import "forge-std/console.sol";

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { InterestState, PoolState, DepositsState } from '../../interfaces/pool/commons/IPoolState.sol';

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

    /**************************/
    /*** External Functions ***/
    /**************************/

    /**
     *  @notice Calculates EMAs, caches values required for calculating interest rate, and saves new values in storage.
     *  @dev    Called after each interaction with the pool.
     **/
    function updateUtilizationEmas(
        InterestState storage interestParams_,  // TODO: many writes; should we pass as memory and let caller update?
        DepositsState storage deposits_,
        PoolState memory poolState_,
        uint256 lup_
    ) external {
        uint256 inflator = poolState_.inflator;
        uint256 t0Debt   = poolState_.t0Debt;

        // if a previous transaction in this block already updated the EMA, only update cached values
        if (interestParams_.emaUpdate != block.timestamp) {
            // We do not need to calculate these during initialization, 
            // but the conditional to check each time would be more expensive thereafter.
            int256 elapsed   = int256(Maths.wdiv(block.timestamp - interestParams_.emaUpdate, 1 hours));
            int256 weightMau = PRBMathSD59x18.exp(PRBMathSD59x18.mul(NEG_H_MAU_HOURS, elapsed));
            int256 weightTu  = PRBMathSD59x18.exp(PRBMathSD59x18.mul(NEG_H_TU_HOURS,  elapsed));
            // console.log("  time %s elapsed %s mins", block.timestamp, (block.timestamp - interestParams_.emaUpdate)/60);

            // update the t0 debt EMA, used for MAU
            uint256 curDebtEma = interestParams_.debtEma;
            if (curDebtEma == 0) {
                // initialize to actual value for the first calculation
                curDebtEma = Maths.wmul(inflator, t0Debt);
            } else {
                curDebtEma = uint256(
                    PRBMathSD59x18.mul(weightMau, int256(curDebtEma)) +
                    PRBMathSD59x18.mul((1e18 - weightMau), int256(interestParams_.debt))
                );
            }
            // console.log("debt %s, curDebtEma %s", interestParams_.debt, curDebtEma);

            // update the meaningful deposit EMA, used for MAU
            uint256 curDepositEma = interestParams_.depositEma;
            if (curDepositEma == 0) {
                // initialize to actual value for the first calculation
                curDepositEma = _meaningfulDeposit(deposits_, t0Debt, inflator, interestParams_.t0UtilizationWeight);    
            } else {
                curDepositEma = uint256(
                    PRBMathSD59x18.mul(weightMau, int256(curDepositEma)) +
                    PRBMathSD59x18.mul((1e18 - weightMau), int256(interestParams_.meaningfulDeposit))
                );
            }
            // console.log("meaningfulDeposit %s, curDepositEma %s", interestParams_.meaningfulDeposit, curDepositEma);

            // update the debt squared to collateral EMA, used for TU
            uint256 curDebtColEma = interestParams_.debtColEma;
            if (curDebtColEma == 0) {
                curDebtColEma =  Maths.wmul(inflator, interestParams_.t0UtilizationWeight);
            } else {
                curDebtColEma = uint256(
                    PRBMathSD59x18.mul(weightTu, int256(curDebtColEma)) +
                    PRBMathSD59x18.mul((1e18 - weightTu), int256(interestParams_.debtCol))
                );
            }
            // console.log("debtCol %s, curDebtColEma %s", interestParams_.debtCol, curDebtColEma);

            // update the EMA of LUP * t0 debt
            uint256 curlupt0DebtEma = interestParams_.lupt0DebtEma;
            if (curlupt0DebtEma == 0) {
                curlupt0DebtEma = Maths.wmul(lup_, t0Debt);
            } else {
                curlupt0DebtEma = uint256(
                    PRBMathSD59x18.mul(weightTu, int256(curlupt0DebtEma)) +
                    PRBMathSD59x18.mul((1e18 - weightTu), int256(interestParams_.lupt0Debt))
                );
            }
            // console.log("lupt0Debt %s, curlupt0DebtEma %s", interestParams_.lupt0Debt, curlupt0DebtEma);

            interestParams_.debtEma      = curDebtEma;
            interestParams_.depositEma   = curDepositEma;
            interestParams_.debtColEma   = curDebtColEma;
            interestParams_.lupt0DebtEma = curlupt0DebtEma;

            interestParams_.emaUpdate    = block.timestamp;
        }

        interestParams_.debt              = Maths.wmul(inflator, t0Debt);
        interestParams_.meaningfulDeposit = _meaningfulDeposit(deposits_, t0Debt, inflator, interestParams_.t0UtilizationWeight);
        interestParams_.debtCol           = Maths.wmul(inflator, interestParams_.t0UtilizationWeight);
        interestParams_.lupt0Debt         = Maths.wmul(lup_, t0Debt);
    }

    /**
     *  @notice Calculates new pool interest rate params (EMAs and interest rate value) and saves new values in storage.
     *  @dev    Never called more than once every 12 hours.
     *  @dev    write state:
     *              - interest rate accumulator and interestRateUpdate state
     *  @dev    emit events:
     *              - UpdateInterestRate
     */
    function updateInterestRate(
        InterestState storage interestParams_,
        PoolState memory poolState_
    ) external {
        // meaningful actual utilization
        int256 mau;
        // meaningful actual utilization * 1.02
        int256 mau102;

        if (poolState_.debt != 0) {
            // current inflator * t0UtilizationDebtWeight / current lup
            // NEW: current inflator * t0UtilizationDebtWeight
            // uint256 lupCol = 
            //     Maths.wmul(poolState_.inflator, t0PoolUtilizationDebtWeight_);

            // calculate meaningful actual utilization for interest rate update
            mau    = int256(_utilization(interestParams_.debtEma, interestParams_.depositEma));
            mau102 = mau * PERCENT_102 / 1e18;
        }

        // calculate target utilization
        int256 tu = (interestParams_.lupt0DebtEma != 0) ? 
            int256(Maths.wdiv(interestParams_.debtColEma, interestParams_.lupt0DebtEma)) : int(Maths.WAD);

        // console.log("debtColEma %s, lupt0DebtEma %s", uint256(interestParams_.debtColEma), uint256(interestParams_.lupt0DebtEma));
        // console.log("mau %s, tu %s", uint256(mau), uint256(tu));

        if (!poolState_.isNewInterestAccrued) poolState_.rate = interestParams_.interestRate;

        uint256 newInterestRate = poolState_.rate;

        // raise rates if 4*(tu-1.02*mau) < (tu+1.02*mau-1)^2-1
        if (4 * (tu - mau102) < ((tu + mau102 - 1e18) ** 2) / 1e18 - 1e18) {
            newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
        // decrease rates if 4*(tu-mau) > 1-(tu+mau-1)^2
        } else if (4 * (tu - mau) > 1e18 - ((tu + mau - 1e18) ** 2) / 1e18) {
            newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
        }

        // bound rates between 10 bps and 50000%
        newInterestRate = Maths.min(500 * 1e18, Maths.max(0.001 * 1e18, newInterestRate));

        if (poolState_.rate != newInterestRate) {
            interestParams_.interestRate       = uint208(newInterestRate);
            interestParams_.interestRateUpdate = uint48(block.timestamp);

            emit UpdateInterestRate(poolState_.rate, newInterestRate);
        }
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
        DepositsState storage deposits_,
        InterestState storage interestState_,
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
                _lenderInterestMargin(_utilization(interestState_.debtEma, interestState_.depositEma)),
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
    /*** View Functions ***/
    /**************************/

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
     *  @notice Calculates pool meaningful actual utilization.
     *  @dev Wrapper of the internal function.
     */
    function utilization(
        InterestState storage interestParams_
    ) external view returns (uint256 utilization_) {
        return _utilization(interestParams_.debtEma, interestParams_.depositEma);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

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
        uint256 base = 1_000_000 * 1e18 - Maths.wmul(Maths.min(mau_, 1e18), 1_000_000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            // cubic root of the percentage of meaningful unutilized deposit
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

    function _meaningfulDeposit(
        DepositsState storage deposits_,
        uint256 t0Debt_,
        uint256 inflator_,
        uint256 t0UtilizationWeight_
    ) internal view returns (uint256 meaningfulDeposit_) {
        uint256 dwatp = _dwatp(t0Debt_, inflator_, t0UtilizationWeight_);
        if (dwatp == 0) {
            meaningfulDeposit_ = Deposits.treeSum(deposits_);
        } else {
            if      (dwatp >= MAX_PRICE) meaningfulDeposit_ = 0;
            else if (dwatp >= MIN_PRICE) meaningfulDeposit_ = Deposits.prefixSum(deposits_, _indexOf(dwatp));
            else                         meaningfulDeposit_ = Deposits.treeSum(deposits_);
        }
    }
}
