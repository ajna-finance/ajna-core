// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import {
    AddQuoteParams,
    MoveQuoteParams,
    RemoveQuoteParams
}                     from '../../interfaces/pool/commons/IPoolInternals.sol';
import {
    Bucket,
    DepositsState,
    Lender,
    PoolState
}                     from '../../interfaces/pool/commons/IPoolState.sol';

import { _feeRate, _priceAt, _ptp, MAX_FENWICK_INDEX } from '../helpers/PoolHelper.sol';

import { Deposits } from '../internal/Deposits.sol';
import { Buckets }  from '../internal/Buckets.sol';
import { Maths }    from '../internal/Maths.sol';


/**
    @title  LenderActions library
    @notice External library containing logic for pool actors:
            - Lenders: add, remove and move quote tokens; transfer LPs
            - Traders: add, remove and move quote tokens; add and remove collateral
 */
library LenderActions {

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct MoveQuoteLocalVars {
        uint256 fromBucketPrice;            // [WAD] Price of the bucket to move amount from.
        uint256 fromBucketCollateral;       // [WAD] Total amount of collateral in from bucket.
        uint256 fromBucketLPs;              // [WAD] Total amount of LPs in from bucket.
        uint256 fromBucketLenderLPs;        // [WAD] Amount of LPs owned by lender in from bucket.
        uint256 fromBucketDepositTime;      // Time of lender deposit in the bucket to move amount from.
        uint256 fromBucketRemainingLPs;     // Amount of LPs remaining in from bucket after move.
        uint256 fromBucketRemainingDeposit; // Amount of scaled deposit remaining in from bucket after move.
        uint256 toBucketPrice;              // [WAD] Price of the bucket to move amount to.
        uint256 toBucketBankruptcyTime;     // Time the bucket to move amount to was marked as insolvent.
        uint256 toBucketDepositTime;        // Time of lender deposit in the bucket to move amount to.
        uint256 toBucketUnscaledDeposit;    // Amount of unscaled deposit in to bucket.
        uint256 toBucketDeposit;            // Amount of scaled deposit in to bucket.
        uint256 toBucketScale;              // Scale deposit of to bucket.
        uint256 ptp;                        // [WAD] Pool Threshold Price.
        uint256 htp;                        // [WAD] Highest Threshold Price.
    }
    struct RemoveDepositParams {
        uint256 depositConstraint; // [WAD] Constraint on deposit in quote token.
        uint256 lpConstraint;      // [WAD] Constraint in LPB terms.
        uint256 bucketLPs;         // [WAD] Total LPB in the bucket.
        uint256 bucketCollateral;  // [WAD] Claimable collateral in the bucket.
        uint256 price;             // [WAD] Price of bucket.
        uint256 index;             // Bucket index.
        uint256 dustLimit;         // Minimum amount of deposit which may reside in a bucket.
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event AddQuoteToken(address indexed lender, uint256 indexed index, uint256 amount, uint256 lpAwarded, uint256 lup);
    event BucketBankruptcy(uint256 indexed index, uint256 lpForfeited);
    event MoveQuoteToken(address indexed lender, uint256 indexed from, uint256 indexed to, uint256 amount, uint256 lpRedeemedFrom, uint256 lpAwardedTo, uint256 lup);
    event RemoveQuoteToken(address indexed lender, uint256 indexed index, uint256 amount, uint256 lpRedeemed, uint256 lup);
    event TransferLPs(address owner, address newOwner, uint256[] indexes, uint256 lps);

    /**************/
    /*** Errors ***/
    /**************/

    // See `IPoolErrors` for descriptions
    error BucketBankruptcyBlock();
    error CannotMergeToHigherPrice();
    error DustAmountNotExceeded();
    error NoAllowance();
    error InvalidIndex();
    error InvalidAmount();
    error LUPBelowHTP();
    error NoClaim();
    error InsufficientLPs();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error MoveToSameIndex();
    error TransferorNotApproved();
    error TransferToSameOwner();

    /***************************/
    /***  External Functions ***/
    /***************************/

    /**
     *  @notice See `IERC20PoolLenderActions` and `IERC721PoolLenderActions` for descriptions
     *  @dev    write state:
     *              - Buckets.addCollateral:
     *                  - increment bucket.collateral and bucket.lps accumulator
     *                  - addLenderLPs:
     *                      - increment lender.lps accumulator and lender.depositTime state
     *  @dev    reverts on:
     *              - invalid bucket index InvalidIndex()
     */
    function addCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) external returns (uint256 bucketLPs_) {
        // revert if no amount to be added
        if (collateralAmountToAdd_ == 0) revert InvalidAmount();
        // revert if adding at invalid index
        if (index_ == 0 || index_ > MAX_FENWICK_INDEX) revert InvalidIndex();

        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);
        uint256 bucketPrice   = _priceAt(index_);

        bucketLPs_ = Buckets.addCollateral(
            buckets_[index_],
            msg.sender,
            bucketDeposit,
            collateralAmountToAdd_,
            bucketPrice
        );
    }

    /**
     *  @notice See `IPoolLenderActions` for descriptions
     *  @dev    write state:
     *              - Deposits.unscaledAdd (add new amount in Fenwick tree):
     *                  - update values array state 
     *              - increment bucket.lps accumulator
     *              - increment lender.lps accumulator and lender.depositTime state
     *  @dev    reverts on:
     *              - invalid bucket index InvalidIndex()
     *              - same block when bucket becomes insolvent BucketBankruptcyBlock()
     *  @dev    emit events:
     *              - AddQuoteToken
     */
    function addQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        AddQuoteParams calldata params_
    ) external returns (uint256 bucketLPs_, uint256 lup_) {
        // revert if no amount to be added
        if (params_.amount == 0) revert InvalidAmount();
        // revert if adding to an invalid index
        if (params_.index == 0 || params_.index > MAX_FENWICK_INDEX) revert InvalidIndex();

        Bucket storage bucket = buckets_[params_.index];

        uint256 bankruptcyTime = bucket.bankruptcyTime;

        // cannot deposit in the same block when bucket becomes insolvent
        if (bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        uint256 unscaledBucketDeposit = Deposits.unscaledValueAt(deposits_, params_.index);
        uint256 bucketScale           = Deposits.scale(deposits_, params_.index);
        uint256 bucketDeposit         = Maths.wmul(bucketScale, unscaledBucketDeposit);
        uint256 bucketPrice           = _priceAt(params_.index);

        bucketLPs_ = Buckets.quoteTokensToLPs(
            bucket.collateral,
            bucket.lps,
            bucketDeposit,
            params_.amount,
            bucketPrice
        );

        Deposits.unscaledAdd(deposits_, params_.index, Maths.wdiv(params_.amount, bucketScale));

        // update lender LPs
        Lender storage lender = bucket.lenders[msg.sender];

        if (bankruptcyTime >= lender.depositTime) lender.lps = bucketLPs_;
        else lender.lps += bucketLPs_;

        lender.depositTime = block.timestamp;

        // update bucket LPs
        bucket.lps += bucketLPs_;

        lup_ = _lup(deposits_, poolState_.debt);

        emit AddQuoteToken(msg.sender, params_.index, params_.amount, bucketLPs_, lup_);
    }

    /**
     *  @notice See `IPoolLenderActions` for descriptions
     *  @dev    write state:
     *              - _removeMaxDeposit:
     *                  - Deposits.unscaledRemove (remove amount in Fenwick tree, from index):
     *                  - update values array state
     *              - Deposits.unscaledAdd (add amount in Fenwick tree, to index):
     *                  - update values array state
     *              - decrement lender.lps accumulator for from bucket
     *              - increment lender.lps accumulator and lender.depositTime state for to bucket
     *              - decrement bucket.lps accumulator for from bucket
     *              - increment bucket.lps accumulator for to bucket
     *  @dev    reverts on:
     *              - same index MoveToSameIndex()
     *              - dust amount DustAmountNotExceeded()
     *              - invalid index InvalidIndex()
     *  @dev    emit events:
     *              - BucketBankruptcy
     *              - MoveQuoteToken
     */
    function moveQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        MoveQuoteParams calldata params_
    ) external returns (uint256 fromBucketRedeemedLPs_, uint256 toBucketLPs_, uint256 movedAmount_, uint256 lup_) {
        if (params_.maxAmountToMove == 0)
            revert InvalidAmount();
        if (params_.fromIndex == params_.toIndex)
            revert MoveToSameIndex();
        if (params_.maxAmountToMove != 0 && params_.maxAmountToMove < poolState_.quoteDustLimit)
            revert DustAmountNotExceeded();
        if (params_.toIndex == 0 || params_.toIndex > MAX_FENWICK_INDEX) 
            revert InvalidIndex();

        Bucket storage toBucket = buckets_[params_.toIndex];

        MoveQuoteLocalVars memory vars;
        vars.toBucketBankruptcyTime = toBucket.bankruptcyTime;

        // cannot move in the same block when target bucket becomes insolvent
        if (vars.toBucketBankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        Bucket storage fromBucket       = buckets_[params_.fromIndex];
        Lender storage fromBucketLender = fromBucket.lenders[msg.sender];

        vars.fromBucketPrice       = _priceAt(params_.fromIndex);
        vars.fromBucketCollateral  = fromBucket.collateral;
        vars.fromBucketLPs         = fromBucket.lps;
        vars.fromBucketDepositTime = fromBucketLender.depositTime;

        vars.toBucketPrice         = _priceAt(params_.toIndex);

        if (fromBucket.bankruptcyTime < vars.fromBucketDepositTime) vars.fromBucketLenderLPs = fromBucketLender.lps;

        (movedAmount_, fromBucketRedeemedLPs_, vars.fromBucketRemainingDeposit) = _removeMaxDeposit(
            deposits_,
            RemoveDepositParams({
                depositConstraint: params_.maxAmountToMove,
                lpConstraint:      vars.fromBucketLenderLPs,
                bucketLPs:         vars.fromBucketLPs,
                bucketCollateral:  vars.fromBucketCollateral,
                price:             vars.fromBucketPrice,
                index:             params_.fromIndex,
                dustLimit:         poolState_.quoteDustLimit
            })
        );

        vars.ptp = _ptp(poolState_.debt, poolState_.collateral);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        if (vars.fromBucketDepositTime != 0 && block.timestamp - vars.fromBucketDepositTime < 1 days) {
            if (vars.fromBucketPrice > vars.ptp && vars.toBucketPrice < vars.ptp) {
                movedAmount_ = Maths.wmul(movedAmount_, Maths.WAD - _feeRate(poolState_.rate));
            }
        }

        vars.toBucketUnscaledDeposit = Deposits.unscaledValueAt(deposits_, params_.toIndex);
        vars.toBucketScale           = Deposits.scale(deposits_, params_.toIndex);
        vars.toBucketDeposit         = Maths.wmul(vars.toBucketUnscaledDeposit, vars.toBucketScale);

        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            vars.toBucketDeposit,
            movedAmount_,
            vars.toBucketPrice
        );

        Deposits.unscaledAdd(deposits_, params_.toIndex, Maths.wdiv(movedAmount_, vars.toBucketScale));

        lup_     = _lup(deposits_, poolState_.debt);
        vars.htp = Maths.wmul(params_.thresholdPrice, poolState_.inflator);

        // check loan book's htp against new lup, revert if move drives LUP below HTP
        if (params_.fromIndex < params_.toIndex && vars.htp > lup_) revert LUPBelowHTP();

        // update lender and bucket LPs balance in from bucket
        vars.fromBucketRemainingLPs = vars.fromBucketLPs - fromBucketRedeemedLPs_;

        if (vars.fromBucketCollateral == 0 && vars.fromBucketRemainingDeposit == 0 && vars.fromBucketRemainingLPs != 0) {
            emit BucketBankruptcy(params_.fromIndex, vars.fromBucketRemainingLPs);
            fromBucket.lps            = 0;
            fromBucket.bankruptcyTime = block.timestamp;
        } else {
            // update lender and bucket LPs balance
            fromBucketLender.lps -= fromBucketRedeemedLPs_;

            fromBucket.lps = vars.fromBucketRemainingLPs;
        }

        // update lender and bucket LPs balance in target bucket
        Lender storage toBucketLender = toBucket.lenders[msg.sender];

        vars.toBucketDepositTime = toBucketLender.depositTime;
        if (vars.toBucketBankruptcyTime >= vars.toBucketDepositTime) {
            // bucket is bankrupt and deposit was done before bankruptcy time, reset lender lp amount
            toBucketLender.lps = toBucketLPs_;

            // set deposit time of the lender's to bucket as bucket's last bankruptcy timestamp + 1 so deposit won't get invalidated
            vars.toBucketDepositTime = vars.toBucketBankruptcyTime + 1;
        } else {
            toBucketLender.lps += toBucketLPs_;
        }

        // set deposit time to the greater of the lender's from bucket and the target bucket
        toBucketLender.depositTime = Maths.max(vars.fromBucketDepositTime, vars.toBucketDepositTime);

        // update bucket LPs balance
        toBucket.lps += toBucketLPs_;

        emit MoveQuoteToken(
            msg.sender,
            params_.fromIndex,
            params_.toIndex,
            movedAmount_,
            fromBucketRedeemedLPs_,
            toBucketLPs_,
            lup_
        );
    }

    /**
     *  @notice See `IPoolLenderActions` for descriptions
     *  @dev    write state:
     *          - _removeMaxDeposit:
     *              - Deposits.unscaledRemove (remove amount in Fenwick tree):
     *                  - update values array state
     *              - decrement lender.lps accumulator
     *              - decrement bucket.lps accumulator
     *  @dev    reverts on:
     *              - no LPs NoClaim()
     *              - LUP lower than HTP LUPBelowHTP()
     *  @dev    emit events:
     *              - RemoveQuoteToken
     *              - BucketBankruptcy
     */
    function removeQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        RemoveQuoteParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {
        // revert if no amount to be removed
        if (params_.maxAmount == 0) revert InvalidAmount();

        Bucket storage bucket = buckets_[params_.index];
        Lender storage lender = bucket.lenders[msg.sender];

        uint256 depositTime = lender.depositTime;

        RemoveDepositParams memory removeParams;

        if (bucket.bankruptcyTime < depositTime) removeParams.lpConstraint = lender.lps;

        if (removeParams.lpConstraint == 0) revert NoClaim(); // revert if no LP to claim

        removeParams.depositConstraint = params_.maxAmount;
        removeParams.price             = _priceAt(params_.index);
        removeParams.bucketLPs         = bucket.lps;
        removeParams.bucketCollateral  = bucket.collateral;
        removeParams.index             = params_.index;
        removeParams.dustLimit         = poolState_.quoteDustLimit;

        uint256 scaledRemaining;
        (removedAmount_, redeemedLPs_, scaledRemaining) = _removeMaxDeposit(
            deposits_,
            removeParams
        );

        // apply early withdrawal penalty if quote token is removed from above the PTP
        if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
            if (removeParams.price > _ptp(poolState_.debt, poolState_.collateral)) {
                removedAmount_ = Maths.wmul(removedAmount_, Maths.WAD - _feeRate(poolState_.rate));
            }
        }

        lup_ = _lup(deposits_, poolState_.debt);

        uint256 htp = Maths.wmul(params_.thresholdPrice, poolState_.inflator);

        // check loan book's htp against new lup
        if (htp > lup_) revert LUPBelowHTP();

        uint256 lpsRemaining = removeParams.bucketLPs - redeemedLPs_;

        if (removeParams.bucketCollateral == 0 && scaledRemaining == 0 && lpsRemaining != 0) {
            emit BucketBankruptcy(params_.index, lpsRemaining);
            bucket.lps            = 0;
            bucket.bankruptcyTime = block.timestamp;
        } else {
            // update lender and bucket LPs balances
            lender.lps -= redeemedLPs_;

            bucket.lps = lpsRemaining;
        }

        emit RemoveQuoteToken(msg.sender, params_.index, removedAmount_, redeemedLPs_, lup_);
    }

    /**
     *  @notice See `IPoolLenderActions` for descriptions
     *  @dev    write state:
     *              - decrement lender.lps accumulator
     *              - decrement bucket.collateral and bucket.lps accumulator
     *  @dev    reverts on:
     *              - not enough collateral InsufficientCollateral()
     *              - insufficient LPs InsufficientLPs()
     *  @dev    emit events:
     *              - BucketBankruptcy
     */
    function removeCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256 amount_,
        uint256 index_
    ) external returns (uint256 lpAmount_) {
        // revert if no amount to be removed
        if (amount_ == 0) revert InvalidAmount();

        Bucket storage bucket = buckets_[index_];

        uint256 bucketCollateral = bucket.collateral;

        if (amount_ > bucketCollateral) revert InsufficientCollateral();

        uint256 bucketPrice   = _priceAt(index_);
        uint256 bucketLPs     = bucket.lps;
        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);

        lpAmount_ = Buckets.collateralToLPs(
            bucketCollateral,
            bucketLPs,
            bucketDeposit,
            amount_,
            bucketPrice
        );

        Lender storage lender = bucket.lenders[msg.sender];

        uint256 lenderLpBalance;
        if (bucket.bankruptcyTime < lender.depositTime) lenderLpBalance = lender.lps;
        if (lenderLpBalance == 0 || lpAmount_ > lenderLpBalance) revert InsufficientLPs();

        // update bucket LPs and collateral balance
        bucketLPs -= lpAmount_;

        // If clearing out the bucket collateral, ensure it's zeroed out
        if (bucketLPs == 0 && bucketDeposit == 0) {
            amount_ = bucketCollateral;
        }

        bucketCollateral  -= Maths.min(bucketCollateral, amount_);
        bucket.collateral = bucketCollateral;

        if (bucketCollateral == 0 && bucketDeposit == 0 && bucketLPs != 0) {
            emit BucketBankruptcy(index_, bucketLPs);
            bucket.lps            = 0;
            bucket.bankruptcyTime = block.timestamp;
        } else {
            // update lender LPs balance
            lender.lps -= lpAmount_;

            bucket.lps = bucketLPs;
        }
    }

    /**
     *  @notice Removes max collateral amount from a given bucket index.
     *  @dev    write state:
     *              - _removeMaxCollateral:
     *                  - decrement lender.lps accumulator
     *                  - decrement bucket.collateral and bucket.lps accumulator
     *  @dev    reverts on:
     *              - not enough collateral InsufficientCollateral()
     *              - no claim NoClaim()
     *  @return Amount of collateral that was removed.
     *  @return Amount of LPs redeemed for removed collateral amount.
     */
    function removeMaxCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256 maxAmount_,
        uint256 index_
    ) external returns (uint256, uint256) {
        // revert if no amount to remove
        if (maxAmount_ == 0) revert InvalidAmount();

        return _removeMaxCollateral(
            buckets_,
            deposits_,
            maxAmount_,
            index_
        );
    }

    /**
     *  @notice See `IERC721PoolLenderActions` for descriptions
     *  @dev    write state:
     *              - Buckets.addCollateral:
     *                  - increment bucket.collateral and bucket.lps accumulator
     *                  - addLenderLPs:
     *                      - increment lender.lps accumulator and lender.depositTime state
     *  @dev    reverts on:
     *              - invalid merge index CannotMergeToHigherPrice()
     */
    function mergeOrRemoveCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256[] calldata removalIndexes_,
        uint256 collateralAmount_,
        uint256 toIndex_
    ) external returns (uint256 collateralToMerge_, uint256 bucketLPs_) {
        uint256 i;
        uint256 fromIndex;
        uint256 collateralRemoved;
        uint256 noOfBuckets = removalIndexes_.length;
        uint256 collateralRemaining = collateralAmount_;

        // Loop over buckets, exit if collateralAmount is reached or max noOfBuckets is reached
        while (collateralToMerge_ < collateralAmount_ && i < noOfBuckets) {
            fromIndex = removalIndexes_[i];

            if (fromIndex > toIndex_) revert CannotMergeToHigherPrice();

            (collateralRemoved, ) = _removeMaxCollateral(
                buckets_,
                deposits_,
                collateralRemaining,
                fromIndex
            );

            collateralToMerge_ += collateralRemoved;

            collateralRemaining = collateralRemaining - collateralRemoved;

            unchecked { ++i; }
        }

        if (collateralToMerge_ != collateralAmount_) {
            // Merge totalled collateral to specified bucket, toIndex_
            uint256 toBucketDeposit = Deposits.valueAt(deposits_, toIndex_);
            uint256 toBucketPrice   = _priceAt(toIndex_);

            bucketLPs_ = Buckets.addCollateral(
                buckets_[toIndex_],
                msg.sender,
                toBucketDeposit,
                collateralToMerge_,
                toBucketPrice
            );
        }
    }

    /**
     *  @notice See `IPoolLenderActions` for descriptions
     *  @dev write state:
     *          - delete allowance mapping
     *          - increment new lender.lps accumulator and lender.depositTime state
     *          - delete old lender from bucket -> lender mapping
     *  @dev reverts on:
     *          - invalid index InvalidIndex()
     *          - no allowance NoAllowance()
     *  @dev emit events:
     *          - TransferLPs
     */
    function transferLPs(
        mapping(uint256 => Bucket) storage buckets_,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage allowances_,
        mapping(address => mapping(address => bool)) storage approvedTransferors_,
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external {
        // revert if msg.sender is not the new owner and is not approved as a transferor by the new owner
        if (newOwner_ != msg.sender && !approvedTransferors_[newOwner_][msg.sender]) revert TransferorNotApproved();

        // revert if new owner address is the same as old owner address
        if (owner_ == newOwner_) revert TransferToSameOwner();

        uint256 indexesLength = indexes_.length;

        uint256 tokensTransferred;

        for (uint256 i = 0; i < indexesLength; ) {
            uint256 index = indexes_[i];
            if (index > MAX_FENWICK_INDEX) revert InvalidIndex();

            uint256 transferAmount = allowances_[owner_][newOwner_][index];

            Bucket storage bucket = buckets_[index];
            Lender storage lender = bucket.lenders[owner_];

            uint256 lenderDepositTime = lender.depositTime;

            uint256 lenderLpBalance;

            if (bucket.bankruptcyTime < lenderDepositTime) lenderLpBalance = lender.lps;

            if (transferAmount == 0 || transferAmount != lenderLpBalance) revert NoAllowance();

            delete allowances_[owner_][newOwner_][index]; // delete allowance

            // move lps to the new owner address
            Lender storage newLender = bucket.lenders[newOwner_];

            newLender.lps += transferAmount;

            newLender.depositTime = Maths.max(lenderDepositTime, newLender.depositTime);

            // reset owner lp balance for this index
            delete bucket.lenders[owner_];

            tokensTransferred += transferAmount;

            unchecked { ++i; }
        }

        emit TransferLPs(owner_, newOwner_, indexes_, tokensTransferred);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Removes max collateral amount from a given bucket index.
     *  @dev    write state:
     *              - decrement lender.lps accumulator
     *              - decrement bucket.collateral and bucket.lps accumulator
     *  @dev    reverts on:
     *              - not enough collateral InsufficientCollateral()
     *              - no claim NoClaim()
     *  @dev    emit events:
     *              - BucketBankruptcy
     *  @return collateralAmount_ Amount of collateral that was removed.
     *  @return lpAmount_         Amount of LPs redeemed for removed collateral amount.
     */
    function _removeMaxCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256 maxAmount_,
        uint256 index_
    ) internal returns (uint256 collateralAmount_, uint256 lpAmount_) {
        Bucket storage bucket = buckets_[index_];

        uint256 bucketCollateral = bucket.collateral;
        if (bucketCollateral == 0) revert InsufficientCollateral(); // revert if there's no collateral in bucket

        Lender storage lender = bucket.lenders[msg.sender];

        uint256 lenderLpBalance;

        if (bucket.bankruptcyTime < lender.depositTime) lenderLpBalance = lender.lps;
        if (lenderLpBalance == 0) revert NoClaim();                  // revert if no LP to redeem

        uint256 bucketPrice   = _priceAt(index_);
        uint256 bucketLPs     = bucket.lps;
        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);

        // limit amount by what is available in the bucket
        collateralAmount_ = Maths.min(maxAmount_, bucketCollateral);

        // determine how much LP would be required to remove the requested amount
        uint256 requiredLPs = Buckets.collateralToLPs(
            bucketCollateral,
            bucketLPs,
            bucketDeposit,
            collateralAmount_,
            bucketPrice
        );

        // limit withdrawal by the lender's LPB
        if (requiredLPs <= lenderLpBalance) {
            // withdraw collateralAmount_ as is
            lpAmount_ = requiredLPs;
        } else {
            lpAmount_         = lenderLpBalance;
            collateralAmount_ = Maths.wdiv(Maths.wmul(lenderLpBalance, collateralAmount_), requiredLPs);

            if (collateralAmount_ == 0) revert InsufficientLPs();
        }

        // update bucket LPs and collateral balance
        bucketLPs -= Maths.min(bucketLPs, lpAmount_);

        // If clearing out the bucket collateral, ensure it's zeroed out
        if (bucketLPs == 0 && bucketDeposit == 0) {
            collateralAmount_ = bucketCollateral;
        }

        bucketCollateral  -= Maths.min(bucketCollateral, collateralAmount_);
        bucket.collateral = bucketCollateral;

        if (bucketCollateral == 0 && bucketDeposit == 0 && bucketLPs != 0) {
            emit BucketBankruptcy(index_, bucketLPs);
            bucket.lps            = 0;
            bucket.bankruptcyTime = block.timestamp;
        } else {
            // update lender LPs balance
            lender.lps -= lpAmount_;

            bucket.lps = bucketLPs;
        }
    }


    /**
     *  @notice Removes the amount of quote tokens calculated for the given amount of LPs.
     *  @dev    write state:
     *          - Deposits.unscaledRemove (remove amount in Fenwick tree, from index):
     *              - update values array state
     *  @return removedAmount_   Amount of scaled deposit removed.
     *  @return redeemedLPs_     Amount of bucket LPs corresponding for calculated scaled deposit amount.
     *  @return scaledRemaining_ Amount of scaled deposit remaining.
     */
    function _removeMaxDeposit(
        DepositsState storage deposits_,
        RemoveDepositParams memory params_
    ) internal returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 scaledRemaining_) {

        uint256 unscaledDepositAvailable = Deposits.unscaledValueAt(deposits_, params_.index);
        if (unscaledDepositAvailable == 0) revert InsufficientLiquidity(); // revert if there's no liquidity available to remove

        uint256 depositScale = Deposits.scale(deposits_, params_.index);

        uint256 scaledDepositAvailable = Maths.wmul(unscaledDepositAvailable, depositScale);

        uint256 exchangeRate = Buckets.getExchangeRate(
            params_.bucketCollateral,
            params_.bucketLPs,
            scaledDepositAvailable,
            params_.price
        );

        // Below is pseudocode explaining the logic behind finding the constrained amount of deposit and LPB
        // scaledRemovedAmount is constrained by the scaled maxAmount(in QT), the scaledDeposit constraint, and
        // the lender LPB exchange rate in scaled deposit-to-LPB for the bucket:
        // scaledRemovedAmount = min ( maxAmount_, scaledDeposit, lenderLPsBalance*exchangeRate)
        // redeemedLPs_ = min ( maxAmount_/scaledExchangeRate, scaledDeposit/exchangeRate, lenderLPsBalance)

        uint256 scaledLpConstraint = Maths.wmul(params_.lpConstraint, exchangeRate);
        if (
            params_.depositConstraint < scaledDepositAvailable &&
            params_.depositConstraint < scaledLpConstraint
        ) {
            // depositConstraint is binding constraint
            removedAmount_ = params_.depositConstraint;
            redeemedLPs_   = Maths.wdiv(removedAmount_, exchangeRate);
        } else if (scaledDepositAvailable < scaledLpConstraint) {
            // scaledDeposit is binding constraint
            removedAmount_ = scaledDepositAvailable;
            redeemedLPs_   = Maths.wdiv(removedAmount_, exchangeRate);
        } else {
            // redeeming all LPs
            redeemedLPs_   = params_.lpConstraint;
            removedAmount_ = Maths.wmul(redeemedLPs_, exchangeRate);
        }

        // If clearing out the bucket deposit, ensure it's zeroed out
        if (redeemedLPs_ == params_.bucketLPs) {
            removedAmount_ = scaledDepositAvailable;
        }

        scaledRemaining_ = scaledDepositAvailable - removedAmount_;

        uint256 unscaledRemovedAmount = Maths.min(unscaledDepositAvailable, Maths.wdiv(removedAmount_, depositScale));
        Deposits.unscaledRemove(deposits_, params_.index, unscaledRemovedAmount); // update FenwickTree
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function _lup(
        DepositsState storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return _priceAt(Deposits.findIndexOfSum(deposits_, debt_));
    }
}
