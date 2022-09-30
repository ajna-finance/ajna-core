// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/IPool.sol';

import '../libraries/Maths.sol';
import '../libraries/Heap.sol';
import '../libraries/Book.sol';
import '../libraries/Actors.sol';
import '../libraries/PoolUtils.sol';

abstract contract Pool is Clone, Multicall, IPool {
    using SafeERC20 for ERC20;
    using Book      for mapping(uint256 => Book.Bucket);
    using Book      for Book.Deposits;
    using Actors    for mapping(uint256 => mapping(address => Actors.Lender));
    using Actors    for mapping(address => Actors.Borrower);
    using Heap      for Heap.Data;

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

    uint256 public override reserveAuctionKicked;    // Time a Claimable Reserve Auction was last kicked.
    uint256 public override reserveAuctionUnclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.

    mapping(uint256 => Book.Bucket)                       public override buckets;   // deposit index -> bucket
    mapping(uint256 => mapping(address => Actors.Lender)) public override lenders;   // deposit index -> lender address -> lender lp [RAY] and deposit timestamp
    mapping(address => Actors.Borrower)                   public override borrowers; // borrowers book: borrower address -> Borrower struct

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    address       internal ajnaTokenAddress; //  Address of the Ajna token, needed for Claimable Reserve Auctions.
    Book.Deposits internal deposits;
    Heap.Data     internal loans;

    uint256 internal poolInitializations;

    struct PoolState {
        uint256 accruedDebt;
        uint256 collateral;
        bool    isNewInterestAccrued;
        uint256 rate;
        uint256 inflator;
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addQuoteToken(
        uint256 quoteTokenAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        bucketLPs_ = buckets.quoteTokensToLPs(
            index_,
            deposits.valueAt(index_),
            quoteTokenAmountToAdd_
        );

        deposits.add(index_, quoteTokenAmountToAdd_);

        lenders.deposit(index_, msg.sender, bucketLPs_);
        buckets.addLPs(index_, bucketLPs_);

        uint256 newLup = _lup(poolState.accruedDebt);
        _updatePool(poolState, newLup);

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

        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = lenders.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        uint256 quoteTokenAmountToMove;
        (quoteTokenAmountToMove, fromBucketLPs_, ) = buckets.lpsToQuoteToken(
            fromIndex_,
            deposits.valueAt(fromIndex_),
            lenderLpBalance,
            maxQuoteTokenAmountToMove_
        );

        deposits.remove(fromIndex_, quoteTokenAmountToMove);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        quoteTokenAmountToMove = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState.rate,
            minFee,
            lenderLastDepositTime,
            poolState.accruedDebt,
            poolState.collateral,
            fromIndex_,
            toIndex_,
            quoteTokenAmountToMove
        );

        toBucketLPs_ = buckets.quoteTokensToLPs(
            toIndex_,
            deposits.valueAt(toIndex_),
            quoteTokenAmountToMove
        );

        deposits.add(toIndex_, quoteTokenAmountToMove);

        uint256 newLup = _lup(poolState.accruedDebt); // move lup if necessary and check loan book's htp against new lup
        if (fromIndex_ < toIndex_) if(_htp(poolState.inflator) > newLup) revert MoveQuoteLUPBelowHTP();

        // update lender accounting
        lenders.removeLPs(fromIndex_, msg.sender, fromBucketLPs_);
        lenders.addLPs(toIndex_, msg.sender, toBucketLPs_);
        // update buckets
        buckets.removeLPs(fromIndex_, fromBucketLPs_);
        buckets.addLPs(toIndex_, toBucketLPs_);

        _updatePool(poolState, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, quoteTokenAmountToMove, newLup);
    }

    function removeAllQuoteToken(
        uint256 index_
    ) external returns (uint256 quoteTokenAmountRemoved_, uint256 redeemedLenderLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(
            index_,
            msg.sender
        );
        if (lenderLPsBalance == 0) revert RemoveQuoteNoClaim();

        uint256 deposit = deposits.valueAt(index_);
        (quoteTokenAmountRemoved_, , redeemedLenderLPs_) = buckets.lpsToQuoteToken(
            index_,
            deposit,
            lenderLPsBalance,
            deposit
        );

        _redeemLPForQuoteToken(
            index_,
            poolState,
            redeemedLenderLPs_,
            quoteTokenAmountRemoved_
        );
    }

    function removeQuoteToken(
        uint256 quoteTokenAmountToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {

        PoolState memory poolState = _accruePoolInterest();

        uint256 deposit = deposits.valueAt(index_);
        if (quoteTokenAmountToRemove_ > deposit) revert RemoveQuoteInsufficientQuoteAvailable();

        bucketLPs_ = buckets.quoteTokensToLPs(
            index_,
            deposit,
            quoteTokenAmountToRemove_
        );

        (uint256 lenderLPsBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        if (lenderLPsBalance == 0 || bucketLPs_ > lenderLPsBalance) revert RemoveQuoteInsufficientLPB();

        _redeemLPForQuoteToken(
            index_,
            poolState,
            bucketLPs_,
            quoteTokenAmountToRemove_
        );
    }

    function transferLPTokens(
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_)
    external {
        uint256 tokensTransferred;
        uint256 indexesLength = indexes_.length;

        for (uint256 i = 0; i < indexesLength; ) {
            if (!Book.isDepositIndex(indexes_[i])) revert TransferLPInvalidIndex();

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


    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function borrow(
        uint256 amountToBorrow_,
        uint256 limitIndex_
    ) external override {

        PoolState memory poolState = _accruePoolInterest();

        uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
        if (lupId > limitIndex_) revert BorrowLimitIndexReached();

        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            msg.sender,
            poolState.inflator
        );
        uint256 loansCount = loans.count - 1;
        if (
            loansCount != 0
            &&
            (borrowerAccruedDebt + amountToBorrow_ < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
        )  revert BorrowAmountLTMinDebt();

        uint256 debt  = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate, minFee) + Maths.WAD);
        borrowerAccruedDebt += debt;

        uint256 newLup = PoolUtils.indexToPrice(lupId);

        // check borrow won't push borrower or pool into a state of under-collateralization
        if (
            PoolUtils.collateralization(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                newLup
            ) < Maths.WAD || borrowerPledgedCollateral == 0
        ) revert BorrowBorrowerUnderCollateralized();

        poolState.accruedDebt += debt;
        if (
            PoolUtils.collateralization(
                poolState.accruedDebt,
                poolState.collateral,
                newLup
            ) < Maths.WAD
        ) revert BorrowPoolUnderCollateralized();

        // update loan queue
        uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            poolState.inflator
        );
        loans.upsert(msg.sender, thresholdPrice);

        borrowers.update(
            msg.sender,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            deposits.mompFactor(poolState.inflator, poolState.accruedDebt, loans.count - 1),
            poolState.inflator
        );

        _updatePool(poolState, newLup);

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


    /*************************/
    /*** Buyback Functions ***/
    /*************************/

    function startClaimableReserveAuction() external override {
        uint256 curUnclaimedAuctionReserve = reserveAuctionUnclaimed;
        uint256 claimable = PoolUtils.claimableReserves(
            borrowerDebt,
            deposits.treeSum(),
            liquidationBondEscrowed,
            curUnclaimedAuctionReserve,
            quoteToken().balanceOf(address(this))
        );
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward;
        if (curUnclaimedAuctionReserve == 0) revert KickNoReserves();

        reserveAuctionUnclaimed = curUnclaimedAuctionReserve;
        reserveAuctionKicked    = block.timestamp;
        emit ReserveAuction(curUnclaimedAuctionReserve, PoolUtils.reserveAuctionPrice(block.timestamp));
        quoteToken().safeTransfer(msg.sender, kickerAward / quoteTokenScale);
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 kicked = reserveAuctionKicked;
        if (kicked == 0 || block.timestamp - kicked > 72 hours) revert NoAuction();

        amount_ = Maths.min(reserveAuctionUnclaimed, maxAmount_);
        uint256 price = PoolUtils.reserveAuctionPrice(kicked);
        uint256 ajnaRequired = Maths.wmul(amount_, price);
        reserveAuctionUnclaimed -= amount_;

        emit ReserveAuction(reserveAuctionUnclaimed, price);
        ERC20(ajnaTokenAddress).safeTransferFrom(msg.sender, address(this), ajnaRequired);
        ERC20Burnable(ajnaTokenAddress).burn(ajnaRequired);
        quoteToken().safeTransfer(msg.sender, amount_ / quoteTokenScale);
    }


    /***********************************/
    /*** Borrower Internal Functions ***/
    /***********************************/

    function _pledgeCollateral(
        address borrower_,
        uint256 collateralAmountToPledge_
    ) internal {

        PoolState memory poolState = _accruePoolInterest();

        // borrower accounting
        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            borrower_,
            poolState.inflator
        );
        borrowerPledgedCollateral += collateralAmountToPledge_;

        // update loan queue
        if (borrowerAccruedDebt != 0) {
            uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                poolState.inflator
            );
            loans.upsert(borrower_, thresholdPrice);
        }

        borrowers.update(
            borrower_,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            deposits.mompFactor(poolState.inflator, poolState.accruedDebt, loans.count - 1),
            poolState.inflator
        );

        poolState.collateral += collateralAmountToPledge_;
        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _pullCollateral(
        uint256 collateralAmountToPull_
    ) internal {

        PoolState memory poolState = _accruePoolInterest();

        // borrower accounting
        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            msg.sender,
            poolState.inflator
        );

        uint256 curLup = _lup(poolState.accruedDebt);
        if (
            borrowerPledgedCollateral - PoolUtils.encumberance(borrowerAccruedDebt, curLup)
            <
            collateralAmountToPull_
        ) revert PullCollateralInsufficientCollateral();
        borrowerPledgedCollateral -= collateralAmountToPull_;

        // update loan queue
        if (borrowerAccruedDebt != 0) {
            uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                poolState.inflator
            );
            loans.upsert(msg.sender, thresholdPrice);
        }

        borrowers.update(
            msg.sender,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            deposits.mompFactor(poolState.inflator, poolState.accruedDebt, loans.count - 1),
            poolState.inflator
        );

        // update pool state
        poolState.collateral -= collateralAmountToPull_;
        _updatePool(poolState, curLup);
    }

    function _repayDebt(
        address borrower_,
        uint256 maxQuoteTokenAmountToRepay_
    ) internal {

        PoolState memory poolState = _accruePoolInterest();

        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            borrower_,
            poolState.inflator
        );
        if (borrowerAccruedDebt == 0) revert RepayNoDebt();

        uint256 quoteTokenAmountToRepay = Maths.min(borrowerAccruedDebt, maxQuoteTokenAmountToRepay_);
        borrowerAccruedDebt   -= quoteTokenAmountToRepay;
        poolState.accruedDebt -= quoteTokenAmountToRepay;

        // update loan queue
        if (borrowerAccruedDebt == 0) {
            loans.remove(borrower_);
        } else {
            uint256 loansCount = loans.count - 1;
            if (loansCount != 0
                &&
                (borrowerAccruedDebt < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
            ) revert BorrowAmountLTMinDebt();

            uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                borrowerAccruedDebt,
                borrowerPledgedCollateral,
                poolState.inflator
            );
            loans.upsert(borrower_, thresholdPrice);
        }

        borrowers.update(
            msg.sender,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            deposits.mompFactor(poolState.inflator, poolState.accruedDebt, loans.count - 1),
            poolState.inflator
        );

        uint256 newLup = _lup(poolState.accruedDebt);
        _updatePool(poolState, newLup);

        // move amount to repay from sender to pool
        emit Repay(borrower_, newLup, quoteTokenAmountToRepay);
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenAmountToRepay / quoteTokenScale);
    }


    /*********************************/
    /*** Lender Internal Functions ***/
    /*********************************/

    function _addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        (bucketLPs_, ) = buckets.collateralToLPs(
            index_,
            deposits.valueAt(index_),
            collateralAmountToAdd_
        );

        lenders.addLPs(index_, msg.sender, bucketLPs_);
        buckets.addCollateral(index_, bucketLPs_, collateralAmountToAdd_);

        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {

        PoolState memory poolState = _accruePoolInterest();

        uint256 bucketCollateral;
        (bucketLPs_, bucketCollateral) = buckets.collateralToLPs(
            index_,
            deposits.valueAt(index_),
            collateralAmountToRemove_
        );
        if (collateralAmountToRemove_ > bucketCollateral) revert PullCollateralInsufficientCollateral();

        (uint256 lenderLpBalance, ) = lenders.getLenderInfo(index_, msg.sender);
        if (lenderLpBalance == 0 || bucketLPs_ > lenderLpBalance) revert RemoveCollateralInsufficientLP(); // ensure user can actually remove that much

        lenders.removeLPs(index_, msg.sender, bucketLPs_);
        buckets.removeCollateral(index_, bucketLPs_, collateralAmountToRemove_);

        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _redeemLPForQuoteToken(
        uint256 index_,
        PoolState memory poolState_,
        uint256 lpAmount_,
        uint256 amount
    ) internal {
        deposits.remove(index_, amount);  // update FenwickTree

        uint256 newLup = _lup(poolState_.accruedDebt);
        if (_htp(poolState_.inflator) > newLup) revert RemoveQuoteLUPBelowHTP();

        // persist bucket changes
        buckets.removeLPs(index_, lpAmount_);
        lenders.removeLPs(index_,msg.sender, lpAmount_);

        (, uint256 lastDeposit) = lenders.getLenderInfo(index_, msg.sender);
        amount = PoolUtils.applyEarlyWithdrawalPenalty(
            interestRate,
            minFee,
            lastDeposit,
            poolState_.accruedDebt,
            poolState_.collateral,
            index_,
            0,
            amount
        );

        _updatePool(poolState_, newLup);

        // move quote token amount from pool to lender
        emit RemoveQuoteToken(msg.sender, index_, amount, newLup);
        quoteToken().safeTransfer(msg.sender, amount / quoteTokenScale);
    }


    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
        poolState_.accruedDebt = borrowerDebt;
        poolState_.collateral  = pledgedCollateral;
        poolState_.inflator    = inflatorSnapshot;

        if (poolState_.accruedDebt != 0) {
            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;
            if (poolState_.isNewInterestAccrued) {
                poolState_.rate = interestRate;
                uint256 factor = PoolUtils.pendingInterestFactor(poolState_.rate, elapsed);
                poolState_.inflator = Maths.wmul(poolState_.inflator, factor);

                // Scale the fenwick tree to update amount of debt owed to lenders
                uint256 newHtp = _htp(poolState_.inflator);
                if (newHtp != 0) {
                    deposits.accrueInterest(
                        poolState_.accruedDebt,
                        poolState_.collateral,
                        newHtp,
                        factor
                    );
                }

                // Scale the borrower inflator to update amount of interest owed by borrowers
                poolState_.accruedDebt = Maths.wmul(poolState_.accruedDebt, factor);
            }
        }
    }

    function _updatePool(PoolState memory poolState_, uint256 lup_) internal {
        if (block.timestamp - interestRateUpdate > 12 hours) {
            // Update EMAs for target utilization

            uint256 curDebtEma   = Maths.wmul(
                poolState_.accruedDebt,
                EMA_7D_RATE_FACTOR) + Maths.wmul(debtEma,   LAMBDA_EMA_7D
            );
            uint256 curLupColEma = Maths.wmul(
                Maths.wmul(lup_, poolState_.collateral),
                EMA_7D_RATE_FACTOR) + Maths.wmul(lupColEma, LAMBDA_EMA_7D
            );

            debtEma   = curDebtEma;
            lupColEma = curLupColEma;

            if (
                PoolUtils.collateralization(
                    poolState_.accruedDebt,
                    poolState_.collateral,
                    lup_
                ) != Maths.WAD) {

                int256 actualUtilization = int256(
                    deposits.utilization(
                        poolState_.accruedDebt,
                        poolState_.collateral
                    )
                );
                int256 targetUtilization = int256(Maths.wdiv(curDebtEma, curLupColEma));

                int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
                int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

                if (!poolState_.isNewInterestAccrued) poolState_.rate = interestRate;

                uint256 newInterestRate = poolState_.rate;
                if (decreaseFactor < increaseFactor - 10**18) {
                    newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
                } else if (decreaseFactor > 10**18 - increaseFactor) {
                    newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
                }
                if(poolState_.rate != newInterestRate) {
                    interestRate       = newInterestRate;
                    interestRateUpdate = block.timestamp;

                    emit UpdateInterestRate(poolState_.rate, newInterestRate);
                }
            }
        }

        borrowerDebt      = poolState_.accruedDebt;
        pledgedCollateral = poolState_.collateral;

        if (poolState_.isNewInterestAccrued) {
            inflatorSnapshot           = poolState_.inflator;
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    function _hpbIndex() internal view returns (uint256) {
        return deposits.findIndexOfSum(1);
    }

    function _htp(uint256 inflator_) internal view returns (uint256) {
        return Maths.wmul(loans.getMax().val, inflator_);
    }

    function _lupIndex(uint256 debt_) internal view returns (uint256) {
        return deposits.findIndexOfSum(debt_);
    }

    function _lup(uint256 debt_) internal view returns (uint256) {
        return PoolUtils.indexToPrice(_lupIndex(debt_));
    }


    /**************************/
    /*** External Functions ***/
    /**************************/

    function depositSize() external view override returns (uint256) {
        return deposits.treeSum();
    }

    function depositIndex(uint256 debt_) external view override returns (uint256) {
        return deposits.findIndexOfSum(debt_);
    }

    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view override returns (uint256) {
        return deposits.utilization(debt_, collateral_);
    }

    function bucketDeposit(uint256 index_) external view override returns (uint256) {
        return deposits.valueAt(index_);
    }

    function bucketScale(uint256 index_) external view override returns (uint256) {
        return deposits.scale(index_);
    }

    function noOfLoans() external view override returns (uint256) {
        return loans.count - 1;
    }

    function maxBorrower() external view override returns (address) {
        return loans.getMax().id;
    }

    function maxThresholdPrice() external view override returns (uint256) {
        return loans.getMax().val;
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

    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(0);
    }

    function quoteTokenAddress() external pure override returns (address) {
        return _getArgAddress(0x14);
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
