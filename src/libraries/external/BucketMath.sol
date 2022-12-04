// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import '../Maths.sol';

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

}
