// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import './DSTestPlus.sol';

import 'src/libraries/internal/Buckets.sol';

contract BucketInstance is DSTestPlus {
    using Buckets for Bucket;

    Bucket public bucket;

    function addCollateral(
        address lender_,
        uint256 deposit_,
        uint256 collateralAmountToAdd_,
        uint256 bucketPrice_
    ) public returns (uint256 addedLP_) {
        return bucket.addCollateral(lender_, deposit_, collateralAmountToAdd_, bucketPrice_);
    }

    function addLenderLP(
        uint256 bankruptcyTime_,
        address lender_,
        uint256 lpAmount_
    ) public {
        bucket.addLenderLP(bankruptcyTime_, lender_, lpAmount_);
    }

    function getBucket() external view returns (uint256 lps, uint256 collateral, uint256 bankruptcyTime) {
        lps = bucket.lps;
        collateral = bucket.collateral;
        bankruptcyTime = bucket.bankruptcyTime; 
    }

    function getLender(
        address _lender
    ) external view returns (uint256 lps, uint256 depositTime) {
        Lender memory lender = bucket.lenders[_lender];
        lps = lender.lps;
        depositTime = lender.depositTime;
    }

}
