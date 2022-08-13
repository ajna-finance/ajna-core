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

    uint256 public constant RATE_INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 public constant RATE_DECREASE_COEFFICIENT = 0.9 * 10**18;
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

    uint256 public override lenderDebt;
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
     *  @dev deposit index -> lender address -> lender lp [RAY]
     */
    mapping(uint256 => mapping(address => uint256)) public override lpBalance;

    uint256 internal _poolInitializations = 0;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    // TODO: check index incoming index_ is valid?
    function addQuoteToken(uint256 amount_, uint256 index_) external override returns (uint256 lpbChange_) {
        uint256 curDebt = _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        uint256 rate = _exchangeRate(bucket.availableCollateral, bucket.lpAccumulator, index_);

        lpbChange_           = Maths.rdiv(Maths.wadToRay(amount_), rate);
        bucket.lpAccumulator += lpbChange_;

        lpBalance[index_][msg.sender] += lpbChange_;

        _add(index_, amount_);

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(msg.sender, _indexToPrice(index_), amount_, newLup);
    }

    function moveQuoteToken(uint256 maxAmount_, uint256 fromIndex_, uint256 toIndex_) external override {
        require(fromIndex_ != toIndex_, "S:MQT:SAME_PRICE");

        uint256 availableLPs  = lpBalance[fromIndex_][msg.sender];
        uint256 curDebt = _accruePoolInterest();

        // determine amount of quote token to move
        Bucket storage fromBucket   = buckets[fromIndex_];
        uint256 rate                = _exchangeRate(fromBucket.availableCollateral, fromBucket.lpAccumulator, fromIndex_);
        uint256 availableQuoteToken = _rangeSum(fromIndex_, fromIndex_);
        uint256 claimableQuoteToken = Maths.rrdivw(availableLPs, rate);
        uint256 amount              = Maths.min(maxAmount_, Maths.min(availableQuoteToken, claimableQuoteToken));

        // calculate amount of LP required to move it
        uint256 lpbAmount = Maths.wrdivr(amount, rate);

        // update "from" bucket accounting
        fromBucket.lpAccumulator -= lpbAmount;

        // update "to" bucket accounting
        Bucket storage toBucket = buckets[toIndex_];
        rate                    = _exchangeRate(toBucket.availableCollateral, toBucket.lpAccumulator, toIndex_);
        uint256 lpbChange       = Maths.wrdivr(amount, rate);
        toBucket.lpAccumulator  += lpbChange;

        // update FenwickTree
        _remove(fromIndex_, amount);
        _add(toIndex_, amount);

        // move lup if necessary and check loan book's htp against new lup
        uint256 newLup = _lup();
        if (fromIndex_ < toIndex_) require(_htp() <= newLup, "S:MQT:LUP_BELOW_HTP");

        // update lender accounting
        lpBalance[fromIndex_][msg.sender] -= lpbAmount;
        lpBalance[toIndex_][msg.sender]   += lpbChange;

        _updateInterestRate(curDebt, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, amount, newLup);
    }

    function removeQuoteToken(uint256 maxAmount_, uint256 index_) external override {
        // scale the tree, accumulating interest owed to lenders
        uint256 curDebt = _accruePoolInterest();

        // determine amount of quote token to remove
        Bucket memory bucket        = buckets[index_];
        uint256 rate                = _exchangeRate(bucket.availableCollateral, bucket.lpAccumulator, index_);
        uint256 availableLPs        = lpBalance[index_][msg.sender];
        uint256 availableQuoteToken = _rangeSum(index_, index_);
        uint256 claimableQuoteToken = Maths.rayToWad(Maths.rmul(availableLPs, rate));

        uint256 amount;
        uint256 lpRedemption;
        if (maxAmount_ > claimableQuoteToken && availableQuoteToken >= claimableQuoteToken) {
            // lender wants to redeem all of their LPB for quote token, and the bucket has enough to offer
            amount = claimableQuoteToken;
            lpRedemption = availableLPs;
        } else {
            // calculate how much quote token may be awarded to lender, and how much LPB to redeem
            amount = Maths.min(maxAmount_, Maths.min(availableQuoteToken, claimableQuoteToken));
            lpRedemption = Maths.wrdivr(amount, rate);
        }

        // update bucket accounting
        bucket.lpAccumulator -= lpRedemption;
        buckets[index_] = bucket;
        _remove(index_, amount); // update FenwickTree

        // update lender accounting
        lpBalance[index_][msg.sender] -= lpRedemption;

        // update pool accounting
        uint256 newLup = _lup();
        require(_htp() <= newLup, "S:RQT:BAD_LUP");
        _updateInterestRate(curDebt, newLup);

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
        emit RemoveQuoteToken(msg.sender, _indexToPrice(index_), amount, newLup);
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
                    interestRate = Maths.wmul(interestRate, RATE_INCREASE_COEFFICIENT);
                } else if (decreaseFactor > 10**18 - increaseFactor) {
                    interestRate = Maths.wmul(interestRate, RATE_DECREASE_COEFFICIENT);
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
    ) internal pure returns (uint256 collateralization_) {
        uint256 encumbered = _encumberedCollateral(borrowerDebt_ + additionalDebt_, price_);
        collateralization_ = encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function _poolCollateralization(uint256 borrowerDebt_, uint256 pledgedCollateral_, uint256 lup_) internal pure returns (uint256 collateralization_) {
        uint256 encumbered = _encumberedCollateral(borrowerDebt_, lup_);
        collateralization_ = encumbered != 0 ? Maths.wdiv(pledgedCollateral_, encumbered) : Maths.WAD;
    }

    function _poolTargetUtilization(uint256 debtEma_, uint256 lupColEma_) internal pure returns (uint256) {
        if (debtEma_ != 0 && lupColEma_ != 0) {
            return Maths.wdiv(debtEma_, lupColEma_);
        }
        return Maths.WAD;
    }

    function _poolActualUtilization(uint256 borrowerDebt_, uint256 pledgedCollateral_) internal view returns (uint256 utilization_) {
        if (pledgedCollateral_ != 0) {
            uint256 ptp = Maths.wdiv(borrowerDebt_, pledgedCollateral_);
            if (ptp != 0) utilization_ = Maths.wdiv(borrowerDebt_, _prefixSum(_priceToIndex(ptp)));
        }
    }

    function _htp() internal view returns (uint256) {
        if (loanQueueHead != address(0)) {
            return Maths.wmul(loans[loanQueueHead].thresholdPrice, inflatorSnapshot);
        }
        return 0;
    }

    function _lupIndex(uint256 additionalDebt_) internal view returns (uint256) {
        return _findSum(lenderDebt + additionalDebt_);
    }

    function _indexToPrice(uint256 index_) internal pure returns (uint256) {
        return BucketMath.indexToPrice(7388 - int256(index_) - 3232);
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

    // TODO: This performs the (expensive) _rangeSum and throws away the result.
    // We should either pass the _rangeSum as an argument, or have this method return it alongside the rate.
    function _exchangeRate(uint256 availableCollateral_, uint256 lpAccumulator_, uint256 index_) internal view returns (uint256) {
        uint256 colValue   = Maths.wmul(_indexToPrice(index_), availableCollateral_);
        uint256 bucketSize = _rangeSum(index_, index_) + colValue;
        return lpAccumulator_ != 0 ? Maths.wrdivr(bucketSize, lpAccumulator_) : Maths.RAY;
    }

    function _pendingInterestFactor(uint256 elapsed_) internal view returns (uint256) {
        uint256 rate = (interestRate / SECONDS_PER_YEAR) * elapsed_;
        return PRBMathUD60x18.exp(rate);
    }

    function _pendingInflator() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
        return Maths.wmul(inflatorSnapshot, _pendingInterestFactor(elapsed));
    }

    function _threshold_price(uint256 debt_, uint256 collateral_, uint256 inflator_) internal pure returns (uint256) {
        if (collateral_ != 0) return Maths.wdiv(Maths.wmul(inflator_, debt_), collateral_);
        return 0;
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
            this.get(index_),                    // quote token in bucket, deposit + interest (WAD)
            buckets[index_].availableCollateral, // unencumbered collateral in bucket (WAD)
            buckets[index_].lpAccumulator,       // outstanding LP balance (WAD)
            this.scale(index_)                   // lender interest multiplier (WAD)
        );
    }

    function pendingInflator() external view override returns (uint256) {
        return _pendingInflator();
    }

    function exchangeRate(uint256 index_) external view override returns (uint256) {
        return _exchangeRate(buckets[index_].availableCollateral, buckets[index_].lpAccumulator, index_);
    }

    function encumberedCollateral(uint256 debt_, uint256 price_) external pure override returns (uint256) {
        return _encumberedCollateral(debt_, price_);
    }

    function poolMinDebtAmount() external view returns (uint256) {
        if (borrowerDebt != 0) return _poolMinDebtAmount(borrowerDebt);
        return 0;
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }
}
