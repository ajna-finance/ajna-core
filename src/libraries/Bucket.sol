// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

// https://github.com/paulrberg/prb-math/tree/v1.0.3
import "prb-math/contracts/PRBMathSD59x18.sol";

library Bucket {

    // import fixed-point math library for increased precision and efficiency
    using PRBMathSD59x18 for int256;

    // constant price indices defining the min and max of the potential price range
    int24 internal constant MIN_PRICE_INDEX = 0;
    int24 internal constant MAX_PRICE_INDEX = 6926;

    int24 internal constant MIN_PRICE = 1 / 1000000;
    // TODO: rounded down from .21 remainer -> switch to fixed-point math 
    int24 internal constant MAX_PRICE = 1004948313;

    // step amounts in basis points. This is a constant across pools at .05
    int24 public constant priceStep = 5 / 1000;

    // info stored in each utilized price bucket
    struct PriceBucket {
        mapping(address => uint256) lpTokenBalance;
        uint256 onDeposit;
        uint256 totalDebitors;
        mapping(uint256 => address) indexToDebitor;
        mapping(address => uint256) debitorToIndex;
        mapping(address => uint256) debt;
        uint256 debtAccumulator;
    }

    // @notice Calculates the price for a given bucket index
    // TODO: convert index to int24 for reduced storage costs
    function priceToIndex(uint256 price) public view returns (uint256 index) {
        require(price <= MAX_PRICE && price > MIN_PRICE, 'Exceeds P Bounds');

        index = (price - MIN_PRICE) / priceStep;
    }

    // @notice Calculates the bucket index for a given price
    // @dev Throws if index exceeds maximum constant
    // @dev Uses fixed-point math to get around lack of floating point numbers in EVM
    // TODO: convert index to int24 for reduced storage costs
    function indexToPrice(uint256 index) public view returns (uint256 price) {
        require(index <= MAX_PRICE_INDEX && index > MIN_PRICE_INDEX, 'Exceeds I Bounds');

        price = (1 + priceStep).pow(index);
    }


    // clear a given price buckets struct
    function clear() internal {

    }

    // check that a bucket is valid given the spacing and minimum and maximum prices
    function validateBucket() internal {

    }

    function roundToNearestBucket() public view returns (uint256 index) {

    }

}
