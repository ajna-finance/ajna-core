// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { BitMaps }       from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { BucketsManager } from "../base/BucketsManager.sol";

import "../libraries/Maths.sol";

abstract contract ERC721BucketsManager is BucketsManager {

    using EnumerableSet for EnumerableSet.UintSet;

    /**
     *  @notice Mapping of price to Set of NFT Token Ids that have been deposited into the bucket
     *  @dev price [WAD] -> collateralDeposited
     */
    mapping(uint256 => EnumerableSet.UintSet) internal _collateralDeposited;

    /**********************************/
    /*** Internal Utility Functions ***/
    /**********************************/

    function _claimNFTCollateralFromBucket(uint256 price_, uint256[] memory tokenIds_, uint256 lpBalance_) internal returns (uint256 lpRedemption_) {
        Bucket memory bucket = _buckets[price_];

        // check available collateral given removal of the NFT
        require(Maths.wad(tokenIds_.length) <= bucket.collateral, "B:CC:AMT_GT_COLLAT");

        // nft collateral is accounted for in WAD units
        lpRedemption_ = Maths.wrdivr(Maths.wmul(Maths.wad(tokenIds_.length), bucket.price), _exchangeRate(bucket));

        require(lpRedemption_ <= lpBalance_, "B:CC:INSUF_LP_BAL");

        // update bucket accounting
        bucket.collateral -= Maths.wad(tokenIds_.length);
        bucket.lpOutstanding -= lpRedemption_;

        // update collateralDeposited
        EnumerableSet.UintSet storage collateralDeposited = _collateralDeposited[price_];
        for (uint i; i < tokenIds_.length;) {
            require(collateralDeposited.contains(tokenIds_[i]), "B:CC:T_NOT_IN_B");
            collateralDeposited.remove(tokenIds_[i]);
            unchecked {
                ++i;
            }
        }

        // bucket management
        bool isEmpty = bucket.onDeposit == 0 && bucket.debt == 0;
        bool noClaim = bucket.lpOutstanding == 0 && bucket.collateral == 0;
        if (isEmpty && noClaim) {
            _deactivateBucket(bucket); // cleanup if bucket no longer used
        } else {
            _buckets[price_] = bucket; // save bucket to storage
        }
    }

    /**
     *  @notice Puchase a given amount of quote tokens for given NFT collateral tokenIds
     *  @param  price_      The price bucket at which the exchange will occur, WAD
     *  @param  amount_     The amount of quote tokens to receive, WAD
     *  @param  tokenIds_   Array of tokenIds used to purchase quote tokens
     *  @param  inflator_   The current pool inflator rate, RAY
     */
    function _purchaseBidFromBucketNFTCollateral(
        uint256 price_, uint256 amount_, uint256[] memory tokenIds_, uint256 inflator_
    ) internal {
        Bucket memory bucket    = _buckets[price_];
        bucket.debt             = _accumulateBucketInterest(bucket.debt, bucket.inflatorSnapshot, inflator_);
        bucket.inflatorSnapshot = inflator_;

        uint256 available = bucket.onDeposit + bucket.debt;

        require(amount_ <= available, "B:PB:INSUF_BUCKET_LIQ");

        // Exchange collateral for quote token on deposit
        uint256 purchaseFromDeposit = Maths.min(amount_, bucket.onDeposit);

        amount_          -= purchaseFromDeposit;
        // bucket accounting
        bucket.onDeposit -= purchaseFromDeposit;
        bucket.collateral += Maths.wad(tokenIds_.length);

        // update collateralDeposited
        EnumerableSet.UintSet storage collateralDeposited = _collateralDeposited[price_];
        for (uint i; i < tokenIds_.length;) {
            collateralDeposited.add(tokenIds_[i]);
            unchecked {
                ++i;
            }
        }

        // debt reallocation
        uint256 newLup = _reallocateDown(bucket, amount_, inflator_);

        _buckets[price_] = bucket;

        uint256 newHpb = (bucket.onDeposit == 0 && bucket.debt == 0) ? getHpb() : hpb;

        // HPB and LUP management
        if (lup != newLup) lup = newLup;
        if (hpb != newHpb) hpb = newHpb;

        pdAccumulator -= Maths.wmul(purchaseFromDeposit, bucket.price);
    }

    /*****************************/
    /*** Public View Functions ***/
    /*****************************/

    function getCollateralAtPrice(uint256 price_) public view returns (uint256[] memory) {
        return _collateralDeposited[price_].values();
    }

}
