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
        uint256 bucketDeposit = Deposits.valueAt(deposits_, index_);
        uint256 bucketPrice   = _priceAt(index_);
        bucketLPs_ = Buckets.addQuoteToken(
            buckets_[index_],
            bucketDeposit,
            quoteTokenAmountToAdd_,
            bucketPrice
        );
        Deposits.add(deposits_, index_, quoteTokenAmountToAdd_);
    }

    function moveQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        MoveQuoteParams calldata params_
    ) external returns (uint256 fromBucketLPs_, uint256 toBucketLPs_, uint256 lup_) {
        if (params_.fromIndex == params_.toIndex) revert MoveToSamePrice();

        uint256 fromPrice   = _priceAt(params_.fromIndex);
        uint256 toPrice     = _priceAt(params_.toIndex);
        uint256 fromDeposit = Deposits.valueAt(deposits_, params_.fromIndex);
        uint256 amountToMove;

        Buckets.Bucket storage fromBucket = buckets_[params_.fromIndex];
        {
            (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
                buckets_,
                params_.fromIndex,
                msg.sender
            );
            (amountToMove, fromBucketLPs_) = Buckets.lpsToQuoteToken(
                fromBucket.lps,
                fromBucket.collateral,
                fromDeposit,
                lenderLPs,
                params_.maxAmountToMove,
                fromPrice
            );

            Deposits.remove(deposits_, params_.fromIndex, amountToMove, fromDeposit);

            // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
            if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
                if (fromPrice > params_.ptp && toPrice < params_.ptp) {
                    amountToMove = Maths.wmul(amountToMove, Maths.WAD - _feeRate(params_.rate));
                }
            }
        }

        Buckets.Bucket storage toBucket = buckets_[params_.toIndex];
        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            Deposits.valueAt(deposits_, params_.toIndex),
            amountToMove,
            toPrice
        );

        Deposits.add(deposits_, params_.toIndex, amountToMove);

        Buckets.moveLPs(
            fromBucket,
            toBucket,
            fromBucketLPs_,
            toBucketLPs_
        );

        lup_ = _lup(deposits_, params_.poolDebt);
        // check loan book's htp against new lup
        if (params_.fromIndex < params_.toIndex) if(params_.htp > lup_) revert LUPBelowHTP();
        emit MoveQuoteToken(msg.sender, params_.fromIndex, params_.toIndex, amountToMove, lup_);
    }

    function removeQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        RemoveQuoteParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {

        (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
            buckets_,
            params_.index,
            msg.sender
        );
        if (lenderLPs == 0) revert NoClaim();      // revert if no LP to claim

        uint256 deposit = Deposits.valueAt(deposits_, params_.index);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        uint256 price = _priceAt(params_.index);

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
                removedAmount_ = Maths.wmul(removedAmount_, Maths.WAD - _feeRate(params_.rate));
            }
        }

        // update bucket and lender LPs balances
        bucket.lps -= redeemedLPs_;
        bucket.lenders[msg.sender].lps -= redeemedLPs_;

        lup_ = _lup(deposits_, params_.poolDebt);
        // check loan book's htp against new lup
        if (params_.htp > lup_) revert LUPBelowHTP();
        emit RemoveQuoteToken(msg.sender, params_.index, removedAmount_, lup_);
    }

    function removeMaxCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 maxAmount_,
        uint256 index_
    ) external returns (uint256 collateralAmount_, uint256 lpAmount_) {

        Buckets.Bucket storage bucket = buckets_[index_];
        if (bucket.collateral == 0) revert InsufficientCollateral(); // revert if there's no collateral in bucket

        (uint256 lenderLpBalance, ) = Buckets.getLenderInfo(buckets_, index_, msg.sender);
        if (lenderLpBalance == 0) revert NoClaim();                  // revert if no LP to redeem

        uint256 bucketPrice = _priceAt(index_);
        uint256 exchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            Deposits.valueAt(deposits_, index_),
            bucketPrice
        );

        // limit amount by what is available in the bucket
        collateralAmount_ = Maths.min(maxAmount_, bucket.collateral);

        // determine how much LP would be required to remove the requested amount
        uint256 requiredLPs = (collateralAmount_ * bucketPrice * 1e18 + exchangeRate / 2) / exchangeRate;

        // limit withdrawal by the lender's LPB
        if (requiredLPs < lenderLpBalance) {
            lpAmount_ = requiredLPs;
        } else {
            lpAmount_ = lenderLpBalance;
            collateralAmount_ = ((lpAmount_ * exchangeRate + 1e27 / 2) / 1e18 + bucketPrice / 2) / bucketPrice;
        }

        Buckets.removeCollateral(
            bucket,
            collateralAmount_,
            lpAmount_
        );
    }

    function removeCollateral(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        uint256 amount_,
        uint256 index_
    ) external returns (uint256 lpAmount_) {

        Buckets.Bucket storage bucket = buckets_[index_];
        if (amount_ > bucket.collateral) revert InsufficientCollateral();

        uint256 bucketPrice = _priceAt(index_);
        lpAmount_ = Buckets.collateralToLPs(
            bucket.collateral,
            bucket.lps,
            Deposits.valueAt(deposits_, index_),
            amount_,
            bucketPrice
        );

        (uint256 lenderLpBalance, ) = Buckets.getLenderInfo(buckets_, index_, msg.sender);
        // ensure lender has enough balance to remove collateral amount
        if (lenderLpBalance == 0 || lpAmount_ > lenderLpBalance) revert InsufficientLPs();

        Buckets.removeCollateral(
            bucket,
            amount_,
            lpAmount_
        );
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