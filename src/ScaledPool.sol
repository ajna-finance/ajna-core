// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { BorrowerQueue }    from "./BorrowerQueue.sol";
import { FenwickTree } from "./FenwickTree.sol";

import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";

contract ScaledPool is BorrowerQueue, Clone, FenwickTree {
    using SafeERC20 for ERC20;

    /**************/
    /*** Events ***/
    /**************/

    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);

    event AddCollateral(address indexed borrower_, uint256 amount_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);

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

    int256  public constant INDEX_OFFSET       = 3232;
    uint256 public constant WAD_WEEKS_PER_YEAR = 52 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public inflatorSnapshot;           // [RAY]
    uint256 public lastInflatorSnapshotUpdate; // [SEC]
    uint256 public minFee;                     // [WAD]
    uint256 public lenderInterestFactor;       // WAD
    uint256 public interestRate;               // [WAD]

    uint256 public lenderDebt;
    uint256 public borrowerDebt;

    uint256 public collateralScale;
    uint256 public quoteTokenScale;

    uint256 public depositAccumulator;

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
        minFee                     = 0.0005 * 10**18;

        // initialize Fenwick scale array with elements of 1
        uint256[] memory scaleArray = new uint256[](8193);
        for (uint256 i; i < 8193;) {
            scaleArray[i] = Maths.WAD;
            unchecked {
                ++i;
            }
        }
        _s = scaleArray;
        _n = 8192;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(uint256 amount_, uint256 index_) external returns (uint256 lpbChange_) {
        _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        uint256 bucketSize    = _rangeSum(index_, index_);
        uint256 exchangeRate  = bucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, bucket.lpAccumulator) : Maths.WAD;

        lpbChange_            = Maths.wdiv(amount_, exchangeRate);
        bucket.lpAccumulator  += lpbChange_;

        lpBalance[index_][msg.sender] += lpbChange_;

        _add(index_, amount_);
        depositAccumulator += amount_;

        // move quote token amount from lender to pool
        quoteToken().safeTransferFrom(msg.sender, address(this), amount_ / quoteTokenScale);
        emit AddQuoteToken(msg.sender, _indexToPrice(index_), amount_, _lup());
    }

    function removeQuoteToken(uint256 lpbAmount_, uint256 index_) external {
        uint256 availableLPs = lpBalance[index_][msg.sender];
        require(availableLPs != 0 && availableLPs < lpbAmount_, "S:RQT:INSUF_LPS");

        _accruePoolInterest();

        Bucket storage bucket = buckets[index_];
        bucket.lpAccumulator  -= lpbAmount_;
        uint256 bucketSize    = _rangeSum(index_, index_);
        uint256 exchangeRate  = bucket.lpAccumulator != 0 ? Maths.wdiv(bucketSize, bucket.lpAccumulator) : Maths.WAD;
        uint256 amount        = Maths.wmul(lpbAmount_, exchangeRate);

        lpBalance[index_][msg.sender] -= lpbAmount_;

        // Calculate new LUP, revert if LUP would dip below HTP
        uint256 newLup = BucketMath.indexToPrice(int256(_lupIndex(amount)) - INDEX_OFFSET);
        require(_htp() <= newLup, "S:RQT:BAD_LUP");

        _remove(index_, amount);
        depositAccumulator -= amount;

        // move quote token amount from pool to lender
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
        emit RemoveQuoteToken(msg.sender, _indexToPrice(index_), amount, newLup);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function addCollateral(uint256 amount_) external {
        _accruePoolInterest();

        // borrower accounting
        Borrower storage borrower = borrowers[msg.sender];
        _accrueBorrowerInterest(borrower);
        borrower.collateral += amount_;

        // move collateral from sender to pool
        collateral().safeTransferFrom(msg.sender, address(this), amount_ / collateralScale);
        emit AddCollateral(msg.sender, amount_);
    }

    function borrow(uint256 amount_, address oldPrevBorrower_, address newPrevBorrower_) external {
        _accruePoolInterest();

        Borrower storage borrower = borrowers[msg.sender];
        _accrueBorrowerInterest(borrower);

        uint256 fee          = Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
        uint256 borrowerDebt = Maths.wmul(amount_, fee);
        borrower.debt        += borrowerDebt;

        uint256 lup = BucketMath.indexToPrice(int256(_lupIndex(amount_)) - INDEX_OFFSET);
        require(_borrowerCollateralization(borrower.debt, borrower.collateral, lup) >= Maths.WAD, "S:B:BORROWER_UNDER_COLLAT");
        // TODO Ensure loan wouldn't make the pool undercollateralized.

        borrowerDebt       += borrowerDebt;
        lenderDebt         += amount_;
        depositAccumulator -= amount_;

        _updateLoanQueue(msg.sender, Maths.wdiv(borrower.debt, borrower.collateral), oldPrevBorrower_, newPrevBorrower_);

        // move borrowed amount from pool to sender
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
        emit Borrow(msg.sender, lup, amount_);
    }

    function _accruePoolInterest() internal {
        // TODO implement, is this calculated differently than in v8 version?
    }

    function _accrueBorrowerInterest(Borrower storage borrower_) internal {
        if (borrower_.debt != 0 && borrower_.inflatorSnapshot != 0) {
            borrower_.debt = Maths.wmul(borrower_.debt, Maths.wdiv(inflatorSnapshot, borrower_.inflatorSnapshot));
        }
        borrower_.inflatorSnapshot = inflatorSnapshot;
    }

    function _borrowerCollateralization(uint256 debt_, uint256 collateral_, uint256 price_) internal returns (uint256 collateralization_) {
        uint256 encumberedCollateral = price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
        collateralization_ = collateral_ != 0 && encumberedCollateral != 0 ? Maths.wdiv(collateral_, encumberedCollateral) : Maths.WAD;
    }

    function _htp() internal view returns (uint256) {
        if (head != address(0)) {
            return loans[head].thresholdPrice;
        }
        return 0;
    }

    function _lupIndex(uint256 additionalDebt_) public view returns (uint256) {
        return _findSum(lenderDebt + additionalDebt_);
    }

    function _indexToPrice(uint256 index_) internal view returns (uint256) {
        return BucketMath.indexToPrice(int256(index_) - 3232);
    }

    function _lup() internal view returns (uint256) {
        return _indexToPrice(_lupIndex(0));
    }

    function lup() external view returns (uint256) {
        return _lup();
    }

    function htp() external view returns (uint256) {
        return _htp();
    }

    function priceToIndex(uint256 price_) external view returns (uint256) {
        return uint256(BucketMath.priceToIndex(price_) + 3232);
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