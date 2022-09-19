// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { Clone }          from "@clones/Clone.sol";
import { ERC20 }          from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Burnable }  from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import { SafeERC20 }      from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Multicall }      from "@openzeppelin/contracts/utils/Multicall.sol";
import { PRBMathSD59x18 } from "@prb-math/contracts/PRBMathSD59x18.sol";
import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { IScaledPool }    from "./interfaces/IScaledPool.sol";

import { FenwickTree }    from "./FenwickTree.sol";

import { BucketMath }     from "../libraries/BucketMath.sol";
import { Maths }          from "../libraries/Maths.sol";
import { Heap }           from "../libraries/Heap.sol";
import '../libraries/Book.sol';
import '../libraries/Lenders.sol';

abstract contract ScaledPool is Clone, FenwickTree, Multicall, IScaledPool {
    using SafeERC20 for ERC20;
    using Book      for mapping(uint256 => Book.Bucket);
    using Lenders   for mapping(uint256 => mapping(address => Lenders.Lender));
    using Heap      for Heap.Data;

    int256  public constant INDEX_OFFSET = 3232;

    uint256 public constant WAD_WEEKS_PER_YEAR  = 52 * 10**18;
    uint256 public constant MINUTE_HALF_LIFE    = 0.988514020352896135_356867505 * 1e27;  // 0.5^(1/60)
    uint256 public constant CUBIC_ROOT_100      = 4.641588833612778892 * 1e18;
    uint256 public constant ONE_THIRD           = 0.333333333333333334 * 1e18;

    uint256 public constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 public constant DECREASE_COEFFICIENT = 0.9 * 10**18;

    uint256 public constant LAMBDA_EMA_7D        = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 public constant EMA_7D_RATE_FACTOR   = 1e18 - LAMBDA_EMA_7D;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override inflatorSnapshot;           // [WAD]
    uint256 public override lastInflatorSnapshotUpdate; // [SEC]
    uint256 public override minFee;                     // [WAD]
    uint256 public override interestRate;               // [WAD]
    uint256 public override interestRateUpdate;         // [SEC]

    uint256 public override borrowerDebt;               // [WAD]
    uint256 public override liquidationBondEscrowed;    // [WAD]
    uint256 public override quoteTokenScale;
    uint256 public override pledgedCollateral;

    uint256 public override debtEma;      // [WAD]
    uint256 public override lupColEma;    // [WAD]

    /**
     *  @notice Mapping of buckets for a given pool
     *  @dev    deposit index -> bucket
     */
    mapping(uint256 => Book.Bucket) public override buckets;

    /**
     *  @dev deposit index -> lender address -> lender lp [RAY] and deposit timestamp
     */
    mapping(uint256 => mapping(address => Lenders.Lender)) public override lenders;
    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => Borrower) public override borrowers;

    /**
     *  @notice Used for tracking LP token ownership address for transferLPTokens access control
     *  @dev    owner address -> new owner address -> deposit index -> allowed amount
     */
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances;

    /**
     *  @notice Address of the Ajna token, needed for Claimable Reserve Auctions.
     */
    address internal ajnaTokenAddress;

    Heap.Data internal loans;

    uint256 internal poolInitializations;

    /**
     *  @notice Time a Claimable Reserve Auction was last kicked.
     */
    uint256 internal reserveAuctionKicked;

    /**
     *  @notice Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
     */
    uint256 internal reserveAuctionUnclaimed;


    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        uint256 curDebt = _accruePoolInterest();

        bucketLPs_ = buckets.quoteTokensToLPs(
            index_,
            _valueAt(index_),
            quoteTokenAmountToAdd_
        );

        _add(index_, quoteTokenAmountToAdd_);

        lenders.deposit(index_, msg.sender, bucketLPs_);
        buckets.addLPs(index_, bucketLPs_);

        uint256 newLup = _lup();
        _updateInterestRateAndEMAs(curDebt, newLup);

        // move quote token amount from lender to pool
        emit AddQuoteToken(msg.sender, index_, quoteTokenAmountToAdd_, newLup);
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenAmountToAdd_ / quoteTokenScale);
    }

    function approveLpOwnership(
        address allowedNewOwner_,
        uint256 index_,
        uint256 lpsAmountToApprove_
    ) external {
        _lpTokenAllowances[msg.sender][allowedNewOwner_][index_] = lpsAmountToApprove_;
    }

    function moveQuoteToken(
        uint256 maxQuoteTokenAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        if (fromIndex_ == toIndex_) revert MoveQuoteToSamePrice();

        uint256 curDebt = _accruePoolInterest();

        (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = lenders.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        uint256 quoteTokenAmountToMove;
        (quoteTokenAmountToMove, fromBucketLPs_, ) = buckets.lpsToQuoteToken(
            fromIndex_,
            _valueAt(fromIndex_),
            lenderLpBalance,
            maxQuoteTokenAmountToMove_
        );

        _remove(fromIndex_, quoteTokenAmountToMove);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        quoteTokenAmountToMove = Lenders.applyEarlyWithdrawalPenalty(
            _calculateFeeRate(),
            lenderLastDepositTime,
            curDebt,
            pledgedCollateral,
            fromIndex_,
            toIndex_,
            quoteTokenAmountToMove
        );

        toBucketLPs_ = buckets.quoteTokensToLPs(
            toIndex_,
            _valueAt(toIndex_),
            quoteTokenAmountToMove
        );

        _add(toIndex_, quoteTokenAmountToMove);

        uint256 newLup = _lup(); // move lup if necessary and check loan book's htp against new lup
        if (fromIndex_ < toIndex_) if(_htp() > newLup) revert MoveQuoteLUPBelowHTP();

        // update lender accounting
        lenders.removeLPs(fromIndex_, msg.sender, toBucketLPs_); // TODO check why moving toBucketLPs_ instead fromBucketLPs_
        lenders.addLPs(toIndex_, msg.sender, toBucketLPs_);
        // update buckets
        buckets.removeLPs(fromIndex_, fromBucketLPs_);
        buckets.addLPs(toIndex_, toBucketLPs_);

        _updateInterestRateAndEMAs(curDebt, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, quoteTokenAmountToMove, newLup);
    }

    function removeAllQuoteToken(
        uint256 index_
    ) external returns (uint256 quoteTokenAmountRemoved_, uint256 redeemedLenderLPs_) {
        // scale the tree, accumulating interest owed to lenders
        _accruePoolInterest();

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(
            index_,
            msg.sender
        );
        if (lenderLPsBalance == 0) revert RemoveQuoteNoClaim();

        uint256 deposit = _valueAt(index_);
        (quoteTokenAmountRemoved_, , redeemedLenderLPs_) = buckets.lpsToQuoteToken(
            index_,
            deposit,
            lenderLPsBalance,
            deposit
        );

        _redeemLPForQuoteToken(redeemedLenderLPs_, quoteTokenAmountRemoved_, index_);
    }

    function removeQuoteToken(
        uint256 quoteTokenAmountToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        // scale the tree, accumulating interest owed to lenders
        _accruePoolInterest();

        uint256 deposit = _valueAt(index_);
        if (quoteTokenAmountToRemove_ > deposit) revert RemoveQuoteInsufficientQuoteAvailable();

        bucketLPs_ = buckets.quoteTokensToLPs(
            index_,
            deposit,
            quoteTokenAmountToRemove_
        );

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        if (lenderLPsBalance == 0 || bucketLPs_ > lenderLPsBalance) revert RemoveQuoteInsufficientLPB();

        _redeemLPForQuoteToken(bucketLPs_, quoteTokenAmountToRemove_, index_);
    }

    function borrow(
        uint256 amountToBorrow_,
        uint256 limitIndex_
    ) external override {
        uint256 lupId = _lupIndex(amountToBorrow_);
        if (lupId > limitIndex_) revert BorrowLimitIndexReached();

        uint256 curDebt = _accruePoolInterest();

        Borrower memory borrower = borrowers[msg.sender];
        if (loans.count - 1 != 0) if (borrower.debt + amountToBorrow_ < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();

        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(
            borrower.debt,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );

        uint256 debt  = Maths.wmul(amountToBorrow_, _calculateFeeRate() + Maths.WAD);
        borrower.debt += debt;

        uint256 newLup = Book.indexToPrice(lupId);

        // check borrow won't push borrower or pool into a state of under-collateralization
        if (_borrowerCollateralization(borrower.debt, borrower.collateral, newLup) < Maths.WAD) revert BorrowBorrowerUnderCollateralized();
        if (_poolCollateralizationAtPrice(curDebt, debt, pledgedCollateral, newLup) < Maths.WAD) revert BorrowPoolUnderCollateralized();

        curDebt += debt;

        // update actor accounting
        borrowerDebt = curDebt;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(
            borrower.debt,
            borrower.collateral,
            borrower.inflatorSnapshot
        );
        loans.upsert(msg.sender, thresholdPrice);

        borrower.mompFactor = _mompFactor(borrower.inflatorSnapshot);
        borrowers[msg.sender] = borrower;

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amountToBorrow_);
        quoteToken().safeTransfer(msg.sender, amountToBorrow_ / quoteTokenScale);
    }

    function repay(
        address borrower_,
        uint256 maxQuoteTokenAmountToRepay_
    ) external override {
        _repayDebt(borrower_, maxQuoteTokenAmountToRepay_);
    }

    function transferLPTokens(
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_)
    external {
        uint256 tokensTransferred;
        uint256 indexesLength = indexes_.length;

        for (uint256 i = 0; i < indexesLength; ) {
            if (!BucketMath.isValidIndex(Book.indexToBucketIndex(indexes_[i]))) revert TransferLPInvalidIndex();

            uint256 transferAmount = _lpTokenAllowances[owner_][newOwner_][indexes_[i]];
            if (transferAmount == 0) revert TransferLPNoAllowance();

            (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = lenders.getLenderInfo(
                indexes_[i],
                owner_
            );
            if (transferAmount != lenderLpBalance) revert TransferLPNoAllowance();

            delete _lpTokenAllowances[owner_][newOwner_][indexes_[i]]; // delete allowance

            lenders.transferLPs(
                indexes_[i],
                owner_,
                newOwner_,
                transferAmount,
                lenderLastDepositTime
            );

            tokensTransferred += transferAmount;

            unchecked {
                ++i;
            }
        }

        emit TransferLPTokens(owner_, newOwner_, indexes_, tokensTransferred);
    }


    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function startClaimableReserveAuction() external override {
        uint256 claimable = _claimableReserves();
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        reserveAuctionUnclaimed += claimable - kickerAward;
        if (reserveAuctionUnclaimed == 0) revert KickNoReserves();

        reserveAuctionKicked = block.timestamp;
        emit ReserveAuction(reserveAuctionUnclaimed, _reserveAuctionPrice());
        quoteToken().safeTransfer(msg.sender, kickerAward / quoteTokenScale);
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 kicked = reserveAuctionKicked;
        if (kicked == 0 || block.timestamp - kicked > 72 hours) revert NoAuction();

        amount_ = Maths.min(reserveAuctionUnclaimed, maxAmount_);
        uint256 price = _reserveAuctionPrice();
        uint256 ajnaRequired = Maths.wmul(amount_, price);
        reserveAuctionUnclaimed -= amount_;

        emit ReserveAuction(reserveAuctionUnclaimed, price);
        ERC20(ajnaTokenAddress).safeTransferFrom(msg.sender, address(this), ajnaRequired);
        ERC20Burnable(ajnaTokenAddress).burn(ajnaRequired);
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
    }


    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _pledgeCollateral(
        address borrower_,
        uint256 collateralAmountToPledge_
    ) internal {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[borrower_];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(
            borrower.debt,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
        borrower.collateral += collateralAmountToPledge_;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(
            borrower.debt,
            borrower.collateral,
            borrower.inflatorSnapshot
        );
        if (borrower.debt != 0) loans.upsert(borrower_, thresholdPrice);

        uint256 newLup = _lup();
        borrower.mompFactor = _mompFactor(borrower.inflatorSnapshot);
        borrowers[borrower_] = borrower;

        pledgedCollateral += collateralAmountToPledge_;
        _updateInterestRateAndEMAs(curDebt, newLup);
    }

    function _pullCollateral(
        uint256 collateralAmountToPull_
    ) internal {
        uint256 curDebt = _accruePoolInterest();

        // borrower accounting
        Borrower memory borrower = borrowers[msg.sender];
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(
            borrower.debt,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );

        uint256 curLup = _lup();
        if (borrower.collateral - _encumberedCollateral(borrower.debt, curLup) < collateralAmountToPull_) revert RemoveCollateralInsufficientCollateral();
        borrower.collateral -= collateralAmountToPull_;

        // update loan queue
        uint256 thresholdPrice = _t0ThresholdPrice(
            borrower.debt,
            borrower.collateral,
            borrower.inflatorSnapshot
        );
        if (borrower.debt != 0) loans.upsert(msg.sender, thresholdPrice);

        borrower.mompFactor = _mompFactor(borrower.inflatorSnapshot);
        borrowers[msg.sender] = borrower;

        // update pool state
        pledgedCollateral -= collateralAmountToPull_;
        _updateInterestRateAndEMAs(curDebt, curLup);
    }

    function _repayDebt(
        address borrower_,
        uint256 maxQuoteTokenAmountToRepay_
    ) internal {
        Borrower memory borrower = borrowers[borrower_];
        if (borrower.debt == 0) revert RepayNoDebt();

        uint256 curDebt = _accruePoolInterest();

        // update borrower accounting
        (borrower.debt, borrower.inflatorSnapshot) = _accrueBorrowerInterest(
            borrower.debt,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
        uint256 amount = Maths.min(borrower.debt, maxQuoteTokenAmountToRepay_);
        borrower.debt -= amount;
        curDebt       -= amount;

        // update loan queue
        if (borrower.debt == 0) {
            loans.remove(borrower_);
        } else {
            if (loans.count - 1 != 0) if (borrower.debt < _poolMinDebtAmount(curDebt)) revert BorrowAmountLTMinDebt();
            uint256 thresholdPrice = _t0ThresholdPrice(
                borrower.debt,
                borrower.collateral,
                borrower.inflatorSnapshot
            );
            loans.upsert(borrower_, thresholdPrice);
        }

        // update pool state
        borrowerDebt = curDebt;

        uint256 newLup = _lup();
        borrower.mompFactor = _mompFactor(borrower.inflatorSnapshot);
        borrowers[borrower_] = borrower;

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move amount to repay from sender to pool
        emit Repay(borrower_, newLup, amount);
        quoteToken().safeTransferFrom(msg.sender, address(this), amount / quoteTokenScale);
    }

    function _addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        uint256 curDebt = _accruePoolInterest();

        bucketLPs_ = buckets.collateralToLPs(
            index_,
            _valueAt(index_),
            collateralAmountToAdd_
        );

        lenders.addLPs(index_, msg.sender, bucketLPs_);
        buckets.addCollateral(index_, bucketLPs_, collateralAmountToAdd_);

        _updateInterestRateAndEMAs(curDebt, _lup());
    }

    function _removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        if (collateralAmountToRemove_ > buckets.getCollateral(index_)) revert RemoveCollateralInsufficientCollateral();

        _accruePoolInterest();

        bucketLPs_ = buckets.collateralToLPs(
            index_,
            _valueAt(index_),
            collateralAmountToRemove_
        );

        (uint256 lenderLpBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        if (lenderLpBalance == 0 || bucketLPs_ > lenderLpBalance) revert RemoveCollateralInsufficientLP(); // ensure user can actually remove that much

        lenders.removeLPs(index_, msg.sender, bucketLPs_);
        buckets.removeCollateral(index_, bucketLPs_, collateralAmountToRemove_);

        _updateInterestRateAndEMAs(borrowerDebt, _lup());
    }

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
                        uint256 netInterestMargin = _lenderInterestMargin(_poolActualUtilization(curDebt_, pledgedCollateral));
                        uint256 newInterest  = Maths.wmul(netInterestMargin, Maths.wmul(factor - Maths.WAD, curDebt_));
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

    function _auctionPrice(uint256 referencePrice, uint256 kickTime) internal view returns (uint256 price_) {
        uint256 elapsedHours = Maths.wdiv((block.timestamp - kickTime) * 1e18, 1 hours * 1e18);
        elapsedHours -= Maths.min(elapsedHours, 1e18);  // price locked during cure period

        int256 timeAdjustment = PRBMathSD59x18.mul(-1 * 1e18, int256(elapsedHours));
        price_ = 10 * Maths.wmul(referencePrice, uint256(PRBMathSD59x18.exp2(timeAdjustment)));
    }

    function _claimableReserves() internal view returns (uint256 claimable_) {
        claimable_ = Maths.wmul(0.995 * 1e18, borrowerDebt) + quoteToken().balanceOf(address(this));
        claimable_ -= Maths.min(claimable_, _treeSum() + liquidationBondEscrowed + reserveAuctionUnclaimed);
    }

    function _redeemLPForQuoteToken(
        uint256 lpAmount_,
        uint256 amount,
        uint256 index_
    ) internal {
        _remove(index_, amount);  // update FenwickTree

        uint256 newLup = _lup();
        if (_htp() > newLup) revert RemoveQuoteLUPBelowHTP();

        // persist bucket changes
        buckets.removeLPs(index_, lpAmount_);
        lenders.removeLPs(index_,msg.sender, lpAmount_);

        (, uint256 lastDeposit) = lenders.getLenderInfo(index_, msg.sender);
        uint256 curDebt = borrowerDebt;
        amount = Lenders.applyEarlyWithdrawalPenalty(
            _calculateFeeRate(),
            lastDeposit,
            curDebt,
            pledgedCollateral,
            index_,
            0,
            amount
        );

        _updateInterestRateAndEMAs(curDebt, newLup);

        // move quote token amount from pool to lender
        emit RemoveQuoteToken(msg.sender, index_, amount, newLup);
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
    }

    function _updateInterestRateAndEMAs(uint256 curDebt_, uint256 lup_) internal {
        if (block.timestamp - interestRateUpdate > 12 hours) {
            // Update EMAs for target utilization
            uint256 col = pledgedCollateral;

            uint256 curDebtEma   = Maths.wmul(curDebt_,              EMA_7D_RATE_FACTOR) + Maths.wmul(debtEma,   LAMBDA_EMA_7D);
            uint256 curLupColEma = Maths.wmul(Maths.wmul(lup_, col), EMA_7D_RATE_FACTOR) + Maths.wmul(lupColEma, LAMBDA_EMA_7D);

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

    function _hpbIndex() internal view returns (uint256) {
        return _findIndexOfSum(1);
    }

    function _htp() internal view returns (uint256) {
        return Maths.wmul(loans.getMax().val, inflatorSnapshot);
    }

    function _lupIndex(uint256 additionalDebt_) internal view returns (uint256) {
        return _findIndexOfSum(borrowerDebt + additionalDebt_);
    }

    function _priceToIndex(uint256 price_) internal pure returns (uint256) {
        return uint256(7388 - (BucketMath.priceToIndex(price_) + 3232));
    }

    function _poolMinDebtAmount(uint256 debt_) internal view returns (uint256) {
        return Maths.wdiv(Maths.wdiv(debt_, Maths.wad(loans.count - 1)), 10**19);
    }

    function _lup() internal view returns (uint256) {
        return Book.indexToPrice(_lupIndex(0));
    }

    function _calculateFeeRate() internal view returns (uint256) {
        // greater of the current annualized interest rate divided by 52 (one week of interest) or 5 bps
        return Maths.max(Maths.wdiv(interestRate, WAD_WEEKS_PER_YEAR), minFee);
    }

    function _pendingInterestFactor(uint256 elapsed_) internal view returns (uint256) {
        return PRBMathUD60x18.exp((interestRate * elapsed_) / 365 days);
    }

    function _pendingInflator() internal view returns (uint256) {
        return Maths.wmul(inflatorSnapshot, _pendingInterestFactor(block.timestamp - lastInflatorSnapshotUpdate));
    }

    function _t0ThresholdPrice(uint256 debt_, uint256 collateral_, uint256 inflator_) internal pure returns (uint256 tp_) {
        if (collateral_ != 0) tp_ = Maths.wdiv(Maths.wdiv(debt_, inflator_), collateral_);
    }

    function _reserveAuctionPrice() internal view returns (uint256 _price) {
        if (reserveAuctionKicked != 0) {
            uint256 secondsElapsed = block.timestamp - reserveAuctionKicked;
            uint256 hoursComponent = 1e27 >> secondsElapsed / 3600;
            uint256 minutesComponent = Maths.rpow(MINUTE_HALF_LIFE, secondsElapsed % 3600 / 60);
            _price = Maths.rayToWad(1_000_000_000 * Maths.rmul(hoursComponent, minutesComponent));
        }
    }

    function _mompFactor(uint256 inflator) internal view returns (uint256 momFactor_) {
        uint256 numLoans = loans.count - 1;
        if (numLoans != 0) momFactor_ = Maths.wdiv(Book.indexToPrice(_findIndexOfSum(Maths.wdiv(borrowerDebt, numLoans * 1e18))), inflator);
    }

    /**
     *  @notice Returns the proportion of interest rate which is awarded to lenders;
     *          the remainder accumulates in reserves.
    */
    function _lenderInterestMargin(uint256 mau) internal view returns (uint256) {
        // TODO: Consider pre-calculating and storing a conversion table in a library or shared contract.
        // cubic root of the percentage of meaningful unutilized deposit
        uint256 crpud = PRBMathUD60x18.pow(100 * 1e18 - Maths.wmul(Maths.min(mau, 1e18), 100 * 1e18), ONE_THIRD);
        return 1e18 - Maths.wmul(Maths.wdiv(crpud, CUBIC_ROOT_100), 0.15 * 1e18);
    }


    /**************************/
    /*** External Functions ***/
    /**************************/

    // TODO: Temporarily here for unit testing; move to accessor method when merging with current implementation.
    function auctionPrice(
        uint256 referencePrice_,
        uint256 kickTime_
    ) external view returns (uint256) {
        return _auctionPrice(referencePrice_, kickTime_);
    }

    function borrowerCollateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) external pure override returns (uint256) {
        return _borrowerCollateralization(debt_, collateral_, price_);
    }

    function bucketAt(uint256 index_)
        external
        view
        override
        returns (
            uint256 price_,
            uint256 quoteTokens_,
            uint256 collateral_,
            uint256 bucketLPs_,
            uint256 scale_,
            uint256 exchangeRate_,
            uint256 liquidityToPrice_
        )
    {
        price_             = Book.indexToPrice(index_);
        quoteTokens_       = _valueAt(index_);           // quote token in bucket, deposit + interest (WAD)
        collateral_        = buckets[index_].collateral; // unencumbered collateral in bucket (WAD)
        bucketLPs_         = buckets[index_].lps;        // outstanding LP balance (WAD)
        scale_             = _scale(index_);             // lender interest multiplier (WAD)
        exchangeRate_      = buckets.getExchangeRate(index_, quoteTokens_);
        liquidityToPrice_  = _prefixSum(index_);
    }

    function borrowerInfo(address borrower_)
        external
        view
        override
        returns (
            uint256 debt_,            // accrued debt (WAD)
            uint256 pendingDebt_,     // current debt, accrued and pending accrual (WAD)
            uint256 collateral_,      // deposited collateral including encumbered (WAD)
            uint256 mompFactor_,      // MOMP / inflator, used in neutralPrice calc (WAD)
            uint256 inflatorSnapshot_ // used to calculate pending interest (WAD)
        )
    {
        debt_             = borrowers[borrower_].debt;
        pendingDebt_      = Maths.wmul(borrowers[borrower_].debt, Maths.wdiv(_pendingInflator(), inflatorSnapshot));
        collateral_       = borrowers[borrower_].collateral;
        mompFactor_       = borrowers[borrower_].mompFactor;
        inflatorSnapshot_ = borrowers[borrower_].inflatorSnapshot;
    }

    function encumberedCollateral(
        uint256 debt_,
        uint256 price_
    ) external pure override returns (uint256) {
        return _encumberedCollateral(debt_, price_);
    }

    function lpsToQuoteTokens(
        uint256 deposit_,
        uint256 lpTokens_,
        uint256 index_
    ) external view override returns (uint256 quoteTokenAmount_) {
        (quoteTokenAmount_, , ) = buckets.lpsToQuoteToken(
            index_,
            deposit_,
            lpTokens_,
            deposit_
        );
    }

    function poolLoansInfo()
        external
        view
        override
        returns (
            uint256 poolSize_,
            uint256 loansCount_,
            address maxBorrower_,
            uint256 pendingInflator_
        )
    {
        poolSize_        = _treeSum();
        loansCount_      = loans.count - 1;
        maxBorrower_     = loans.getMax().id;
        pendingInflator_ = _pendingInflator();
    }

    function poolPricesInfo()
        external
        view
        override
        returns (
            uint256 hpb_,
            uint256 htp_,
            uint256 lup_,
            uint256 lupIndex_
        )
    {
        hpb_ = Book.indexToPrice(_hpbIndex());
        htp_ = _htp();
        lupIndex_ = _lupIndex(0);
        lup_ = Book.indexToPrice(lupIndex_);
    }

    function poolReservesInfo()
        external
        view
        override
        returns (
            uint256 reserves_,
            uint256 claimableReserves_,
            uint256 claimableReservesRemaining_,
            uint256 auctionPrice_,
            uint256 timeRemaining_
        )
    {
        reserves_ = borrowerDebt
            + quoteToken().balanceOf(address(this))
            - _treeSum()
            - liquidationBondEscrowed
            - reserveAuctionUnclaimed;
        claimableReserves_ = _claimableReserves();

        claimableReservesRemaining_ = reserveAuctionUnclaimed;
        auctionPrice_               = _reserveAuctionPrice();
        timeRemaining_              = 3 days - Maths.min(3 days, block.timestamp - reserveAuctionKicked);
    }

    function poolUtilizationInfo()
        external
        view
        override
        returns (
            uint256 poolMinDebtAmount_,
            uint256 poolCollateralization_,
            uint256 poolActualUtilization_,
            uint256 poolTargetUtilization_
        )
    {
        if (borrowerDebt != 0) poolMinDebtAmount_ = _poolMinDebtAmount(borrowerDebt);
        poolCollateralization_ = _poolCollateralization(borrowerDebt, pledgedCollateral, _lup());
        poolActualUtilization_  = _poolActualUtilization(borrowerDebt, pledgedCollateral);
        poolTargetUtilization_  = _poolTargetUtilization(debtEma, lupColEma);
    }

    function priceToIndex(uint256 price_) external pure override returns (uint256) {
        return _priceToIndex(price_);
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
