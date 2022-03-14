// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {PRBMathSD59x18} from "@prb-math/contracts/PRBMathSD59x18.sol";

// https://stackoverflow.com/questions/42738640/division-in-ethereum-solidity
// https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e

// Problem of floating points:
// - https://ethereum.stackexchange.com/questions/79903/exponential-function-with-fractional-numbers

// Library list:
// - https://ethereum.stackexchange.com/questions/83785/what-fixed-or-float-point-math-libraries-are-available-in-solidity/83786#83786
// - Decimal Math: https://github.com/HQ20/contracts/tree/master/contracts/math
// - Logs + other fx: https://github.com/barakman/solidity-math-utils
// - Fixed Point (Open Source License): https://github.com/paulrberg/prb-math/tree/v1.0.3

library BucketMath {
    int256 public constant WAD = 10**18;

    using PRBMathSD59x18 for int256;

    // constant price indices defining the min and max of the potential price range
    int256 public constant MAX_PRICE_INDEX = 6926;
    int256 public constant MIN_PRICE_INDEX = -3232;

    int256 public constant MIN_PRICE = 100000000000;
    int256 public constant MAX_PRICE = 1004948313 * WAD;

    // step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
    int256 public constant FLOAT_STEP_INT = 1005000000000000000;

    function abs(int256 x) private pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }

    /// @notice Calculates the index for a given bucket price
    /// @dev Throws if price exceeds maximum constant
    /// @dev Price expected to be inputted as a 18 decimal WAD
    function priceToIndex(int256 price) public pure returns (int256 index) {
        require(price <= MAX_PRICE && price >= MIN_PRICE, "Exceeds P Bounds");

        // V1
        // index = (price - MIN_PRICE) / FLOAT_STEP;

        // V2
        // index = (log(FLOAT_STEP) * price) /  MAX_PRICE;

        // V3
        index = PRBMathSD59x18.div(
            PRBMathSD59x18.log2(price),
            PRBMathSD59x18.log2(FLOAT_STEP_INT)
        );
        if (index < 0) {
            return PRBMathSD59x18.toInt(index) - 1;
        }

        return PRBMathSD59x18.toInt(index);
    }

    /// @notice Calculates the bucket price for a given index
    /// @dev Throws if index exceeds maximum constant
    /// @dev Uses fixed-point math to get around lack of floating point numbers in EVM
    /// @dev Price expected to be inputted as a 18 decimal WAD
    function indexToPrice(int256 index) public pure returns (int256 price) {
        require(
            index <= MAX_PRICE_INDEX && index >= MIN_PRICE_INDEX,
            "Exceeds I Bounds"
        );

        // V1
        // price = MIN_PRICE + (FLOAT_STEP * index);

        // V2
        // price = MAX_PRICE * (FLOAT_STEP ** (abs(int256(index - MAX_PRICE_INDEX))));

        // V3
        // x^y = 2^(y*log_2(x))
        price = PRBMathSD59x18.exp2(
            PRBMathSD59x18.mul(
                PRBMathSD59x18.fromInt(index),
                PRBMathSD59x18.log2(FLOAT_STEP_INT)
            )
        );
    }

    /// @notice Determine if a given price is within the constant range
    /// @dev Price needs to be cast to int, since indices can be negative
    /// @return A boolean indicating if the given price is valid
    function isValidPrice(uint256 _price) public pure returns (bool) {
        // cast uint256 price to int256 to enable comparison to int constants
        int256 int_price = int256(_price);

        return (int_price >= MIN_PRICE && int_price < MAX_PRICE);
    }

    /// @notice Determine if a given index is within the constant range
    /// @return A boolean indicating if the given index is valid
    function isValidIndex(int256 _index) public pure returns (bool) {
        return (_index >= MIN_PRICE_INDEX && _index <= MAX_PRICE_INDEX);
    }

    // TODO: finish implementing
    // function getNextValidPrice(uint256 _price) public pure returns (uint256) {
    //     // dummy implementation, should calculate using maths library
    //     uint256 next = _price + 1;
    //     if (next > MAX_PRICE) {
    //         return 0;
    //     }
    //     return next;
    // }
}
