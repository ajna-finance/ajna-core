// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import './Maths.sol';
import './Deposits.sol';
import './Buckets.sol';
import './Loans.sol';

library PoolLogic {

    /**
        @dev constant price indices defining the min and max of the potential price range
     */
    int256 internal constant MAX_PRICE_INDEX = 4_156;
    int256 internal constant MIN_PRICE_INDEX = -3_232;

    uint256 internal constant MIN_PRICE = 99_836_282_890;
    uint256 internal constant MAX_PRICE = 1_004_968_987.606512354182109771 * 10**18;

    uint256 internal constant CUBIC_ROOT_1000000 = 100 * 1e18;
    uint256 internal constant ONE_THIRD          = 0.333333333333333334 * 1e18;

    /**
        @dev step amounts in basis points. This is a constant across pools at .005, achieved by dividing WAD by 10,000
     */
    int256 internal constant FLOAT_STEP_INT = 1.005 * 10**18;

    uint256 internal constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;

    // minimum fee that can be applied for early withdraw penalty
    uint256 internal constant MIN_FEE = 0.0005 * 10**18;

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
        address sender;
        uint256 maxAmountToMove;
        uint256 fromIndex;
        uint256 toIndex;
        uint256 poolDebt;
        uint256 ptp;
        uint256 feeRate;
    }

    struct RemoveParams {
        address sender;
        uint256 maxAmount;
        uint256 index;
        uint256 poolDebt;
        uint256 ptp;
        uint256 feeRate;
    }

    function accrueInterest(
        Deposits.Data storage deposits_,
        uint256 debt_,
        uint256 collateral_,
        uint256 thresholdPrice_,
        uint256 inflator_,
        uint256 interestRate_,
        uint256 elapsed_
    ) external returns (uint256 newInflator_) {
        // Scale the borrower inflator to update amount of interest owed by borrowers
        uint256 pendingFactor = PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
        newInflator_ = Maths.wmul(inflator_, pendingFactor);

        uint256 htp = Maths.wmul(thresholdPrice_, newInflator_);
        uint256 htpIndex = (htp != 0) ? _priceToIndex(htp) : 7_388; // if HTP is 0 then accrue interest at max index (min price)

        // Scale the fenwick tree to update amount of debt owed to lenders
        uint256 depositAboveHtp = Deposits.prefixSum(deposits_, htpIndex);

        if (depositAboveHtp != 0) {
            uint256 newInterest = Maths.wmul(
                _lenderInterestMargin(deposits_, debt_, collateral_),
                Maths.wmul(pendingFactor - Maths.WAD, debt_)
            );

            Deposits.mult(
                deposits_,
                htpIndex,
                Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD // lender factor
            );
        }
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

    function moveQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        MoveParams calldata params_
    ) external returns (uint256 fromBucketLPs_, uint256 toBucketLPs_, uint256 amountToMove_, uint256 lup_) {
        if (params_.fromIndex == params_.toIndex) revert MoveToSamePrice();

        uint256 fromPrice   = _indexToPrice(params_.fromIndex);
        uint256 toPrice     = _indexToPrice(params_.toIndex);
        uint256 fromDeposit = Deposits.valueAt(deposits_, params_.fromIndex);

        Buckets.Bucket storage fromBucket = buckets_[params_.fromIndex];
        {
            (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
                buckets_,
                params_.fromIndex,
                params_.sender
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

        lup_ = _indexToPrice(Deposits.findIndexOfSum(deposits_, params_.poolDebt));
    }

    function removeQuoteToken(
        mapping(uint256 => Buckets.Bucket) storage buckets_,
        Deposits.Data storage deposits_,
        RemoveParams calldata params_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_, uint256 lup_) {

        (uint256 lenderLPs, uint256 depositTime) = Buckets.getLenderInfo(
            buckets_,
            params_.index,
            params_.sender
        );
        if (lenderLPs == 0) revert NoClaim();      // revert if no LP to claim

        uint256 deposit = Deposits.valueAt(deposits_, params_.index);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        uint256 price = _indexToPrice(params_.index);

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
        bucket.lenders[params_.sender].lps -= redeemedLPs_;

        lup_ = _indexToPrice(Deposits.findIndexOfSum(deposits_, params_.poolDebt));
    }

    /**
     *  @notice Calculates the price for a given deposit index
     */
    function indexToPrice(
        uint256 index_
    ) external pure returns (uint256) {
        return _indexToPrice(index_);
    }

    /**
     *  @notice Calculates the deposit index for a given price
     */
    function priceToIndex(
        uint256 price_
    ) external pure returns (uint256) {
        return _priceToIndex(price_);
    }

    function pendingInterestFactor(
        uint256 interestRate_,
        uint256 elapsed_
    ) external pure returns (uint256) {
        return PRBMathUD60x18.exp((interestRate_ * elapsed_) / 365 days);
    }

    function pendingInflator(
        uint256 inflatorSnapshot_,
        uint256 lastInflatorSnapshotUpdate_,
        uint256 interestRate_
    ) external view returns (uint256) {
        return Maths.wmul(
            inflatorSnapshot_,
            PRBMathUD60x18.exp((interestRate_ * (block.timestamp - lastInflatorSnapshotUpdate_)) / 365 days)
        );
    }

    function lenderInterestMargin(
        uint256 mau_
    ) external pure returns (uint256) {
        // TODO: Consider pre-calculating and storing a conversion table in a library or shared contract.
        // cubic root of the percentage of meaningful unutilized deposit
        uint256 base = 1000000 * 1e18 - Maths.wmul(Maths.min(mau_, 1e18), 1000000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

    function utilization(
        Deposits.Data storage deposits,
        uint256 debt_,
        uint256 collateral_
    ) external view returns (uint256 utilization_) {
        if (collateral_ != 0) {
            uint256 ptp = Maths.wdiv(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits, _priceToIndex(ptp));

                if (depositAbove != 0) utilization_ = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }
    }

    /**
     *  @notice Calculates the price for a given Fenwick index
     *  @dev    Throws if index exceeds maximum constant
     *  @dev    Uses fixed-point math to get around lack of floating point numbers in EVM
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    Fenwick index is converted to bucket index
     *  @dev Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     *  @dev    V1: price = MIN_PRICE + (FLOAT_STEP * index)
     *          V2: price = MAX_PRICE * (FLOAT_STEP ** (abs(int256(index - MAX_PRICE_INDEX))));
     *          V3 (final): x^y = 2^(y*log_2(x))
     */
    function _indexToPrice(
        uint256 index_
    ) internal pure returns (uint256) {
        int256 bucketIndex = (index_ != 8191) ? MAX_PRICE_INDEX - int256(index_) : MIN_PRICE_INDEX;
        require(bucketIndex >= MIN_PRICE_INDEX && bucketIndex <= MAX_PRICE_INDEX, "BM:ITP:OOB");

        return uint256(
            PRBMathSD59x18.exp2(
                PRBMathSD59x18.mul(
                    PRBMathSD59x18.fromInt(bucketIndex),
                    PRBMathSD59x18.log2(FLOAT_STEP_INT)
                )
            )
        );
    }

    /**
     *  @notice Calculates the Fenwick index for a given price
     *  @dev    Throws if price exceeds maximum constant
     *  @dev    Price expected to be inputted as a 18 decimal WAD
     *  @dev    V1: bucket index = (price - MIN_PRICE) / FLOAT_STEP
     *          V2: bucket index = (log(FLOAT_STEP) * price) /  MAX_PRICE
     *          V3 (final): bucket index =  log_2(price) / log_2(FLOAT_STEP)
     *  @dev    Fenwick index = 7388 - bucket index + 3232
     */
    function _priceToIndex(
        uint256 price_
    ) internal pure returns (uint256) {
        require(price_ >= MIN_PRICE && price_ <= MAX_PRICE, "BM:PTI:OOB");

        int256 index = PRBMathSD59x18.div(
            PRBMathSD59x18.log2(int256(price_)),
            PRBMathSD59x18.log2(FLOAT_STEP_INT)
        );

        int256 ceilIndex = PRBMathSD59x18.ceil(index);
        if (index < 0 && ceilIndex - index > 0.5 * 1e18) {
            return uint256(4157 - PRBMathSD59x18.toInt(ceilIndex));
        }
        return uint256(4156 - PRBMathSD59x18.toInt(ceilIndex));
    }

    function _lenderInterestMargin(
        Deposits.Data storage deposits_,
        uint256 debt_,
        uint256 collateral_
    ) internal view returns (uint256) {
        // utilization
        uint256 mau;
        if (collateral_ != 0) {
            uint256 ptp = Maths.wdiv(debt_, collateral_);

            if (ptp != 0) {
                uint256 depositAbove = Deposits.prefixSum(deposits_, _priceToIndex(ptp));
                if (depositAbove != 0) mau = Maths.wdiv(
                    debt_,
                    depositAbove
                );
            }
        }

        // TODO: Consider pre-calculating and storing a conversion table in a library or shared contract.
        // cubic root of the percentage of meaningful unutilized deposit
        uint256 base = 1000000 * 1e18 - Maths.wmul(Maths.min(mau, 1e18), 1000000 * 1e18);
        if (base < 1e18) {
            return 1e18;
        } else {
            uint256 crpud = PRBMathUD60x18.pow(base, ONE_THIRD);
            return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_1000000), 0.15 * 1e18);
        }
    }

}