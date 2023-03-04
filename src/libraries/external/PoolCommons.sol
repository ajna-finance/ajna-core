// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;
import "forge-std/console.sol";

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { InterestState, PoolState, DepositsState } from '../../interfaces/pool/commons/IPoolState.sol';

import { _indexOf, _ptp, MAX_FENWICK_INDEX, MIN_PRICE, MAX_PRICE } from '../helpers/PoolHelper.sol';

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
        // if a previous transaction in this block already updated the EMA, only update cached values
        if (interestParams_.emaUpdate != block.timestamp) {
            // We do not need to calculate these during initialization, 
            // but the conditional to check each time would be more expensive thereafter.
            int256 elapsed = int256(Maths.wdiv(block.timestamp - interestParams_.emaUpdate, 1 hours));
            int256 weight = PRBMathSD59x18.exp(PRBMathSD59x18.mul(NEG_H_MAU_HOURS, elapsed));
            // console.log("  time %s elapsed %s mins", block.timestamp, (block.timestamp - interestParams_.emaUpdate)/60);

            // update the t0 debt EMA, used for MAU
            uint256 debt       = interestParams_.debt;
            uint256 curDebtEma = interestParams_.debtEma;
            if (curDebtEma == 0) {
                // initialize to actual value for the first calculation
                curDebtEma = Maths.wmul(poolState_.inflator, poolState_.t0Debt);
            } else {
                curDebtEma = uint256(
                    PRBMathSD59x18.mul(weight, int256(curDebtEma)) +
                    PRBMathSD59x18.mul((1e18 - weight), int256(debt))
                );
            }
            // console.log("debt %s, curDebtEma %s", poolState_.debt, curDebtEma);

            // update the meaningful deposit EMA, used for MAU
            uint256 meaningfulDeposit = interestParams_.meaningfulDeposit;
            uint256 curDepositEma     = interestParams_.depositEma;
            if (curDepositEma == 0) {
                // initialize to actual value for the first calculation
                curDepositEma = _meaningfulDeposit(deposits_, poolState_.debt, poolState_.collateral);    
            } else {
                curDepositEma = uint256(
                    PRBMathSD59x18.mul(weight, int256(curDepositEma)) +
                    PRBMathSD59x18.mul((1e18 - weight), int256(meaningfulDeposit))
                );
            }
            // console.log("meaningfulDeposit %s, curDepositEma %s", meaningfulDeposit, curDepositEma);

            // TODO: calculations below should be based of previously cached values in pool, 
            // not current values from poolState_.  Must add to InterestState and update at bottom of method.

            // update the debt squared to collateral EMA, used for TU
            uint256 debtCol       = Maths.wmul(poolState_.inflator, interestParams_.t0UtilizationWeight);
            uint256 curDebtColEma = interestParams_.debtColEma;
            if (curDebtColEma == 0) {
                curDebtColEma = debtCol;
            } else {
                curDebtColEma = uint256(
                    PRBMathSD59x18.mul(weight, int256(curDebtColEma)) +
                    PRBMathSD59x18.mul((1e18 - weight), int256(debtCol))
                );
            }
            // console.log("debtCol %s, curDebtColEma %s", debtCol, curDebtColEma);

            // update the EMA of LUP * t0 debt
            uint256 lupt0Debt       = Maths.wmul(lup_, poolState_.t0Debt);
            uint256 curlupt0DebtEma = interestParams_.lupt0DebtEma;
            if (curlupt0DebtEma == 0) {
                curlupt0DebtEma = lupt0Debt;
            } else {
                curlupt0DebtEma = uint256(
                    PRBMathSD59x18.mul(weight, int256(curlupt0DebtEma)) +
                    PRBMathSD59x18.mul((1e18 - weight), int256(lupt0Debt))
                );
            }
            console.log("lupt0Debt %s, curlupt0DebtEma %s", lupt0Debt, curlupt0DebtEma);

            interestParams_.debtEma      = curDebtEma;
            interestParams_.depositEma   = curDepositEma;
            interestParams_.debtColEma   = curDebtColEma;
            interestParams_.lupt0DebtEma = curlupt0DebtEma;

            interestParams_.emaUpdate    = block.timestamp;
        }

        interestParams_.debt              = Maths.wmul(poolState_.inflator, poolState_.t0Debt);
        interestParams_.meaningfulDeposit = _meaningfulDeposit(deposits_, poolState_.debt, poolState_.collateral);
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
        uint256 meaningfulDeposit = _meaningfulDeposit(deposits_, poolState_.debt, poolState_.collateral);

        if (depositAboveHtp != 0) {
            newInterest_ = Maths.wmul(
                // TODO: should be calculated against EMAs, but we don't have InterestState here
                _lenderInterestMargin(_utilization(poolState_.debt, meaningfulDeposit)),
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
        return _utilization(interestParams_.debtEma, interestParams_.depositEma );
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

    // TODO: update this to use the t0UtilizationWeight accumulator
    function _meaningfulDeposit(
        DepositsState storage deposits,
        uint256 poolDebt_,
        uint256 collateral_
    ) internal view returns (uint256 meaningfulDeposit_) {
        uint256 ptp = _ptp(poolDebt_, collateral_);
        if (ptp != 0) {
            if      (ptp >= MAX_PRICE) meaningfulDeposit_ = 0;
            else if (ptp >= MIN_PRICE) meaningfulDeposit_ = Deposits.prefixSum(deposits, _indexOf(ptp));
            else                       meaningfulDeposit_ = Deposits.treeSum(deposits);
        }
    }
}
