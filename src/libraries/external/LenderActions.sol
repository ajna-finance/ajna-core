// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import '../../base/interfaces/pool/IPoolEvents.sol';

import '../Deposits.sol';
import '../Buckets.sol';

import '../../base/PoolHelper.sol';

/**
    @notice External library containing logic for common lender actions.
 */
library LenderActions {

    /**
     *  @notice Operation cannot be executed in the same block when bucket becomes insolvent.
     */
    error BucketBankruptcyBlock();
    /**
     *  @notice Owner of the LP tokens must have approved the new owner prior to transfer.
     */
    error NoAllowance();
    /**
     *  @notice When transferring LP tokens between indices, the new index must be a valid index.
     */
    error InvalidIndex();
    /**
     *  @notice When moving quote token HTP must stay below LUP.
     *  @notice When removing quote token HTP must stay below LUP.
     */
    error LUPBelowHTP();
    /**
     *  @notice Lender must have non-zero LPB when attempting to remove quote token from the pool.
     */
    error NoClaim();
    /**
     *  @notice Lender is attempting to remove more collateral they have claim to in the bucket.
     */
    error InsufficientLPs();
    /**
     *  @notice Deposit must have more quote available than the lender is attempting to claim.
     */
    error InsufficientLiquidity();
    /**
     *  @notice User is attempting to remove more collateral than available.
     */
    error InsufficientCollateral();
    /**
     *  @notice From and to deposit indexes to move are the same.
     */
    error MoveToSamePrice();

    /**
     *  @dev Struct to hold move quote token details, used to prevent stack too deep error.
     */
    struct MoveQuoteLocalVars {
        uint256 amountToMove;
        uint256 fromBucketPrice;
        uint256 fromBucketDeposit;
        uint256 fromBucketLPs;
        uint256 fromBucketDepositTime;
        uint256 toBucketPrice;
        uint256 toBucketBankruptcyTime;
    }

    struct MoveQuoteParams {
        uint256 maxAmountToMove; // max amount to move between deposits
        uint256 fromIndex;       // the deposit index from where amount is moved
        uint256 toIndex;         // the deposit index where amount is moved to
        uint256 ptp;             // the Pool Threshold Price (used to determine if penalty should be applied
        uint256 htp;             // the Highest Threshold Price in pool
        uint256 poolDebt;        // the current debt of the pool
        uint256 rate;            // the interest rate in pool (used to calculate penalty)
    }

    struct RemoveQuoteParams {
        uint256 maxAmount; // max amount to be removed
        uint256 index;     // the deposit index from where amount is removed
        uint256 ptp;       // the Pool Threshold Price (used to determine if penalty should be applied)
        uint256 htp;       // the Highest Threshold Price in pool
        uint256 poolDebt;  // the current debt of the pool
        uint256 rate;      // the interest rate in pool (used to calculate penalty)
    }

    event MoveQuoteToken(
        address indexed lender,
        uint256 indexed from,
        uint256 indexed to,
        uint256 amount,
        uint256 lup
    );

    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );

    event TransferLPTokens(
        address owner,
        address newOwner,
        uint256[] indexes,
        uint256 lpTokens
    );

    function addCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) external returns (uint256 bucketLPs_) {
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

    function addQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external returns (uint256 bucketLPs_) {
        Buckets.Bucket storage bucket = buckets_[index_];
        uint256 bankruptcyTime = bucket.bankruptcyTime;
        // cannot deposit in the same block when bucket becomes insolvent
        if (bankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);
        uint256 bucketPrice   = _priceAt(index_);
        bucketLPs_ = Buckets.quoteTokensToLPs(
            bucket.collateral,
            bucket.lps,
            bucketDeposit,
            quoteTokenAmountToAdd_,
            bucketPrice
        );

        Deposits.add(deposits_, index_, quoteTokenAmountToAdd_);

        // update lender LPs
        Buckets.Lender storage lender = bucket.lenders[msg.sender];
        if (bankruptcyTime >= lender.depositTime) lender.lps = bucketLPs_;
        else lender.lps += bucketLPs_;
        lender.depositTime = block.timestamp;
        // update bucket LPs
        bucket.lps += bucketLPs_;
    }

    function moveQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        MoveQuoteParams calldata params_
    ) external returns (uint256 fromBucketLPs_, uint256 toBucketLPs_, uint256 lup_) {
        if (params_.fromIndex == params_.toIndex) revert MoveToSamePrice();

        Buckets.Bucket storage toBucket = buckets_[params_.toIndex];

        MoveQuoteLocalVars memory vars;
        vars.toBucketBankruptcyTime = toBucket.bankruptcyTime;
        // cannot move in the same block when target bucket becomes insolvent
        if (vars.toBucketBankruptcyTime == block.timestamp) revert BucketBankruptcyBlock();

        Buckets.Bucket storage fromBucket = buckets_[params_.fromIndex];
        Buckets.Lender storage fromBucketLender = fromBucket.lenders[msg.sender];

        vars.fromBucketPrice       = _priceAt(params_.fromIndex);
        vars.toBucketPrice         = _priceAt(params_.toIndex);
        vars.fromBucketDeposit     = Deposits.valueAt(deposits_, params_.fromIndex);
        vars.fromBucketDepositTime = fromBucketLender.depositTime;

        if (fromBucket.bankruptcyTime < vars.fromBucketDepositTime) vars.fromBucketLPs = fromBucketLender.lps;
        (vars.amountToMove, fromBucketLPs_) = Buckets.lpsToQuoteToken(
            fromBucket.lps,
            fromBucket.collateral,
            vars.fromBucketDeposit,
            vars.fromBucketLPs,
            params_.maxAmountToMove,
            vars.fromBucketPrice
        );

        Deposits.remove(deposits_, params_.fromIndex, vars.amountToMove, vars.fromBucketDeposit);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        if (vars.fromBucketDepositTime != 0 && block.timestamp - vars.fromBucketDepositTime < 1 days) {
            if (vars.fromBucketPrice > params_.ptp && vars.toBucketPrice < params_.ptp) {
                vars.amountToMove = Maths.wmul(vars.amountToMove, Maths.WAD - _feeRate(params_.rate));
            }
        }

        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            Deposits.valueAt(deposits_, params_.toIndex),
            vars.amountToMove,
            vars.toBucketPrice
        );

        Deposits.add(deposits_, params_.toIndex, vars.amountToMove);

        lup_ = _lup(deposits_, params_.poolDebt);
        // check loan book's htp against new lup
        if (params_.fromIndex < params_.toIndex) if(params_.htp > lup_) revert LUPBelowHTP();

        // update lender LPs balance in from bucket
        fromBucketLender.lps -= fromBucketLPs_;
        // update lender LPs balance and deposit time in target bucket
        Buckets.Lender storage toBucketLender = toBucket.lenders[msg.sender];
        if (vars.toBucketBankruptcyTime >= toBucketLender.depositTime) toBucketLender.lps = toBucketLPs_;
        else toBucketLender.lps += toBucketLPs_;
        // set deposit time to the greater of the lender's from bucket and the target bucket's last bankruptcy timestamp + 1 so deposit won't get invalidated
        toBucketLender.depositTime = Maths.max(vars.fromBucketDepositTime, vars.toBucketBankruptcyTime + 1);

        // update buckets LPs balance
        fromBucket.lps -= fromBucketLPs_;
        toBucket.lps   += toBucketLPs_;

        emit MoveQuoteToken(msg.sender, params_.fromIndex, params_.toIndex, vars.amountToMove, lup_);
    }

    function removeQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        RemoveQuoteParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {
        uint256 deposit = Deposits.valueAt(deposits_, params_.index);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        Buckets.Bucket storage bucket = buckets_[params_.index];
        Buckets.Lender storage lender = bucket.lenders[msg.sender];
        uint256 depositTime = lender.depositTime;
        uint256 lenderLPs;
        if (bucket.bankruptcyTime < lender.depositTime) lenderLPs = lender.lps;
        if (lenderLPs == 0) revert NoClaim();      // revert if no LP to claim

        uint256 price = _priceAt(params_.index);
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
                removedAmount_ = Maths.wmul(removedAmount_, Maths.WAD - _feeRate(params_.rate));
            }
        }

        lup_ = _lup(deposits_, params_.poolDebt);
        // check loan book's htp against new lup
        if (params_.htp > lup_) revert LUPBelowHTP();

        // update lender and bucket LPs balances
        lender.lps -= redeemedLPs_;
        bucket.lps -= redeemedLPs_;

        emit RemoveQuoteToken(msg.sender, params_.index, removedAmount_, lup_);
    }

    function removeMaxCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 maxAmount_,
        uint256 index_
    ) external returns (uint256 collateralAmount_, uint256 lpAmount_) {

        Buckets.Bucket storage bucket = buckets_[index_];
        uint256 bucketCollateral = bucket.collateral;
        if (bucketCollateral == 0) revert InsufficientCollateral(); // revert if there's no collateral in bucket

        Buckets.Lender storage lender = bucket.lenders[msg.sender];
        uint256 lenderLpBalance;
        if (bucket.bankruptcyTime < lender.depositTime) lenderLpBalance = lender.lps;
        if (lenderLpBalance == 0) revert NoClaim();                  // revert if no LP to redeem

        uint256 bucketPrice = _priceAt(index_);
        uint256 bucketLPs   = bucket.lps;
        uint256 exchangeRate = Buckets.getExchangeRate(
            bucketCollateral,
            bucketLPs,
            Deposits.valueAt(deposits_, index_),
            bucketPrice
        );

        // limit amount by what is available in the bucket
        collateralAmount_ = Maths.min(maxAmount_, bucketCollateral);

        // determine how much LP would be required to remove the requested amount
        uint256 requiredLPs = (collateralAmount_ * bucketPrice * 1e18 + exchangeRate / 2) / exchangeRate;

        // limit withdrawal by the lender's LPB
        if (requiredLPs < lenderLpBalance) {
            lpAmount_ = requiredLPs;
        } else {
            lpAmount_ = lenderLpBalance;
            collateralAmount_ = ((lpAmount_ * exchangeRate + 1e27 / 2) / 1e18 + bucketPrice / 2) / bucketPrice;
        }

        // update lender LPs balance
        lender.lps -= lpAmount_;
        // update bucket LPs and collateral balance
        bucket.lps        -= Maths.min(bucketLPs, lpAmount_);
        bucket.collateral -= Maths.min(bucketCollateral, collateralAmount_);
    }

    function removeCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 amount_,
        uint256 index_
    ) external returns (uint256 lpAmount_) {

        Buckets.Bucket storage bucket = buckets_[index_];
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

        Buckets.Lender storage lender = bucket.lenders[msg.sender];
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
     *  @notice Called by lenders to transfers their LP tokens to a different address.
     *  @dev    Used by PositionManager.memorializePositions().
     *  @param  owner_    The original owner address of the position.
     *  @param  newOwner_ The new owner address of the position.
     *  @param  indexes_  Array of deposit indexes at which LP tokens were moved.
     */
    function transferLPTokens(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        mapping(address => mapping(address => mapping(uint256 => uint256))) storage allowances_,
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_
    ) external {
        uint256 indexesLength = indexes_.length;
        uint256 tokensTransferred;

        for (uint256 i = 0; i < indexesLength; ) {
            uint256 index = indexes_[i];
            if (index > 8192 ) revert InvalidIndex();

            uint256 transferAmount = allowances_[owner_][newOwner_][index];
            Buckets.Bucket storage bucket = buckets_[index];

            Buckets.Lender storage lender = bucket.lenders[owner_];
            uint256 lenderDepositTime = lender.depositTime;
            uint256 lenderLpBalance;
            if (bucket.bankruptcyTime < lenderDepositTime) lenderLpBalance = lender.lps;

            if (transferAmount == 0 || transferAmount != lenderLpBalance) revert NoAllowance();

            delete allowances_[owner_][newOwner_][index]; // delete allowance

            // move lp tokens to the new owner address
            Buckets.Lender storage newLender = bucket.lenders[newOwner_];
            newLender.lps         += transferAmount;
            newLender.depositTime = Maths.max(lenderDepositTime, newLender.depositTime);
            // reset owner lp balance for this index
            delete bucket.lenders[owner_];

            tokensTransferred += transferAmount;

            unchecked {
                ++i;
            }
        }
        emit TransferLPTokens(owner_, newOwner_, indexes_, tokensTransferred);
    }

    function _lup(
        Deposits.Data storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return _priceAt(Deposits.findIndexOfSum(deposits_, debt_));
    }
}