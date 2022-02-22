// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

// import "prb-math/contracts/PRBMathSD59x18.sol";

// https://stackoverflow.com/questions/42738640/division-in-ethereum-solidity
// https://medium.com/coinmonks/math-in-solidity-part-5-exponent-and-logarithm-9aef8515136e


// Library list:
// - Decimal Math: https://github.com/HQ20/contracts/tree/master/contracts/math
// - Logs + other fx: https://github.com/barakman/solidity-math-utils
// - Fixed Point (Open Source License): https://github.com/paulrberg/prb-math/tree/v1.0.3

library Bucket {

    // TODO: Check need for higher decimal precision
    uint256 public constant WAD = 10**18;

    // TODO: import fixed-point math library for increased precision and efficiency
    // using PRBMathSD59x18 for int256;

    // constant price indices defining the min and max of the potential price range
    uint256 internal constant MIN_PRICE_INDEX = 0;
    uint256 internal constant MAX_PRICE_INDEX = 6926;

    uint256 internal constant MIN_PRICE = uint256(1) * (WAD / 1000000);
    // TODO: rounded down from .21 remainer -> switch to fixed-point math 
    uint256 internal constant MAX_PRICE = 1004948313 * WAD;

    // step amounts in basis points. This is a constant across pools at .005, achieved by dividing by 10,000
    uint256 public constant FLOAT_STEP = uint256(1005) * (WAD / 1000);

    // info stored in each utilized price bucket
    // TODO: add LP tokens at per bucket level?
    struct Bucket {
        uint256 price; // current bucket price
        uint256 next; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
        uint256 debt; // accumulated bucket debt
    }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    // @notice Calculates the price for a given bucket index
    // TODO: convert index to int24 for reduced storage costs
    function priceToIndex(uint256 price) public pure returns (uint256 index) {
        require(price <= MAX_PRICE && price > MIN_PRICE, 'Exceeds P Bounds');

        // V1
        // index = (price - MIN_PRICE) / FLOAT_STEP;

        // V2
        // index = log(FLOAT_STEP) * price;
        index = (log(abs(FLOAT_STEP - MAX_PRICE_INDEX)) * price) /  MAX_PRICE;

    }

    // @notice Calculates the bucket index for a given price
    // @dev Throws if index exceeds maximum constant
    // @dev Uses fixed-point math to get around lack of floating point numbers in EVM
    // TODO: convert index to int24 for reduced storage costs
    function indexToPrice(uint256 index) public pure returns (uint256 price) {
        require(index <= MAX_PRICE_INDEX && index > MIN_PRICE_INDEX, 'Exceeds I Bounds');

        // V1
        // price = MIN_PRICE + (FLOAT_STEP * index);

        // V2
        price = MAX_PRICE * (FLOAT_STEP ** (abs(index - MAX_PRICE_INDEX)));
    }

    function isValidPrice(uint256 _price) public pure returns (bool) {
        if (_price < MIN_PRICE || _price > MAX_PRICE) {
            return false;
        }
        uint256 index = (_price - MIN_PRICE) / FLOAT_STEP;
        return (index >= 0 && index < MAX_PRICE_INDEX);
    }

    // TODO: convert to modifier?
    function isValidIndex(uint256 _index) public pure returns (bool) {
        return (_index >= 0 && _index < MAX_PRICE_INDEX);
    }


    // clear a given price buckets struct
    function clear() internal {}

    function roundToNearestBucket() public view returns (uint256 index) {

    }

}
