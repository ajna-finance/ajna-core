// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { FenwickTree } from "./FenwickTree.sol";
import { Queue }       from "./Queue.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";

contract ScaledPool is Clone, FenwickTree, Queue {
    using SafeERC20 for ERC20;

    /**************/
    /*** Events ***/
    /**************/

    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    event AddCollateral(address indexed borrower_, uint256 amount_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event RemoveCollateral(address indexed borrower_, uint256 amount_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);

    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    /***************/
    /*** Structs ***/
    /***************/

    struct Bucket {
        uint256 lpAccumulator;
        uint256 availableCollateral;
    }

    struct Borrower {
        uint256 debt;
        uint256 collateral;
        uint256 inflatorSnapshot;
    }

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

    uint256 public inflatorSnapshot;           // [WAD]
    uint256 public lastInflatorSnapshotUpdate; // [SEC]
    uint256 public minFee;                     // [WAD]
    uint256 public lenderInterestFactor;       // WAD
    uint256 public interestRate;               // [WAD]
    uint256 public interestRateUpdate;         // [SEC]

    uint256 public lenderDebt;
    uint256 public borrowerDebt;

    uint256 public collateralScale;
    uint256 public quoteTokenScale;

    uint256 public pledgedCollateral;

    uint256 public debtEma;   // [WAD]
    uint256 public lupColEma; // [WAD]

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev    deposit index -> bucket
     */
    mapping(uint256 => Bucket) public buckets;

    /**
     *  @dev deposit index -> lender address -> lender lp [WAD]
     */
    mapping(uint256 => mapping(address => uint256)) public lpBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => Borrower) public borrowers;

    uint256 internal _poolInitializations = 0;

    /*****************************/
    /*** Inititalize Functions ***/
    /*****************************/

    function initialize(uint256 rate_) external {
        require(_poolInitializations == 0, "P:INITIALIZED");
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(uint256 amount_, uint256 index_) external returns (uint256 lpbChange_) {
        uint256 curDebt = _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        uint256 bucketSize    = _rangeSum(index_, index_);
        uint256 exchangeRate  = bucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, bucket.lpAccumulator) : Maths.WAD;

        lpbChange_            = Maths.wdiv(amount_, exchangeRate);
        bucket.lpAccumulator  += lpbChange_;

        lpBalance[index_][msg.sender] += lpbChange_;

        _add(index_, amount_);

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(msg.sender, _indexToPrice(index_), amount_, newLup);
    }

    function moveQuoteToken(uint256 lpbAmount_, uint256 fromIndex_, uint256 toIndex_) external {
        require(fromIndex_ != toIndex_, "S:MQT:SAME_PRICE");

        uint256 availableLPs = lpBalance[fromIndex_][msg.sender];
        require(availableLPs != 0 && lpbAmount_ <= availableLPs, "S:MQT:INSUF_LPS");

        uint256 curDebt = _accruePoolInterest();

        Bucket storage fromBucket = buckets[fromIndex_];
        uint256 bucketSize        = _rangeSum(fromIndex_, fromIndex_);
        uint256 exchangeRate      = fromBucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, fromBucket.lpAccumulator) : Maths.WAD;
        uint256 amount            = Maths.wmul(lpbAmount_, exchangeRate);
        fromBucket.lpAccumulator  -= lpbAmount_;

        Bucket storage toBucket = buckets[toIndex_];
        bucketSize              = _rangeSum(toIndex_, toIndex_);
        exchangeRate            = toBucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, toBucket.lpAccumulator) : Maths.WAD;
        uint256 lpbChange       = Maths.wdiv(amount, exchangeRate);
        toBucket.lpAccumulator  += lpbChange;

        _remove(fromIndex_, amount);
        _add(toIndex_, amount);

        uint256 newLup = _lup();
        if (fromIndex_ < toIndex_) require(_htp() <= newLup, "S:MQT:LUP_BELOW_HTP");

        lpBalance[fromIndex_][msg.sender] -= lpbAmount_;
        lpBalance[toIndex_][msg.sender]   += lpbChange;

        _updateInterestRate(curDebt, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, lpbAmount_, newLup);

    }

    function removeQuoteToken(uint256 lpbAmount_, uint256 index_) external {
        uint256 availableLPs = lpBalance[index_][msg.sender];
        require(availableLPs != 0 && lpbAmount_ <= availableLPs, "S:RQT:INSUF_LPS");

        uint256 curDebt = _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        uint256 bucketSize    = _rangeSum(index_, index_);
        uint256 exchangeRate  = bucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, bucket.lpAccumulator) : Maths.WAD;
        uint256 amount        = Maths.wmul(lpbAmount_, exchangeRate);
        bucket.lpAccumulator  -= lpbAmount_;

        lpBalance[index_][msg.sender] -= lpbAmount_;

        _remove(index_, amount);

        uint256 newLup = _lup();
        require(_htp() <= newLup, "S:RQT:BAD_LUP");

        _updateInterestRate(curDebt, newLup);

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
        emit RemoveQuoteToken(msg.sender, _indexToPrice(index_), amount, newLup);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) external {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);
        borrower.collateral += amount_;

        if (borrower.debt != 0) _updateLoanQueue(msg.sender, Maths.wdiv(borrower.debt, borrower.collateral), oldPrev_, newPrev_, radius_);
        borrowers[msg.sender] = borrower;

        pledgedCollateral += amount_;

        _updateInterestRate(curDebt, _lup());

        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function borrow(uint256 amount_, uint256 limitIndex_, address oldPrev_, address newPrev_, uint256 radius_) external {

        uint256 lupId = _lupIndex(amount_);
        require(lupId <= limitIndex_, "S:B:LIMIT_REACHED");

        uint256 curDebt = _accruePoolInterest();
        Borrower memory borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 feeRate = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee) + Maths.WAD;
        uint256 debt    = Maths.wmul(amount_, feeRate);
        borrower.debt   += debt;

        uint256 newLup = _indexToPrice(lupId);
        require(_borrowerCollateralization(borrower.debt, borrower.collateral, newLup) >= Maths.WAD, "S:B:BUNDER_COLLAT");

        curDebt += debt;
        require(
            _poolCollateralizationAtPrice(curDebt, amount_, pledgedCollateral / collateralScale, newLup) != Maths.WAD,
            "S:B:PUNDER_COLLAT"
        );

        borrowerDebt = curDebt;
        lenderDebt   += amount_;

        _updateLoanQueue(msg.sender, Maths.wdiv(borrower.debt, borrower.collateral), oldPrev_, newPrev_, radius_);
        borrowers[msg.sender] = borrower;

        _updateInterestRate(curDebt, newLup);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, newLup, amount_);
    }

    function removeCollateral(uint256 amount_, address oldPrev_, address newPrev_, uint256 radius_) external {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower storage borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 curLup = _lup();
        require(borrower.debt <= Maths.wmul(curLup, borrower.collateral - amount_), "S:RC:NOT_ENOUGH_COLLATERAL");
        borrower.collateral -= amount_;

        if (borrower.debt != 0) _updateLoanQueue(msg.sender, Maths.wdiv(borrower.debt, borrower.collateral), oldPrev_, newPrev_, radius_);

        pledgedCollateral -= amount_;

        _updateInterestRate(curDebt, curLup);

        // move collateral from pool to sender
        collateral().safeTransfer(msg.sender, amount_ / collateralScale);
        emit RemoveCollateral(msg.sender, amount_);
    }

    function repay(uint256 maxAmount_, address oldPrev_, address newPrev_, uint256 radius_) external {
        require(quoteToken().balanceOf(msg.sender) * quoteTokenScale >= maxAmount_, "S:R:INSUF_BAL");

        Borrower memory borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "S:R:NO_DEBT");

        uint256 curDebt = _accruePoolInterest();
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(borrower.debt, borrower.inflatorSnapshot, inflatorSnapshot);

        uint256 amount = Maths.min(borrower.debt, maxAmount_);
        borrower.debt -= amount;

        uint256 curLenderDebt = lenderDebt;

        curLenderDebt -= Maths.min(curLenderDebt, Maths.wmul(Maths.wdiv(curLenderDebt, curDebt), amount));
        curDebt       -= amount;

        borrowerDebt = curDebt;
        lenderDebt   = curLenderDebt;

        if (borrower.debt == 0) {
            _removeLoanQueue(msg.sender, oldPrev_);
            delete borrowers[msg.sender];
        } else {
            _updateLoanQueue(msg.sender, Maths.wdiv(borrower.debt, borrower.collateral), oldPrev_, newPrev_, radius_);
            borrowers[msg.sender] = borrower;
        }

        uint256 newLup = _lup();
        _updateInterestRate(curDebt, newLup);

        // move amount to repay from sender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
        emit Repay(msg.sender, newLup, amount);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function purchaseQuote(uint256 amount_, uint256 index_) external {
        require(_rangeSum(index_, index_) >= amount_, "S:P:INSUF_QUOTE");

        uint256 curDebt = _accruePoolInterest();

        uint256 price = _indexToPrice(index_);
        uint256 collateralRequired = Maths.wdiv(amount_, price);
        require(collateral().balanceOf(msg.sender) >= collateralRequired, "S:P:INSUF_COL");

        _remove(index_, amount_);
        buckets[index_].availableCollateral += collateralRequired;

        _updateInterestRate(curDebt, _lup());

        // move required collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), collateralRequired / collateralScale);
        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Purchase(msg.sender, price, amount_, collateralRequired);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _accruePoolInterest() internal returns (uint256 curDebt_) {
        curDebt_ = borrowerDebt;
        if (curDebt_ != 0) {
            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            if (elapsed != 0 ) {
                uint256 spr             = interestRate / SECONDS_PER_YEAR;
                uint256 curInflator     = inflatorSnapshot;
                uint256 pendingInflator = Maths.wmul(curInflator, Maths.wpow(Maths.WAD + spr, elapsed));

                uint256 newHtp = _htp();
                if (newHtp != 0) {
                    uint256 htpIndex        = _priceToIndex(newHtp);
                    uint256 depositAboveHtp = _prefixSum(htpIndex);

                    if (depositAboveHtp != 0) {
                        uint256 newInterest  = Maths.wmul(lenderInterestFactor, Maths.wmul(pendingInflator - Maths.WAD, curDebt_));
                        uint256 lenderFactor = Maths.wdiv(newInterest, depositAboveHtp) + Maths.WAD;

                        _mult(htpIndex, lenderFactor);
                    }
                }

                curDebt_ = Maths.wmul(curDebt_, Maths.wdiv(pendingInflator, curInflator));
                borrowerDebt = curDebt_;

                inflatorSnapshot           = pendingInflator;
                lastInflatorSnapshotUpdate = block.timestamp;
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
            if (_poolCollateralization(curDebt_, col, lup_) != Maths.WAD) {
                uint256 oldRate = interestRate;

                uint256 curDebtEma   = Maths.wmul(curDebt_, EMA_RATE_FACTOR) + Maths.wmul(debtEma, LAMBDA_EMA);
                uint256 curLupColEma = Maths.wmul(Maths.wmul(lup_, col), EMA_RATE_FACTOR) + Maths.wmul(lupColEma, LAMBDA_EMA);

                int256 actualUtilization = int256(_poolActualUtilization(curDebt_, col));
                int256 targetUtilization = int256(Maths.wdiv(curDebtEma, curLupColEma));

                int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
                int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

                if (decreaseFactor < increaseFactor - 10**18) {
                    interestRate = Maths.wmul(interestRate, RATE_INCREASE_COEFFICIENT);
                } else if (decreaseFactor > 10**18 - increaseFactor) {
                    interestRate = Maths.wmul(interestRate, RATE_DECREASE_COEFFICIENT);
                }

                debtEma   = curDebtEma;
                lupColEma = curLupColEma;

                interestRateUpdate = block.timestamp;

                emit UpdateInterestRate(oldRate, interestRate);
            }
        }
    }

    function _borrowerCollateralization(uint256 debt_, uint256 collateral_, uint256 price_) internal pure returns (uint256 collateralization_) {
        uint256 encumberedCollateral = price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
        collateralization_ = collateral_ != 0 && encumberedCollateral != 0 ? Maths.wdiv(collateral_, encumberedCollateral) : Maths.WAD;
    }

    function _poolCollateralizationAtPrice(
        uint256 borrowerDebt_, uint256 additionalDebt_, uint256 collateral_, uint256 price_
    ) internal pure returns (uint256 collateralization_) {
        uint256 encumbered = Maths.wdiv(borrowerDebt_ + additionalDebt_, price_);
        collateralization_ = encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
    }

    function _poolCollateralization(uint256 borrowerDebt_, uint256 pledgedCollateral_, uint256 lup_) internal pure returns (uint256 collateralization_) {
        uint256 encumbered = Maths.wdiv(borrowerDebt_, lup_);
        collateralization_ = encumbered != 0 ? Maths.wdiv(pledgedCollateral_, encumbered) : Maths.WAD;
    }

    function _poolTargetUtilization(uint256 debtEma_, uint256 lupColEma_) internal pure returns (uint256) {
        if (debtEma_ != 0 && lupColEma_ != 0) {
            return Maths.wdiv(debtEma_, lupColEma_);
        }
        return Maths.WAD;
    }

    function _poolActualUtilization(uint256 borrowerDebt_, uint256 pledgedCollateral_) internal view returns (uint256 utilization_) {
        uint256 ptpIndex = _priceToIndex(Maths.wdiv(borrowerDebt_, pledgedCollateral_));
        if (ptpIndex != 0) utilization_ = Maths.wdiv(borrowerDebt_, _prefixSum(ptpIndex));
    }

    function _htp() internal view returns (uint256) {
        if (loanQueueHead != address(0)) {
            return loans[loanQueueHead].thresholdPrice;
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

    function _lup() internal view returns (uint256) {
        return _indexToPrice(_lupIndex(0));
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function lup() external view returns (uint256) {
        return _lup();
    }

    function lupIndex() external view returns (uint256) {
        return _lupIndex(0);
    }

    function htp() external view returns (uint256) {
        return _htp();
    }

    function priceToIndex(uint256 price_) external pure returns (uint256) {
        return _priceToIndex(price_);
    }

    function poolCollateralization() external view returns (uint256) {
        return _poolCollateralization(borrowerDebt, pledgedCollateral, _lup());
    }

    function borrowerInfo(address borrower_) external view returns (uint256, uint256, uint256) {
        return (borrowers[borrower_].debt, borrowers[borrower_].collateral, borrowers[borrower_].inflatorSnapshot);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function collateral() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0));
    }

    /**
     *  @dev Pure function used to facilitate accessing token via clone state.
     */
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }
}