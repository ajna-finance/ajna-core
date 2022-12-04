// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import './Maths.sol';
import './Deposits.sol';
import './Buckets.sol';
import './Loans.sol';
import '../base/Pool.sol';

library PoolLogic {
    /**
        @dev constant price indices defining the min and max of the potential price range
     */
    int256 internal constant MAX_PRICE_INDEX = 4_156;
    int256 internal constant MIN_PRICE_INDEX = -3_232;

    uint256 internal constant MIN_PRICE = 99_836_282_890;
    uint256 internal constant MAX_PRICE = 1_004_968_987.606512354182109771 * 10**18;

    uint256 internal constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 internal constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    /**
        @dev step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
     */
    int256 internal constant FLOAT_STEP_INT = 1.005 * 10**18;

    uint256 internal constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;

    // minimum fee that can be applied for early withdraw penalty
    uint256 internal constant MIN_FEE = 0.0005 * 10**18;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 10**18;

    uint256 internal constant LAMBDA_EMA_7D      = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR = 1e18 - LAMBDA_EMA_7D;
    int256  internal constant PERCENT_102        = 1.02 * 10**18;

    event UpdateInterestRate(
        uint256 oldRate,
        uint256 newRate
    );

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
        uint256 htpIndex = (htp != 0) ? _priceToIndex(htp) : 7_388; // if HTP is 0 then accrue interest at max index (min price)

        // Scale the fenwick tree to update amount of debt owed to lenders
        uint256 depositAboveHtp = Deposits.prefixSum(deposits_, htpIndex);

        if (depositAboveHtp != 0) {
            uint256 newInterest = Maths.wmul(
                _lenderInterestMargin(deposits_, debt_, collateral_),
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
     *  @notice Calculates the price for a given deposit index
     */
    function indexToPrice(
        uint256 index_
    ) external pure returns (uint256) {
        return _indexToPrice(index_);
    }

    /**
     *  @notice Calculates the deposit index for a given price
     */
    function priceToIndex(
        uint256 price_
    ) external pure returns (uint256) {
        return _priceToIndex(price_);
    }

    function pendingInterestFactor(
        uint256 interestRate_,
        uint256 elapsed_
    ) external pure returns (uint256) {
        return PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
    }

    function pendingInflator(
        uint256 inflatorSnapshot_,
        uint256 lastInflatorSnapshotUpdate_,
        uint256 interestRate_
    ) external view returns (uint256) {
        return Maths.wmul(
            inflatorSnapshot_,
            PRBMathUD60x18.exp((interestRate_ * (block.timestamp - lastInflatorSnapshotUpdate_)) / 365 days)
        );
    }

    function lenderInterestMargin(
        uint256 mau_
    ) external pure returns (uint256) {
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

    function utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) external view returns (uint256 utilization_) {
        return _utilization(deposits, debt_, collateral_);
    }

    function _utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256 utilization_) {
        if (collateral_ != 0) {
            uint256 ptp = Maths.wdiv(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits, _priceToIndex(ptp));

                if (depositAbove != 0) utilization_ = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }
    }

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
    function _indexToPrice(
        uint256 index_
    ) internal pure returns (uint256) {
        int256 bucketIndex = (index_ != 8191) ? MAX_PRICE_INDEX - int256(index_) : MIN_PRICE_INDEX;
        require(bucketIndex >= MIN_PRICE_INDEX && bucketIndex <= MAX_PRICE_INDEX, "BM:ITP:OOB");

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
    function _priceToIndex(
        uint256 price_
    ) internal pure returns (uint256) {
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

    function _lenderInterestMargin(
        Deposits.Data storage deposits_,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256) {
        // utilization
        uint256 mau;
        if (collateral_ != 0) {
            uint256 ptp = getPtp(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits_, _priceToIndex(ptp));
                if (depositAbove != 0) mau = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }

        // TODO: Consider pre-calculating and storing a conversion table in a library or shared contract.
        // cubic root of the percentage of meaningful unutilized deposit
        uint256 base = 1000000 * 1e18 - Maths.wmul(Maths.min(mau, 1e18), 1000000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

}