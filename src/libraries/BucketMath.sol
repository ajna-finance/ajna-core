// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import './Maths.sol';
import './Deposits.sol';

/**
    @dev https://stackoverflow.com/questions/42738640/division-in-ethereum-solidity
         https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e

         Problem of floating points:
          - https://ethereum.stackexchange.com/questions/79903/exponential-function-with-fractional-numbers

         Library list:
         - https://ethereum.stackexchange.com/questions/83785/what-fixed-or-float-point-math-libraries-are-available-in-solidity/83786#83786
         - Decimal Math: https://github.com/HQ20/contracts/tree/master/contracts/math
         - Logs + other fx: https://github.com/barakman/solidity-math-utils
         - Fixed Point (Open Source License): https://github.com/paulrberg/prb-math/tree/v1.0.3
 */
library BucketMath {

    /**
        @dev constant price indices defining the min and max of the potential price range
     */
    int256 public constant MAX_PRICE_INDEX = 4_156;
    int256 public constant MIN_PRICE_INDEX = -3_232;

    uint256 public constant MIN_PRICE = 99_836_282_890;
    uint256 public constant MAX_PRICE = 1_004_968_987.606512354182109771 * 10**18;

    uint256 public constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 public constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    /**
        @dev step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
     */
    int256 public constant FLOAT_STEP_INT = 1.005 * 10**18;

    uint256 internal constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;

    // minimum fee that can be applied for early withdraw penalty
    uint256 internal constant MIN_FEE = 0.0005 * 10**18;

    /**
     *  @notice Calculates the index for a given bucket price
     *  @dev    Throws if price exceeds maximum constant
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    V1: index = (price - MIN_PRICE) / FLOAT_STEP
     *          V2: index = (log(FLOAT_STEP) * price) /  MAX_PRICE
     *          V3 (final): index =  log_2(price) / log_2(FLOAT_STEP)
     */
    function priceToIndex(uint256 price_) public pure returns (int256) {
        require(price_ >= MIN_PRICE && price_ <= MAX_PRICE, "BM:PTI:OOB");

        int256 index = PRBMathSD59x18.div(
            PRBMathSD59x18.log2(int256(price_)),
            PRBMathSD59x18.log2(FLOAT_STEP_INT)
        );

        int256 ceilIndex = PRBMathSD59x18.ceil(index);
        if (index < 0 && ceilIndex - index > 0.5 * 1e18) {
            return PRBMathSD59x18.toInt(ceilIndex) - 1;
        }
        return PRBMathSD59x18.toInt(ceilIndex);
    }

    /**
     *  @notice Calculates the bucket price for a given index
     *  @dev    Throws if index exceeds maximum constant
     *  @dev    Uses fixed-point math to get around lack of floating point numbers in EVM
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    V1: price = MIN_PRICE + (FLOAT_STEP * index)
     *          V2: price = MAX_PRICE * (FLOAT_STEP ** (abs(int256(index - MAX_PRICE_INDEX))));
     *          V3 (final): x^y = 2^(y*log_2(x))
     */
    function indexToPrice(int256 index_) public pure returns (uint256) {
        require(index_ >= MIN_PRICE_INDEX && index_ <= MAX_PRICE_INDEX, "BM:ITP:OOB");

        return uint256(
            PRBMathSD59x18.exp2(
                PRBMathSD59x18.mul(
                    PRBMathSD59x18.fromInt(index_),
                    PRBMathSD59x18.log2(FLOAT_STEP_INT)
                )
            )
        );
    }

    /**
     *  @notice Determine if a given price is within the constant range
     *  @dev    Price needs to be cast to int, since indices can be negative
     *  @return isValid_ Boolean indicating if the given price is valid
     */
    function isValidPrice(uint256 price_) public pure returns (bool) {
        int256 index = priceToIndex(price_);
        uint256 price = indexToPrice(index);
        return price_ == price;
    }

    /**
     *  @notice Determine if a given index is within the constant range
     *  @return isValid_ Boolean indicating if the given index is valid
    */
    function isValidIndex(int256 index_) public pure returns (bool) {
        return index_ >= MIN_PRICE_INDEX && index_ <= MAX_PRICE_INDEX;
    }

    /**
     * @notice Determine closest bucket index for a given price
     * @return index_ closest bucket index
     * @return bucketPrice_ closest bucket price
    */
    function getClosestBucket(uint256 price_) external pure returns (int256 index_, uint256 bucketPrice_) {
        index_ = priceToIndex(price_);
        bucketPrice_ = indexToPrice(index_);
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

    function accrueInterest(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_,
        uint256 thresholdPrice_,
        uint256 inflator_,
        uint256 interestRate_,
        uint256 elapsed_
    ) external returns (uint256 newInflator_) {
        // Scale the borrower inflator to update amount of interest owed by borrowers
        uint256 pendingInterestFactor = PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
        newInflator_ = Maths.wmul(inflator_, pendingInterestFactor);

        uint256 htp = Maths.wmul(thresholdPrice_, newInflator_);
        uint256 htpIndex = (htp != 0) ? _priceToIndex(htp) : 7_388; // if HTP is 0 then accrue interest at max index (min price)

        // Scale the fenwick tree to update amount of debt owed to lenders
        uint256 depositAboveHtp = Deposits.prefixSum(deposits, htpIndex);

        if (depositAboveHtp != 0) {
            uint256 newInterest = Maths.wmul(
                _lenderInterestMargin(deposits, debt_, collateral_),
                Maths.wmul(pendingInterestFactor - Maths.WAD, debt_)
            );

            uint256 lenderFactor = Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD;
            Deposits.mult(deposits, htpIndex, lenderFactor);
        }
    }

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
            return uint256(7067 - PRBMathSD59x18.toInt(ceilIndex));
        }
        return uint256(4156 - PRBMathSD59x18.toInt(ceilIndex));
    }

    function _lenderInterestMargin(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256) {

        uint256 mau;
        if (collateral_ != 0) {
            uint256 ptp = Maths.wdiv(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits, _priceToIndex(ptp));

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

    function utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) external view returns (uint256 utilization_) {
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

    function minDebtAmount(
        uint256 debt_,
        uint256 loansCount_
    ) internal pure returns (uint256 minDebtAmount_) {
        if (loansCount_ != 0) {
            minDebtAmount_ = Maths.wdiv(Maths.wdiv(debt_, Maths.wad(loansCount_)), 10**19);
        }
    }

}
