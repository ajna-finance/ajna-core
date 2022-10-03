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
import '../libraries/Queue.sol';
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
    using Queue     for Queue.Data;

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

    mapping(address => Liquidation) public override liquidations;

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    address       internal ajnaTokenAddress; //  Address of the Ajna token, needed for Claimable Reserve Auctions.
    Book.Deposits internal deposits;
    Heap.Data     internal loans;
    Queue.Data    internal auctions;

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

        uint256 numLoans = loans.count - 1;
        uint256 mompFactor = numLoans > 0 ? Maths.wdiv(_momp(numLoans, poolState.accruedDebt), poolState.inflator): 0;

        borrowers.update(
            msg.sender,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            mompFactor,
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

    /**************************************/
    /*** Liquidation External Functions ***/
    /**************************************/

    function kick(address borrower_) external override {
        PoolState memory poolState = _accruePoolInterest();

        Actors.Borrower memory borrower = borrowers.getBorrowerInfoStruct(
            borrower_,
            poolState.inflator
        );

        if (auctions.isActive(borrower_)) revert AuctionActive();
        if (borrower.debt == 0) revert KickNoDebt();
        uint256 lup = _lup(poolState.accruedDebt);

       if (
           PoolUtils.collateralization(
               borrower.debt,
               borrower.collateral,
               lup
           ) >= Maths.WAD
       ) revert KickBorrowerOk();


       (uint256 bondFactor, uint256 bondSize) = _calcBond(
                                                    loans.count - 1,
                                                    poolState.accruedDebt,
                                                    borrower.debt,
                                                    borrower.collateral,
                                                    lup
                                                );

       liquidations[borrower_] = Liquidation({
           kickTime:       uint128(block.timestamp),
           kickPriceIndex: uint128(_hpbIndex()),
           bondFactor:     bondFactor,
           bondSize:       bondSize
       });

       auctions.add(borrower_);
       loans.remove(borrower_);

       borrowers.updateDebt(
           borrower_,
           borrower.debt,
           poolState.inflator
       );

       _updatePool(poolState, lup);

        emit Kick(borrower_, borrower.debt, borrower.collateral);
        quoteToken().safeTransferFrom(msg.sender, address(this), bondSize / quoteTokenScale);
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

        uint256 numLoans = loans.count - 1;
        uint256 mompFactor = numLoans > 0 ? Maths.wdiv(_momp(numLoans, poolState.accruedDebt), poolState.inflator): 0;
        borrowers.update(
            borrower_,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            mompFactor,
            poolState.inflator
        );

        poolState.collateral += collateralAmountToPledge_;
        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _pullCollateral(
        address borrower_,
        uint256 collateralAmountToPull_
    ) internal {

        PoolState memory poolState = _accruePoolInterest();

        // borrower accounting
        (uint256 borrowerAccruedDebt, uint256 borrowerPledgedCollateral) = borrowers.getBorrowerInfo(
            borrower_,
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
            loans.upsert(borrower_, thresholdPrice);
        }

        uint256 numLoans = loans.count - 1;
        uint256 mompFactor = numLoans > 0 ? Maths.wdiv(_momp(numLoans, poolState.accruedDebt), poolState.inflator): 0;
        borrowers.update(
            borrower_,
            borrowerAccruedDebt,
            borrowerPledgedCollateral,
            mompFactor,
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

        Actors.Borrower memory borrower = borrowers.getBorrowerInfoStruct(
            borrower_,
            poolState.inflator
        );


        if (borrower.debt == 0) revert RepayNoDebt();
        uint256 quoteTokenAmountToRepay = Maths.min(borrower.debt, maxQuoteTokenAmountToRepay_);

        borrower.debt         -= quoteTokenAmountToRepay;
        poolState.accruedDebt -= quoteTokenAmountToRepay;

        uint256 newLup = _lup(poolState.accruedDebt);
        _updateLoanPositionAndState(borrower_, borrower, poolState, newLup);

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

    /**************************************/
    /*** Liquidation Internal Functions ***/
    /**************************************/

    /**
     *  @notice Performs take checks, calculates amounts and bpf reward / penalty.
     *  @dev Internal support method assisting in the ERC20 and ERC721 pool take calls.
     *  @param borrower_         Address of the borower take is being called upon.
     *  @param maxCollateral_    Max amount of collateral to take, submited by the taker.
     *  @return rewardOrPenalty_ Reward (positive) or penalty (negative) in quote token that is applied to the bondSize.
     *  @return collateralTaken_ Amount of collateral taken from the auction and sent to the taker.
     */
    function _take(
        address borrower_,
        uint256 maxCollateral_
    ) internal returns(
        int256 rewardOrPenalty_,
        uint256 collateralTaken_,
        uint256 amountQT_
    ) { 

        // check liquidation process status
        if (!auctions.isActive(borrower_)) revert NoAuction();

        Liquidation memory liquidation = liquidations[borrower_];
        if (liquidation.kickTime == 0 || block.timestamp - uint256(liquidation.kickTime) <= 1 hours) revert TakeNotPastCooldown();

        PoolState memory poolState = _accruePoolInterest();
        Actors.Borrower memory borrower = borrowers.getBorrowerInfoStruct(
            borrower_,
            poolState.inflator
        );

        if (borrower.collateral == 0) revert TakeNoCollateral();
        if (
            PoolUtils.collateralization(
                borrower.debt,
                borrower.collateral,
                _lup(poolState.accruedDebt)
            ) >= Maths.WAD
        ) revert TakeBorrowerOk();

        // Calculate amount
        uint256 price    = PoolUtils.auctionPrice(liquidation.kickPriceIndex, liquidation.kickTime);
        amountQT_        = Maths.wmul(price, Maths.min(borrower.collateral, maxCollateral_));
        collateralTaken_ = Maths.wdiv(amountQT_, price);

        // Calculate Bond reward or penalty
        // TODO: remove auction from queue if auctionDebt == 0;
        int256 bpf = PoolUtils._bpf(
            borrower.debt,
            borrower.collateral,
            borrower.mompFactor,
            poolState.inflator,
            liquidation.bondFactor,
            price);

        uint256 repayAmount = Maths.wmul(amountQT_, uint256(1e18 - bpf));
        if (repayAmount >= borrower.debt) {
            repayAmount = borrower.debt;
            amountQT_ = Maths.wdiv(borrower.debt, uint256(1e18 - bpf));
        }

        if (bpf >= 0) {
            // Take is below neutralPrice, Kicker is rewarded
            rewardOrPenalty_ = int256(amountQT_ - repayAmount);
            liquidation.bondSize += amountQT_ - repayAmount;
 
        } else {     
            // Take is above neutralPrice, Kicker is penalized
            rewardOrPenalty_ = PRBMathSD59x18.mul(int256(amountQT_), bpf);
            liquidation.bondSize -= uint256(-rewardOrPenalty_);
        }

        poolState.accruedDebt -= repayAmount;
        borrower.debt         -= repayAmount;

        poolState.collateral  -= collateralTaken_;
        borrower.collateral   -= collateralTaken_;
        
        uint256 newLup = _lup(poolState.accruedDebt);
        _updateLoanPositionAndState(borrower_, borrower, poolState, newLup);

        liquidations[borrower_] = liquidation;

    }


    /**
     *  @notice Performs loan and auction update checks, calculates TP and loan and auction position.
     *  @dev Internal support method assisting in the ERC20 and ERC721 pool take calls, called by _take.
     *  @param borrower_       Address of the borower take is being called upon.
     *  @param borrowerStruct_ Borrower struct containing relevant Borrower info.
     *  @param poolState_      PoolState struct containing relevant PoolState info.
     *  @param lup_            Lowest utilized price, used to track shared liquidation price.
     */
    function _updateLoanPositionAndState(
        address borrower_,
        Actors.Borrower memory borrowerStruct_,
        PoolState memory poolState_,
        uint256 lup_
        ) internal {

        uint256 loansCount = loans.count - 1;

        if (borrowerStruct_.debt != 0) {

            // If loan has debt or collateralized auction has debt
            if (!auctions.isActive(borrower_) || PoolUtils.collateralization(borrowerStruct_.debt, borrowerStruct_.collateral, lup_) >= Maths.WAD) {

                if (auctions.isActive(borrower_)) auctions.remove(borrower_);
                if (loansCount != 0
                    &&
                    (borrowerStruct_.debt < PoolUtils.minDebtAmount(poolState_.accruedDebt, loansCount))
                ) revert BorrowAmountLTMinDebt();

                uint256 thresholdPrice = PoolUtils.t0ThresholdPrice(
                    borrowerStruct_.debt,
                    borrowerStruct_.collateral,
                    poolState_.inflator
                );

                loans.upsert(borrower_, thresholdPrice);

                loansCount = loans.count - 1;
                borrowerStruct_.mompFactor = loansCount > 0 ? Maths.wdiv(_momp(loansCount, poolState_.accruedDebt), poolState_.inflator): 0; 
            }

        } else { // loan or auction has no debt

            if (auctions.isActive(borrower_)) {
                auctions.remove(borrower_);

            } else {
                loans.remove(borrower_);
                loansCount = loans.count - 1;
                borrowerStruct_.mompFactor = loansCount > 0 ? Maths.wdiv(_momp(loansCount, poolState_.accruedDebt), poolState_.inflator): 0; 
            }
        }


        borrowerStruct_.inflatorSnapshot = poolState_.inflator;

        borrowers[borrower_] = borrowerStruct_;
        _updatePool(poolState_, lup_);
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

    /**
     *  @notice Calculates the MOMP, most optomistic matching price.
     *  @dev The MOMP is stamped on each loan when touched and used in the kick as well as take.
     *  @param numLoans_             Number of loans in the pool.
     *  @param poolStateAccruedDebt_ Total debt of the pool.
     *  @return momp_                The amount of deposit above this price is equal to the average loan's debt.
     */
    function _momp(uint256 numLoans_, uint256 poolStateAccruedDebt_) internal view returns (uint256) {
        return PoolUtils.indexToPrice(
                deposits.findIndexOfSum(
                    Maths.wdiv(poolStateAccruedDebt_, numLoans_ * Maths.WAD)
                )
            );
    }
    
    /**
     *  @notice Calculates the bondFactor and bondSize, to be used in determining the bond when an auction is kicked. 
     *  @param numLoans_                  Number of loans in the pool.
     *  @param poolStateAccruedDebt_      Total debt of the pool.
     *  @param borrowerAccruedDebt_       Total borrower.
     *  @param borrowerPledgedCollateral_ Total borrower pledged collateral.
     *  @return bondFactor_               Factor used in calculating the BPF, bond penalty factor on every take.
     *  @return bondSize_                 Size of the bond required to kick the loan into auction.
     */
    function _calcBond(
        uint256 numLoans_,
        uint256 poolStateAccruedDebt_,
        uint256 borrowerAccruedDebt_,
        uint256 borrowerPledgedCollateral_,
        uint256 lup_
    ) internal view returns (uint256 bondFactor_, uint256 bondSize_) {

       uint256 thresholdPrice = borrowerAccruedDebt_ * Maths.WAD / borrowerPledgedCollateral_;
       if (lup_ > thresholdPrice) revert KickLUPGreaterThanTP();
       uint256 momp = _momp(numLoans_, poolStateAccruedDebt_);

       // bondFactor = min(30%, max(1%, (neutralPrice - thresholdPrice) / neutralPrice))
       bondFactor_ = thresholdPrice >= momp ? 0.01 * 1e18 : Maths.min(0.3 * 1e18, Maths.max(0.01 * 1e18, 1e18 - Maths.wdiv(thresholdPrice, momp)));
       bondSize_ = Maths.wmul(bondFactor_, borrowerAccruedDebt_);
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
