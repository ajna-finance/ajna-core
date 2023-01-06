// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { AddQuoteParams, MoveQuoteParams, RemoveQuoteParams, PoolState } from '../../base/interfaces/IPool.sol';

import '../Deposits.sol';
import '../Buckets.sol';
import '../../base/PoolHelper.sol';

/**
    @notice External library containing logic for common lender actions.
 */
library LenderActions {

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct MoveQuoteLocalVars {
        uint256 amountToMove;
        uint256 fromBucketPrice;
        uint256 fromBucketLPs;
        uint256 fromBucketDepositTime;
        uint256 toBucketPrice;
        uint256 toBucketBankruptcyTime;
        uint256 ptp;
        uint256 htp;
    }
    struct RemoveDepositParams {
        uint256 depositConstraint;  // Constraint on deposit in quote token.
        uint256 lpConstraint;       // Constraint in LPB terms.
        uint256 bucketLPs;          // Total LPB in the bucket.
        uint256 bucketCollateral;   // Claimable collateral in the bucket.
        uint256 price;              // Price of bucket.
        uint256 index;              // Bucket index.
        uint256 dustLimit;          // Minimum amount of deposit which may reside in a bucket.
    }

    /**************/
    /*** Events ***/
    /**************/

    // See `IPoolEvents` for descriptions
    event AddQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lpAwarded, uint256 lup);
    event MoveQuoteToken(address indexed lender, uint256 indexed from, uint256 indexed to, uint256 amount, uint256 lpRedeemedFrom, uint256 lpAwardedTo, uint256 lup);
    event RemoveQuoteToken(address indexed lender, uint256 indexed price, uint256 amount, uint256 lpRedeemed, uint256 lup);
    event TransferLPTokens(address owner, address newOwner, uint256[] indexes, uint256 lpTokens);

    /**************/
    /*** Errors ***/
    /**************/

    // See `IPoolErrors` for descriptions
    error BucketBankruptcyBlock();
    error CannotMergeToHigherPrice();
    error DustAmountNotExceeded();
    error NoAllowance();
    error InvalidIndex();
    error LUPBelowHTP();
    error NoClaim();
    error InsufficientLPs();
    error InsufficientLiquidity();
    error InsufficientCollateral();
    error MoveToSamePrice();

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
     *              - same index MoveToSamePrice()
     *              - dust amount DustAmountNotExceeded()
     *              - invalid index InvalidIndex()
     *  @dev    emit events:
     *              - MoveQuoteToken
     */
    function moveQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        MoveQuoteParams calldata params_
    ) external returns (uint256 fromBucketRedeemedLPs_, uint256 toBucketLPs_, uint256 lup_) {
        if (params_.fromIndex == params_.toIndex)
            revert MoveToSamePrice();
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
        vars.toBucketPrice         = _priceAt(params_.toIndex);
        vars.fromBucketDepositTime = fromBucketLender.depositTime;

        if (fromBucket.bankruptcyTime < vars.fromBucketDepositTime) vars.fromBucketLPs = fromBucketLender.lps;

        (vars.amountToMove, fromBucketRedeemedLPs_) = _removeMaxDeposit(
            deposits_,
            RemoveDepositParams({
                depositConstraint: params_.maxAmountToMove,
                lpConstraint:      vars.fromBucketLPs,
                bucketLPs:         fromBucket.lps,
                bucketCollateral:  fromBucket.collateral,
                price:             vars.fromBucketPrice,
                index:             params_.fromIndex,
                dustLimit:         poolState_.quoteDustLimit
            })
        );

        vars.ptp = _ptp(poolState_.debt, poolState_.collateral);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        if (vars.fromBucketDepositTime != 0 && block.timestamp - vars.fromBucketDepositTime < 1 days) {
            if (vars.fromBucketPrice > vars.ptp && vars.toBucketPrice < vars.ptp) {
                vars.amountToMove = Maths.wmul(vars.amountToMove, Maths.WAD - _feeRate(poolState_.rate));
            }
        }

        uint256 unscaledToBucketDeposit = Deposits.unscaledValueAt(deposits_, params_.toIndex);
        uint256 toBucketScale           = Deposits.scale(deposits_, params_.toIndex);
        uint256 toBucketDeposit         = Maths.wmul(toBucketScale, unscaledToBucketDeposit);
        vars.toBucketPrice              = _priceAt(params_.toIndex);
        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            toBucketDeposit,
            vars.amountToMove,
            vars.toBucketPrice
        );

        Deposits.unscaledAdd(deposits_, params_.toIndex, Maths.wdiv(vars.amountToMove, toBucketScale));

        lup_     = _lup(deposits_, poolState_.debt);
        vars.htp = Maths.wmul(params_.thresholdPrice, poolState_.inflator);

        // check loan book's htp against new lup, revert if move drives LUP below HTP
        if (params_.fromIndex < params_.toIndex) if(vars.htp > lup_) revert LUPBelowHTP();

        // update lender LPs balance in from bucket
        fromBucketLender.lps -= fromBucketRedeemedLPs_;

        // update lender LPs balance and deposit time in target bucket
        Lender storage toBucketLender = toBucket.lenders[msg.sender];

        if (vars.toBucketBankruptcyTime >= toBucketLender.depositTime) toBucketLender.lps = toBucketLPs_;
        else toBucketLender.lps += toBucketLPs_;

        // set deposit time to the greater of the lender's from bucket and the target bucket's last bankruptcy timestamp + 1 so deposit won't get invalidated
        toBucketLender.depositTime = Maths.max(vars.fromBucketDepositTime, vars.toBucketBankruptcyTime + 1);

        // update buckets LPs balance
        fromBucket.lps -= fromBucketRedeemedLPs_;
        toBucket.lps   += toBucketLPs_;

        emit MoveQuoteToken(
            msg.sender,
            params_.fromIndex,
            params_.toIndex,
            vars.amountToMove,
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
     */
    function removeQuoteToken(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        PoolState calldata poolState_,
        RemoveQuoteParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {
        Bucket storage bucket = buckets_[params_.index];
        Lender storage lender = bucket.lenders[msg.sender];

        uint256 depositTime = lender.depositTime;

        uint256 lenderLPs;

        if (bucket.bankruptcyTime < lender.depositTime) lenderLPs = lender.lps;
        if (lenderLPs == 0) revert NoClaim();      // revert if no LP to claim

        uint256 price = _priceAt(params_.index);

        (removedAmount_, redeemedLPs_) = _removeMaxDeposit(
            deposits_,
            RemoveDepositParams({
                depositConstraint: params_.maxAmount,
                lpConstraint:      lenderLPs,
                bucketCollateral:  bucket.collateral,
                bucketLPs:         bucket.lps,
                price:             price,
                index:             params_.index,
                dustLimit:         poolState_.quoteDustLimit
            })
        );

        // apply early withdrawal penalty if quote token is removed from above the PTP
        if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
            if (price > _ptp(poolState_.debt, poolState_.collateral)) {
                removedAmount_ = Maths.wmul(removedAmount_, Maths.WAD - _feeRate(poolState_.rate));
            }
        }

        lup_ = _lup(deposits_, poolState_.debt);

        uint256 htp = Maths.wmul(params_.thresholdPrice, poolState_.inflator);

        // check loan book's htp against new lup
        if (htp > lup_) revert LUPBelowHTP();

        // update lender and bucket LPs balances
        lender.lps -= redeemedLPs_;
        bucket.lps -= redeemedLPs_;

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
     */
    function removeCollateral(
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        uint256 amount_,
        uint256 index_
    ) external returns (uint256 lpAmount_) {
        Bucket storage bucket = buckets_[index_];

        uint256 bucketCollateral = bucket.collateral;

        if (amount_ > bucketCollateral) revert InsufficientCollateral();

        uint256 bucketPrice = _priceAt(index_);
        uint256 bucketLPs   = bucket.lps;

        lpAmount_ = Buckets.collateralToLPs(
            bucketCollateral,
            bucketLPs,
            Deposits.valueAt(deposits_, index_),
            amount_,
            bucketPrice
        );

        Lender storage lender = bucket.lenders[msg.sender];

        uint256 lenderLpBalance;
        if (bucket.bankruptcyTime < lender.depositTime) lenderLpBalance = lender.lps;
        if (lenderLpBalance == 0 || lpAmount_ > lenderLpBalance) revert InsufficientLPs();

        // update lender LPs balance
        lender.lps -= lpAmount_;

        // update bucket LPs and collateral balance
        bucket.lps        -= Maths.min(bucketLPs, lpAmount_);
        bucket.collateral -= Maths.min(bucketCollateral, amount_);
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
     *          - TransferLPTokens
     */
    function transferLPTokens(
        mapping(uint256 => Bucket) storage buckets_,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage allowances_,
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external {
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

            // move lp tokens to the new owner address
            Lender storage newLender = bucket.lenders[newOwner_];

            newLender.lps += transferAmount;

            newLender.depositTime = Maths.max(lenderDepositTime, newLender.depositTime);

            // reset owner lp balance for this index
            delete bucket.lenders[owner_];

            tokensTransferred += transferAmount;

            unchecked { ++i; }
        }

        emit TransferLPTokens(owner_, newOwner_, indexes_, tokensTransferred);
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
        uint256 collateralValue     = Maths.wmul(bucketPrice, bucketCollateral);
        uint256 lpsForAllCollateral = Maths.rmul(bucketLPs, Maths.wwdivr(collateralValue, collateralValue + bucketDeposit));
        uint256 requiredLPs         = Maths.rmul(lpsForAllCollateral, Maths.wwdivr(collateralAmount_, bucketCollateral));

        // limit withdrawal by the lender's LPB
        if (requiredLPs <= lenderLpBalance) {
            // withdraw collateralAmount_ as is
            lpAmount_ = requiredLPs;
        } else {
            lpAmount_         = lenderLpBalance;
            collateralAmount_ = Maths.wmul(Maths.rrdivw(lenderLpBalance,lpsForAllCollateral), bucketCollateral);
        }

        // update lender LPs balance
        lender.lps -= lpAmount_;

        // update bucket LPs and collateral balance
        bucket.lps        -= Maths.min(bucketLPs, lpAmount_);
        bucket.collateral -= Maths.min(bucketCollateral, collateralAmount_);
    }


    /**
     *  @notice Removes the amount of quote tokens calculated for the given amount of LPs.
     *  @dev    write state:
     *          - Deposits.unscaledRemove (remove amount in Fenwick tree, from index):
     *              - update values array state
     *  @return removedAmount_     Amount of scaled deposit removed.
     *  @return redeemedLPs_       Amount of bucket LPs corresponding for calculated unscaled deposit amount.
     */
    function _removeMaxDeposit(
        DepositsState storage deposits_,
        RemoveDepositParams memory params_
    ) internal returns (uint256 removedAmount_, uint256 redeemedLPs_) {

        uint256 unscaledDepositAvailable = Deposits.unscaledValueAt(deposits_, params_.index);
        if (unscaledDepositAvailable == 0) revert InsufficientLiquidity(); // revert if there's no liquidity available to remove

        uint256 depositScale = Deposits.scale(deposits_, params_.index);

        uint256 unscaledExchangeRate = Buckets.getUnscaledExchangeRate(
            params_.bucketCollateral,
            params_.bucketLPs,
            unscaledDepositAvailable,
            depositScale,
            params_.price
        );

        // Below is pseudocode explaining the logic behind finding the constrained amount of deposit and LPB
        // unscaledRemovedAmount is constrained by the de-scaled maxAmount(in QT), the unscaledDeposit constraint, and
        // the lender LPB exchange rate in unscaled deposit-to-LPB for the bucket:
        // unscaledRemovedAmount = min ( maxAmount_/scale, unscaledDeposit, lenderLPsBalance*unscaledExchangeRate)
        // redeemedLPs_ = min ( maxAmount_/(unscaledExchangeRate*scale), unscaledDeposit/unscaledExchangeRate, lenderLPsBalance)

        uint256 unscaledRemovedAmount;
        uint256 unscaledLpConstraint = Maths.rmul(params_.lpConstraint, unscaledExchangeRate);
        if (
            params_.depositConstraint < Maths.wmul(unscaledDepositAvailable, depositScale) &&
            Maths.wwdivr(params_.depositConstraint, depositScale) < unscaledLpConstraint
        ) {
            // depositConstraint is binding constraint
            unscaledRemovedAmount = Maths.wdiv(params_.depositConstraint, depositScale);
            redeemedLPs_          = Maths.wrdivr(unscaledRemovedAmount, unscaledExchangeRate);
        }
        else if (Maths.wadToRay(unscaledDepositAvailable) < unscaledLpConstraint) {
            // unscaledDeposit is binding constraint
            unscaledRemovedAmount = unscaledDepositAvailable;
            redeemedLPs_          = Maths.wrdivr(unscaledRemovedAmount, unscaledExchangeRate);
        }
        else {
            // redeeming all LPs
            redeemedLPs_          = params_.lpConstraint;
            unscaledRemovedAmount = Maths.rayToWad(Maths.rmul(redeemedLPs_, unscaledExchangeRate));
        }

        // If clearing out the bucket deposit, ensure it's zeroed out
        if (redeemedLPs_ == params_.bucketLPs) {
            unscaledRemovedAmount = unscaledDepositAvailable;
        }

        // calculate the scaled amount removed from deposits
        removedAmount_ = Maths.wmul(depositScale, unscaledRemovedAmount);        
        // calculate scale amount remaining
        uint256 remaining = Maths.wmul(depositScale, unscaledDepositAvailable - unscaledRemovedAmount);

        // abandon dust amounts upon last withdrawal
        if (remaining < params_.dustLimit && redeemedLPs_ == params_.bucketLPs) {
            unscaledRemovedAmount = unscaledDepositAvailable;
        }

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
