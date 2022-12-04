// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import './Maths.sol';
import './Deposits.sol';
import './Buckets.sol';
import './PoolLogic.sol';

library LenderActions {

    /**
     *  @notice Owner of the LP tokens must have approved the new owner prior to transfer.
     */
    error NoAllowance();
    /**
     *  @notice When transferring LP tokens between indices, the new index must be a valid index.
     */
    error InvalidIndex();
    /**
     *  @notice Lender must have non-zero LPB when attemptign to remove quote token from the pool.
     */
    error NoClaim();
    /**
     *  @notice Bucket must have more quote available in the bucket than the lender is attempting to claim.
     */
    error InsufficientLiquidity();
    /**
     *  @notice from bucket and to bucket arguments to move are the same.
     */
    error MoveToSamePrice();

    struct MoveParams {
        uint256 maxAmountToMove;
        uint256 fromIndex;
        uint256 toIndex;
        uint256 poolDebt;
        uint256 ptp;
        uint256 feeRate;
    }

    struct RemoveParams {
        uint256 maxAmount;
        uint256 index;
        uint256 poolDebt;
        uint256 ptp;
        uint256 feeRate;
    }

    function addCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 collateralAmountToAdd_,
        uint256 index_,
        uint256 poolDebt_
    ) external returns (uint256 bucketLPs_, uint256 lup_) {
        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);
        uint256 bucketPrice   = PoolLogic._indexToPrice(index_);
        bucketLPs_ = Buckets.addCollateral(
            buckets_[index_],
            msg.sender,
            bucketDeposit,
            collateralAmountToAdd_,
            bucketPrice
        );

        lup_ = PoolLogic._indexToPrice(Deposits.findIndexOfSum(deposits_, poolDebt_));
    }

    function addQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 quoteTokenAmountToAdd_,
        uint256 index_,
        uint256 poolDebt_
    ) external returns (uint256 bucketLPs_, uint256 lup_) {
        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);
        uint256 bucketPrice   = PoolLogic._indexToPrice(index_);
        bucketLPs_ = Buckets.addQuoteToken(
            buckets_[index_],
            bucketDeposit,
            quoteTokenAmountToAdd_,
            bucketPrice
        );
        Deposits.add(deposits_, index_, quoteTokenAmountToAdd_);

        lup_ = PoolLogic._indexToPrice(Deposits.findIndexOfSum(deposits_, poolDebt_));
    }

    function moveQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        MoveParams calldata params_
    ) external returns (uint256 fromBucketLPs_, uint256 toBucketLPs_, uint256 amountToMove_, uint256 lup_) {
        if (params_.fromIndex == params_.toIndex) revert MoveToSamePrice();

        uint256 fromPrice   = PoolLogic._indexToPrice(params_.fromIndex);
        uint256 toPrice     = PoolLogic._indexToPrice(params_.toIndex);
        uint256 fromDeposit = Deposits.valueAt(deposits_, params_.fromIndex);

        Buckets.Bucket storage fromBucket = buckets_[params_.fromIndex];
        {
            (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
                buckets_,
                params_.fromIndex,
                msg.sender
            );
            (amountToMove_, fromBucketLPs_, ) = Buckets.lpsToQuoteToken(
                fromBucket.lps,
                fromBucket.collateral,
                fromDeposit,
                lenderLPs,
                params_.maxAmountToMove,
                fromPrice
            );

            Deposits.remove(deposits_, params_.fromIndex, amountToMove_, fromDeposit);

            // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
            if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
                if (fromPrice > params_.ptp && toPrice < params_.ptp) {
                    amountToMove_ = Maths.wmul(amountToMove_, Maths.WAD - params_.feeRate);
                }
            }
        }

        Buckets.Bucket storage toBucket = buckets_[params_.toIndex];
        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            Deposits.valueAt(deposits_, params_.toIndex),
            amountToMove_,
            toPrice
        );

        Deposits.add(deposits_, params_.toIndex, amountToMove_);

        Buckets.moveLPs(
            fromBucket,
            toBucket,
            fromBucketLPs_,
            toBucketLPs_
        );

        lup_ = PoolLogic._indexToPrice(Deposits.findIndexOfSum(deposits_, params_.poolDebt));
    }

    function removeQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        RemoveParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {

        (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
            buckets_,
            params_.index,
            msg.sender
        );
        if (lenderLPs == 0) revert NoClaim();      // revert if no LP to claim

        uint256 deposit = Deposits.valueAt(deposits_, params_.index);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        uint256 price = PoolLogic._indexToPrice(params_.index);

        Buckets.Bucket storage bucket = buckets_[params_.index];
        uint256 exchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            deposit,
            price
        );
        removedAmount_ = Maths.rayToWad(Maths.rmul(lenderLPs, exchangeRate));
        uint256 removedAmountBefore = removedAmount_;

        // remove min amount of lender entitled LPBs, max amount desired and deposit in bucket
        if (removedAmount_ > params_.maxAmount) removedAmount_ = params_.maxAmount;
        if (removedAmount_ > deposit)           removedAmount_ = deposit;

        if (removedAmountBefore == removedAmount_) redeemedLPs_ = lenderLPs;
        else {
            redeemedLPs_ = Maths.min(lenderLPs, Maths.wrdivr(removedAmount_, exchangeRate));
        }

        Deposits.remove(deposits_, params_.index, removedAmount_, deposit); // update FenwickTree

        // apply early withdrawal penalty if quote token is removed from above the PTP
        if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
            if (price > params_.ptp) {
                removedAmount_ = Maths.wmul(removedAmount_, Maths.WAD - params_.feeRate);
            }
        }

        // update bucket and lender LPs balances
        bucket.lps -= redeemedLPs_;
        bucket.lenders[msg.sender].lps -= redeemedLPs_;

        lup_ = PoolLogic._indexToPrice(Deposits.findIndexOfSum(deposits_, params_.poolDebt));
    }

    function transferLPTokens(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage allowances_,
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external returns (uint256 tokensTransferred_){
        uint256 indexesLength = indexes_.length;

        for (uint256 i = 0; i < indexesLength; ) {
            if (indexes_[i] > 8192 ) revert InvalidIndex();

            uint256 transferAmount = allowances_[owner_][newOwner_][indexes_[i]];
            (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = Buckets.getLenderInfo(
                buckets_,
                indexes_[i],
                owner_
            );
            if (transferAmount == 0 || transferAmount != lenderLpBalance) revert NoAllowance();

            delete allowances_[owner_][newOwner_][indexes_[i]]; // delete allowance

            Buckets.transferLPs(
                buckets_,
                owner_,
                newOwner_,
                transferAmount,
                indexes_[i],
                lenderLastDepositTime
            );

            tokensTransferred_ += transferAmount;

            unchecked {
                ++i;
            }
        }
    }
}