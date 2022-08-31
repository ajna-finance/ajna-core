// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IScaledPool } from "./interfaces/IScaledPool.sol";

import { FenwickTree } from "./FenwickTree.sol";
import { Queue }       from "./Queue.sol";

import { BucketMath }     from "../libraries/BucketMath.sol";
import { Maths }          from "../libraries/Maths.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

abstract contract ScaledPool is Clone, FenwickTree, Queue, IScaledPool {
    using SafeERC20      for ERC20;

    int256  public constant INDEX_OFFSET = 3232;

    uint256 public constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;
    uint256 public constant SECONDS_PER_YEAR    = 3_600 * 24 * 365;
    uint256 public constant SECONDS_PER_HALFDAY = 43_200;

    uint256 public constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 public constant DECREASE_COEFFICIENT = 0.9 * 10**18;
    // lambda used for the EMAs calculated as exp(-1/7 * ln2)
    uint256 public constant LAMBDA_EMA                = 0.905723664263906671 * 10**18;
    uint256 public constant EMA_RATE_FACTOR           = 10**18 - LAMBDA_EMA;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override inflatorSnapshot;           // [WAD]
    uint256 public override lastInflatorSnapshotUpdate; // [SEC]
    uint256 public override minFee;                     // [WAD]
    uint256 public override lenderInterestFactor;       // [WAD]
    uint256 public override interestRate;               // [WAD]
    uint256 public override interestRateUpdate;         // [SEC]

    uint256 public override borrowerDebt;

    uint256 public override totalBorrowers;
    uint256 public override quoteTokenScale;
    uint256 public override pledgedCollateral;

    uint256 public override debtEma;   // [WAD]
    uint256 public override lupColEma; // [WAD]

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev    deposit index -> bucket
     */
    mapping(uint256 => Bucket) public override buckets;

    /**
     *  @dev deposit index -> lender address -> lender lp [RAY] and deposit timestamp
     */
    mapping(uint256 => mapping(address => BucketLender)) public override bucketLenders;

    /**
     *  @notice Used for tracking LP token ownership address for transferLPTokens access control
     *  @dev    owner address -> new owner address -> deposit index -> allowed amount
     */
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances;

    uint256 internal poolInitializations = 0;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    // TODO: check index incoming index_ is valid?
    function addQuoteToken(uint256 amount_, uint256 index_) external override returns (uint256 lpbChange_) {
        uint256 curDebt = _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        uint256 rate = _exchangeRate(_valueAt(index_), bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpbChange_           = Maths.rdiv(Maths.wadToRay(amount_), rate);
        bucket.lpAccumulator += lpbChange_;

        BucketLender storage bucketLender = bucketLenders[index_][msg.sender];
        bucketLender.lpBalance            += lpbChange_;
        bucketLender.lastQuoteDeposit     = block.timestamp;

        _add(index_, amount_);

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move quote token amount from lender to pool
        emit AddQuoteToken(msg.sender, _indexToPrice(index_), amount_, newLup);
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
    }

    function approveLpOwnership(address allowedNewOwner_, uint256 index_, uint256 amount_) external {
        _lpTokenAllowances[msg.sender][allowedNewOwner_][index_] = amount_;
    }

    function moveQuoteToken(uint256 maxAmount_, uint256 fromIndex_, uint256 toIndex_) external override returns (uint256 lpbAmountFrom_, uint256 lpbAmountTo_) {
        require(fromIndex_ != toIndex_, "S:MQT:SAME_PRICE");

        BucketLender storage bucketLender = bucketLenders[fromIndex_][msg.sender];
        uint256 availableLPs              = bucketLender.lpBalance;
        uint256 curDebt                   = _accruePoolInterest();

        // determine amount of quote token to move
        Bucket storage fromBucket   = buckets[fromIndex_];
        uint256 availableQuoteToken = _valueAt(fromIndex_);
        uint256 rate                = _exchangeRate(availableQuoteToken, fromBucket.availableCollateral, fromBucket.lpAccumulator, fromIndex_);
        uint256 amount              = Maths.min(maxAmount_, Maths.min(availableQuoteToken, Maths.rrdivw(availableLPs, rate)));

        // calculate amount of LP required to move it
        lpbAmountFrom_ = Maths.wrdivr(amount, rate);

        // update "from" bucket accounting
        fromBucket.lpAccumulator -= lpbAmountFrom_;
        _remove(fromIndex_, amount);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        uint256 col = pledgedCollateral;
        if (col != 0 && bucketLender.lastQuoteDeposit != 0 && block.timestamp - bucketLender.lastQuoteDeposit < 1 days) {
            uint256 ptp = Maths.wdiv(curDebt, col);
            if (_indexToPrice(fromIndex_) > ptp && _indexToPrice(toIndex_) < ptp) {
                amount =  Maths.wmul(amount, Maths.WAD - _calculateFeeRate());
            }
        }

        // update "to" bucket accounting
        Bucket storage toBucket = buckets[toIndex_];
        rate                    = _exchangeRate(_valueAt(toIndex_), toBucket.availableCollateral, toBucket.lpAccumulator, toIndex_);
        lpbAmountTo_            = Maths.wrdivr(amount, rate);
        toBucket.lpAccumulator  += lpbAmountTo_;
        _add(toIndex_, amount);

        // move lup if necessary and check loan book's htp against new lup
        uint256 newLup = _lup();
        if (fromIndex_ < toIndex_) require(_htp() <= newLup, "S:MQT:LUP_BELOW_HTP");

        // update lender accounting
        bucketLender.lpBalance -= lpbAmountFrom_;
        bucketLender           = bucketLenders[toIndex_][msg.sender];
        bucketLender.lpBalance += lpbAmountTo_;

        _updateInterestRate(curDebt, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, amount, newLup);
    }

    function removeAllQuoteToken(uint256 index_) external returns (uint256 amount_, uint256 lpAmount_) {
        // scale the tree, accumulating interest owed to lenders
        _accruePoolInterest();

        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        lpAmount_ = bucketLender.lpBalance;
        require(lpAmount_ != 0, "S:RAQT:NO_CLAIM");

        Bucket memory bucket        = buckets[index_];
        uint256 availableQuoteToken = _valueAt(index_);
        uint256 rate                = _exchangeRate(availableQuoteToken, bucket.availableCollateral, bucket.lpAccumulator, index_);
        amount_                     = Maths.rayToWad(Maths.rmul(lpAmount_, rate));

        if (amount_ > availableQuoteToken) {
            // user is owed more quote token than is available in the bucket
            amount_   = availableQuoteToken;
            lpAmount_ = Maths.wrdivr(amount_, rate);
        } // else user is redeeming all of their LPs

        _redeemLPForQuoteToken(bucket, bucketLender, lpAmount_, amount_, index_);
    }

    function removeQuoteToken(uint256 amount_, uint256 index_) external override returns (uint256 lpAmount_) {
        // scale the tree, accumulating interest owed to lenders
        _accruePoolInterest();

        uint256 availableQuoteToken = _valueAt(index_);
        require(amount_ <= availableQuoteToken, "S:RQT:INSUF_QT");

        Bucket memory bucket = buckets[index_];
        uint256 rate         = _exchangeRate(availableQuoteToken, bucket.availableCollateral, bucket.lpAccumulator, index_);
        lpAmount_            = Maths.wrdivr(amount_, rate);

        BucketLender memory bucketLender = bucketLenders[index_][msg.sender];
        require(bucketLender.lpBalance != 0 && lpAmount_ <= bucketLender.lpBalance, "S:RQT:INSUF_LPS");

        _redeemLPForQuoteToken(bucket, bucketLender, lpAmount_, amount_, index_);
    }

    function transferLPTokens(address owner_, address newOwner_, uint256[] calldata indexes_) external {
        uint256 tokensTransferred;
        uint256 indexesLength = indexes_.length;

        for (uint256 i = 0; i < indexesLength; ) {
            require(BucketMath.isValidIndex(_indexToBucketIndex(indexes_[i])), "S:TLT:INVALID_INDEX");

            BucketLender memory bucketLenderOwner = bucketLenders[indexes_[i]][owner_];
            uint256 balanceToTransfer             = _lpTokenAllowances[owner_][newOwner_][indexes_[i]];
            require(balanceToTransfer != 0 && balanceToTransfer == bucketLenderOwner.lpBalance, "S:TLT:NO_ALLOWANCE");

            delete _lpTokenAllowances[owner_][newOwner_][indexes_[i]];

            // move lp tokens to the new owner address
            BucketLender memory bucketLenderNewOwner = bucketLenders[indexes_[i]][newOwner_];
            bucketLenderNewOwner.lpBalance           += balanceToTransfer;
            bucketLenderNewOwner.lastQuoteDeposit    = Maths.max(bucketLenderOwner.lastQuoteDeposit, bucketLenderNewOwner.lastQuoteDeposit);
            bucketLenders[indexes_[i]][newOwner_]  = bucketLenderNewOwner;

            // delete owner lp balance for this bucket
            delete bucketLenders[indexes_[i]][owner_];

            tokensTransferred += balanceToTransfer;

            unchecked {
                ++i;
            }
        }

        emit TransferLPTokens(owner_, newOwner_, indexes_, tokensTransferred);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _accruePoolInterest() internal returns (uint256 curDebt_) {
        curDebt_ = borrowerDebt;
        if (curDebt_ != 0) {
            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            if (elapsed != 0 ) {
                uint256 factor = _pendingInterestFactor(elapsed);
                inflatorSnapshot = Maths.wmul(inflatorSnapshot, factor);
                lastInflatorSnapshotUpdate = block.timestamp;

                // Scale the fenwick tree to update amount of debt owed to lenders
                uint256 newHtp = _htp();
                if (newHtp != 0) {
                    uint256 htpIndex        = _priceToIndex(newHtp);
                    uint256 depositAboveHtp = _prefixSum(htpIndex);

                    if (depositAboveHtp != 0) {
                        uint256 newInterest  = Maths.wmul(lenderInterestFactor, Maths.wmul(factor - Maths.WAD, curDebt_));
                        uint256 lenderFactor = Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD;
                        _mult(htpIndex, lenderFactor);
                    }
                }

                // Scale the borrower inflator to update amount of interest owed by borrowers
                curDebt_ = Maths.wmul(curDebt_, factor);
                borrowerDebt = curDebt_;
            }
        }
    }

    function _accrueBorrowerInterest(
        uint256 borrowerDebt_, uint256 borrowerInflator_, uint256 poolInflator_
    ) internal pure returns (uint256 newDebt_, uint256 newInflator_) {
        if (borrowerDebt_ != 0 && borrowerInflator_ != 0) {
            newDebt_ = Maths.wmul(borrowerDebt_, Maths.wdiv(poolInflator_, borrowerInflator_));
        }
        newInflator_ = poolInflator_;
    }

    function _redeemLPForQuoteToken(
        Bucket memory bucket,
        BucketLender memory bucketLender,
        uint256 lpAmount_,
        uint256 amount,
        uint256 index_
    ) internal {
        _remove(index_, amount);  // update FenwickTree

        uint256 newLup = _lup();
        require(_htp() <= newLup, "S:RQT:BAD_LUP");

        bucket.lpAccumulator   -= lpAmount_;
        bucketLender.lpBalance -= lpAmount_;

        // persist bucket changes
        buckets[index_] = bucket;
        bucketLenders[index_][msg.sender] = bucketLender;

        // apply early withdrawal penalty if quote token is withdrawn above the PTP
        uint256 col  = pledgedCollateral;
        uint256 debt = borrowerDebt;
        if (col != 0 && bucketLender.lastQuoteDeposit != 0 && block.timestamp - bucketLender.lastQuoteDeposit < 1 days) {
            uint256 ptp = Maths.wdiv(debt, col);
            if (_indexToPrice(index_) > ptp) {
                amount =  Maths.wmul(amount, Maths.WAD - _calculateFeeRate());
            }
        }

        _updateInterestRate(debt, newLup);

        // move quote token amount from pool to lender
        emit RemoveQuoteToken(msg.sender, _indexToPrice(index_), amount, newLup);
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
    }

    function _updateInterestRate(uint256 curDebt_, uint256 lup_) internal {

        if (block.timestamp - interestRateUpdate > SECONDS_PER_HALFDAY) {
            uint256 col = pledgedCollateral;

            uint256 curDebtEma   = Maths.wmul(curDebt_, EMA_RATE_FACTOR) + Maths.wmul(debtEma, LAMBDA_EMA);
            uint256 curLupColEma = Maths.wmul(Maths.wmul(lup_, col), EMA_RATE_FACTOR) + Maths.wmul(lupColEma, LAMBDA_EMA);

            debtEma   = curDebtEma;
            lupColEma = curLupColEma;

            if (_poolCollateralization(curDebt_, col, lup_) != Maths.WAD) {
                uint256 oldRate = interestRate;

                int256 actualUtilization = int256(_poolActualUtilization(curDebt_, col));
                int256 targetUtilization = int256(Maths.wdiv(curDebtEma, curLupColEma));

                int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
                int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

                if (decreaseFactor < increaseFactor - 10**18) {
                    interestRate = Maths.wmul(interestRate, INCREASE_COEFFICIENT);
                } else if (decreaseFactor > 10**18 - increaseFactor) {
                    interestRate = Maths.wmul(interestRate, DECREASE_COEFFICIENT);
                }

                interestRateUpdate = block.timestamp;

                emit UpdateInterestRate(oldRate, interestRate);
            }
        }
    }

    function _borrowerCollateralization(uint256 debt_, uint256 collateral_, uint256 price_) internal pure returns (uint256 collateralization_) {
        uint256 encumbered = _encumberedCollateral(debt_, price_);
        collateralization_ = collateral_ != 0 && encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    // TODO: Check if price and debt checks here are really needed
    function _encumberedCollateral(uint256 debt_, uint256 price_) internal pure returns (uint256 encumberance_) {
        encumberance_ =  price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
    }

    function _poolCollateralizationAtPrice(
        uint256 borrowerDebt_, uint256 additionalDebt_, uint256 collateral_, uint256 price_
    ) internal pure returns (uint256) {
        uint256 encumbered = _encumberedCollateral(borrowerDebt_ + additionalDebt_, price_);
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function _poolCollateralization(uint256 borrowerDebt_, uint256 pledgedCollateral_, uint256 lup_) internal pure returns (uint256) {
        uint256 encumbered = _encumberedCollateral(borrowerDebt_, lup_);
        return encumbered != 0 ? Maths.wdiv(pledgedCollateral_, encumbered) : Maths.WAD;
    }

    function _poolTargetUtilization(uint256 debtEma_, uint256 lupColEma_) internal pure returns (uint256) {
        return (debtEma_ != 0 && lupColEma_ != 0) ? Maths.wdiv(debtEma_, lupColEma_) : Maths.WAD;
    }

    function _poolActualUtilization(uint256 borrowerDebt_, uint256 pledgedCollateral_) internal view returns (uint256 utilization_) {
        if (pledgedCollateral_ != 0) {
            uint256 ptp = Maths.wdiv(borrowerDebt_, pledgedCollateral_);
            if (ptp != 0) utilization_ = Maths.wdiv(borrowerDebt_, _prefixSum(_priceToIndex(ptp)));
        }
    }

    function _htp() internal view returns (uint256 htp_) {
        if (loanQueueHead != address(0)) htp_ = Maths.wmul(loans[loanQueueHead].thresholdPrice, inflatorSnapshot);
    }

    function _lupIndex(uint256 additionalDebt_) internal view returns (uint256) {
        return _findSum(borrowerDebt + additionalDebt_);
    }

    /**
     *  @dev Fenwick index to bucket index conversion
     *          1.00      : bucket index 0,     fenwick index 4146: 7388-4156-3232=0
     *          MAX_PRICE : bucket index 4156,  fenwick index 0:    7388-0-3232=4156.
     *          MIN_PRICE : bucket index -3232, fenwick index 7388: 7388-7388-3232=-3232.
     */
    function _indexToBucketIndex(uint256 index_) internal pure returns (int256 bucketIndex_) {
        bucketIndex_ = (index_ != 8191) ? 4156 - int256(index_) : BucketMath.MIN_PRICE_INDEX;
    }

    function _indexToPrice(uint256 index_) internal pure returns (uint256) {
        return BucketMath.indexToPrice(_indexToBucketIndex(index_));
    }

    function _priceToIndex(uint256 price_) internal pure returns (uint256) {
        return uint256(7388 - (BucketMath.priceToIndex(price_) + 3232));
    }

    function _poolMinDebtAmount(uint256 debt_) internal view returns (uint256) {
        return Maths.wdiv(Maths.wdiv(debt_, Maths.wad(totalBorrowers)), 10**19);
    }

    function _lup() internal view returns (uint256) {
        return _indexToPrice(_lupIndex(0));
    }

    function _calculateFeeRate() internal view returns (uint256) {
        // greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps
        return Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
    }

    // We should either pass the _rangeSum as an argument, or have this method return it alongside the rate.
    function _exchangeRate(uint256 quoteToken_, uint256 availableCollateral_, uint256 lpAccumulator_, uint256 index_) internal pure returns (uint256) {
        uint256 colValue   = Maths.wmul(_indexToPrice(index_), availableCollateral_);
        uint256 bucketSize = quoteToken_ + colValue;
        return lpAccumulator_ != 0 ? Maths.wrdivr(bucketSize, lpAccumulator_) : Maths.RAY;
    }

    function _lpsToQuoteTokens(uint256 deposit_, uint256 lpTokens_, uint256 index_) internal view returns (uint256 quoteAmount_) {
        Bucket memory bucket = buckets[index_];
        uint256 rate         = _exchangeRate(deposit_, bucket.availableCollateral, bucket.lpAccumulator, index_);
        quoteAmount_         = Maths.min(deposit_, Maths.rayToWad(Maths.rmul(lpTokens_, rate))); // TODO optimize to calculate bucket size only once
    }

    function _pendingInterestFactor(uint256 elapsed_) internal view returns (uint256) {
        return PRBMathUD60x18.exp((interestRate * elapsed_) / SECONDS_PER_YEAR);
    }

    function _pendingInflator() internal view returns (uint256) {
        return Maths.wmul(inflatorSnapshot, _pendingInterestFactor(block.timestamp - lastInflatorSnapshotUpdate));
    }

    function _thresholdPrice(uint256 debt_, uint256 collateral_, uint256 inflator_) internal pure returns (uint256 tp_) {
        if (collateral_ != 0) tp_ = Maths.wdiv(Maths.wmul(inflator_, debt_), collateral_);
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function lup() external view override returns (uint256) {
        return _lup();
    }

    function lupIndex() external view override returns (uint256) {
        return _lupIndex(0);
    }

    function htp() external view returns (uint256) {
        return _htp();
    }

    function poolTargetUtilization() external view override returns (uint256) {
        return _poolTargetUtilization(debtEma, lupColEma);
    }

    function poolActualUtilization() external view override returns (uint256) {
        return _poolActualUtilization(borrowerDebt, pledgedCollateral);
    }

    function priceToIndex(uint256 price_) external pure override returns (uint256) {
        return _priceToIndex(price_);
    }

    function indexToPrice(uint256 index_) external pure override returns (uint256) {
        return _indexToPrice(index_);
    }

    function poolCollateralization() external view override returns (uint256) {
        return _poolCollateralization(borrowerDebt, pledgedCollateral, _lup());
    }

    function borrowerCollateralization(uint256 debt_, uint256 collateral_, uint256 price_) external pure override returns (uint256) {
        return _borrowerCollateralization(debt_, collateral_, price_);
    }

    function bucketAt(uint256 index_) external view override returns (uint256, uint256, uint256, uint256) {
        return (
            _valueAt(index_),           // quote token in bucket, deposit + interest (WAD)
            buckets[index_].availableCollateral, // unencumbered collateral in bucket (WAD)
            buckets[index_].lpAccumulator,       // outstanding LP balance (WAD)
            _scale(index_)                       // lender interest multiplier (WAD)
        );
    }

    function bucketCount() external view returns (uint256) {
        return this.SIZE();
    }

    function depositAt(uint256 index_) external view override returns (uint256) {
        return _valueAt(index_);
    }

    function liquidityToPrice(uint256 index_) external view returns (uint256) {
        return _prefixSum(index_);
    }

    function lpsToQuoteTokens(uint256 deposit_, uint256 lpTokens_, uint256 index_) external view override returns (uint256) {
        return _lpsToQuoteTokens(deposit_, lpTokens_, index_);
    }

    function pendingInflator() external view override returns (uint256) {
        return _pendingInflator();
    }

    function exchangeRate(uint256 index_) external view override returns (uint256) {
        return _exchangeRate(_valueAt(index_), buckets[index_].availableCollateral, buckets[index_].lpAccumulator, index_);
    }

    function encumberedCollateral(uint256 debt_, uint256 price_) external pure override returns (uint256) {
        return _encumberedCollateral(debt_, price_);
    }

    function poolMinDebtAmount() external view returns (uint256) {
        if (borrowerDebt != 0) return _poolMinDebtAmount(borrowerDebt);
        return 0;
    }

    function poolSize() external view returns (uint256) {
        return _treeSum();
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function collateralTokenAddress() external pure returns (address) {
        return _getArgAddress(0);
    }

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    function quoteTokenAddress() external pure returns (address) {
        return _getArgAddress(0x14);
    }
}
