// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import '../utils/DSTestPlus.sol';
import '../utils/BucketInstance.sol';

contract BucketsTest is DSTestPlus {

    BucketInstance internal _bucket;

    address internal _lender;
    address internal _lender2;

    function setUp() public {
        _startTest();

        _lender  = makeAddr("lender");
        _lender2 = makeAddr("lender");

        _bucket = new BucketInstance();
    }
 
    /**
     *  @notice Tests adding collateral to a bucket.
     */
    function testBucketAddCollateral() external {
        
        // single lender adding collateral to a bucket
        // lender adds 100 collateral to bucket 23_659.397731825701207700
        uint256 addedLp = _bucket.addCollateral(_lender, 0, 100 * 1e18, _p236_59); 

        (uint256 lps, uint256 collateral, uint256 bankruptcyTime) = _bucket.getBucket();
        assertEq(23659.397731825701207700 * 1e18, lps);
        assertEq(23659.397731825701207700 * 1e18, addedLp);
        assertEq(100 * 1e18, collateral);
        assertEq(0, bankruptcyTime);

        (uint256 lenderLps, uint256 lenderDepositTime) = _bucket.getLender(_lender);
        assertEq(23659.397731825701207700 * 1e18, lenderLps);
        assertEq(block.timestamp, lenderDepositTime);

        // multiple lenders add collateral to the same bucket
        // lender2 adds 50 collateral to bucket 23_659.397731825701207700
        addedLp = _bucket.addCollateral(_lender2, 0, 50 * 1e18, _p236_59); 

        (lps, collateral, bankruptcyTime) = _bucket.getBucket();
        assertEq(35489.096597738551811550 * 1e18, lps);
        assertEq(11829.698865912850603850 * 1e18, addedLp);
        assertEq(150 * 1e18, collateral);
        assertEq(0, bankruptcyTime);

        (lenderLps, lenderDepositTime) = _bucket.getLender(_lender2);
        assertEq(35489.096597738551811550 * 1e18, lenderLps);
        assertEq(block.timestamp, lenderDepositTime);
    }

    /**
     *  @notice Tests adding lender LP to a bucket
     */
    function testBucketAddLenderLP() external {

        // single lender gets 15_000 lp in a bucket
        _bucket.addLenderLP(0, _lender, 15_000 * 1e18);

        // since add collateral was not touched, nothing is in the bucket
        (uint256 lps, uint256 collateral, uint256 bankruptcyTime) = _bucket.getBucket();
        assertEq(0, lps);
        assertEq(0, collateral);
        assertEq(0, bankruptcyTime);

        (uint256 lenderLps, uint256 lenderDepositTime) = _bucket.getLender(_lender);
        assertEq(15_000.0 * 1e18, lenderLps);
        assertEq(block.timestamp, lenderDepositTime);

        // single lender attempts to add 15_000 lp in a bankrupt bucket
        _bucket.addLenderLP(block.timestamp + 10, _lender, 15_000 * 1e18);

        (lenderLps, lenderDepositTime) = _bucket.getLender(_lender);
        assertEq(15_000.0 * 1e18, lenderLps); // lp amount doesn't change
        assertEq(block.timestamp, lenderDepositTime);
    }

    /**
     *  @notice Tests collateralToLP method
     */
    function testBucketCollateralToLP() external {

        // 0 deposit, 0 collateral in bucket, 0 collateral is added
        assertEq(
            Buckets.collateralToLP(
                0,
                0,
                0,
                0,
                _p236_59,
                Math.Rounding.Down
            ), 0
        );

        // 0 deposit, 0 collateral in bucket, 100 collateral is added 
        assertEq(
            Buckets.collateralToLP(
                0,
                0,
                0,
                100 * 1e18,
                _p236_59,
                Math.Rounding.Down
            ), 23_659.397731825701207700 * 1e18
        );
 
        // 0 deposit, 100 collateral in bucket, 100 collateral is added 
        assertEq(
            Buckets.collateralToLP(
                100 * 1e18,                      // exisiting collateral
                23659.397731825701207700 * 1e18, // exisiting lp
                0,                               // existing deposit
                50 * 1e18,                       // collateral to add
                _p236_59,
                Math.Rounding.Down
            ), 11829.698865912850603850 * 1e18
        );
    }

    /**
     *  @notice Tests quoteTokensToLP method
     */
    function testBucketQuoteTokensToLP() external {
        
        // 0 deposit, 0 collateral in bucket, 10 qt is added
        assertEq(
            Buckets.quoteTokensToLP(
                0,
                0,
                0,
                0,
                _p236_59,
                Math.Rounding.Down
            ), 0
        );

        // 0 deposit, 0 collateral in bucket, 10 qt is added
        assertEq(
            Buckets.quoteTokensToLP(
                0,
                0,
                0,
                10 * 1e18,
                _p236_59,
                Math.Rounding.Down
            ), 10 * 1e18
        );

        // 0 deposit, 1 collateral but no exisiting LP
        assertEq(
            Buckets.quoteTokensToLP(
                1 * 1e18,
                0,
                0,
                10 * 1e18,
                _p236_59,
                Math.Rounding.Down
            ), 10 * 1e18
        );

        // 0 deposit, 1 collateral but no exisiting LP
        assertEq(
            Buckets.quoteTokensToLP(
                1 * 1e18,
                0,
                0,
                10 * 1e18,
                _p236_59,
                Math.Rounding.Down
            ), 10 * 1e18
        );

        // 0 deposit, 100 collateral, healthy LP
        assertEq(
            Buckets.quoteTokensToLP(
                100 * 1e18,
                23_659.397731825701207700 * 1e18,
                0,
                10 * 1e18,
                _p236_59,
                Math.Rounding.Down
            ), 10 * 1e18
        );
    }
}