// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/IPool.sol';

import '../libraries/Auctions.sol';
import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';
import '../libraries/Maths.sol';
import '../libraries/PoolUtils.sol';
import '../libraries/BucketMath.sol';

abstract contract Pool is Clone, ReentrancyGuard, Multicall, IPool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 10**18;

    uint256 internal constant LAMBDA_EMA_7D      = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR = 1e18 - LAMBDA_EMA_7D;
    int256  internal constant PERCENT_102        = 1.02 * 10**18;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint208 public override interestRate;       // [WAD]
    uint48  public override interestRateUpdate; // [SEC]

    uint208 internal inflatorSnapshot;           // [WAD]
    uint48  internal lastInflatorSnapshotUpdate; // [SEC]

    uint256 public override pledgedCollateral;  // [WAD]

    uint256 internal debtEma;   // [WAD]
    uint256 internal lupColEma; // [WAD]

    uint256 internal reserveAuctionKicked;    // Time a Claimable Reserve Auction was last kicked.
    uint256 internal reserveAuctionUnclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.
    uint256 internal t0DebtInAuction;         // Total debt in auction used to restrict LPB holder from withdrawing [WAD]

    uint256 internal poolInitializations;
    uint256 internal t0poolDebt;              // Pool debt as if the whole amount was incurred upon the first loan. [WAD]

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    Auctions.Data                      internal auctions;
    mapping(uint256 => Buckets.Bucket) internal buckets;   // deposit index -> bucket
    Deposits.Data                      internal deposits;
    Loans.Data                         internal loans;

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

        bucketLPs_ = Buckets.addQuoteToken(
            buckets[index_],
            deposits.valueAt(index_),
            quoteTokenAmountToAdd_,
            PoolUtils.indexToPrice(index_)
        );
        deposits.add(index_, quoteTokenAmountToAdd_);

        uint256 newLup = _lup(poolState.accruedDebt);
        _updateInterestParams(poolState, newLup);

        emit AddQuoteToken(msg.sender, index_, quoteTokenAmountToAdd_, newLup);
        // move quote token amount from lender to pool
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmountToAdd_);
    }

    function approveLpOwnership(
        address allowedNewOwner_,
        uint256 index_,
        uint256 lpsAmountToApprove_
    ) external {
        _lpTokenAllowances[msg.sender][allowedNewOwner_][index_] = lpsAmountToApprove_;
    }

    function moveQuoteToken(
        uint256 maxAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        if (fromIndex_ == toIndex_) revert MoveToSamePrice();

        PoolState memory poolState = _accruePoolInterest();
        _revertIfAuctionDebtLocked(fromIndex_, poolState.inflator);

        Buckets.Lender memory lender;
        (lender.lps, lender.depositTime) = buckets.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        uint256 amountToMove;
        uint256 fromDeposit = deposits.valueAt(fromIndex_);
        Buckets.Bucket storage fromBucket = buckets[fromIndex_];
        (amountToMove, fromBucketLPs_, ) = Buckets.lpsToQuoteToken(
            fromBucket.lps,
            fromBucket.collateral,
            fromDeposit,
            lender.lps,
            maxAmountToMove_,
            PoolUtils.indexToPrice(fromIndex_)
        );

        deposits.remove(fromIndex_, amountToMove, fromDeposit);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        amountToMove = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState,
            lender.depositTime,
            fromIndex_,
            toIndex_,
            amountToMove
        );

        Buckets.Bucket storage toBucket = buckets[toIndex_];
        toBucketLPs_ = Buckets.quoteTokensToLPs(
            toBucket.collateral,
            toBucket.lps,
            deposits.valueAt(toIndex_),
            amountToMove,
            PoolUtils.indexToPrice(toIndex_)
        );

        deposits.add(toIndex_, amountToMove);

        // move lup if necessary and check loan book's htp against new lup
        uint256 newLup = _lup(poolState.accruedDebt);
        if (fromIndex_ < toIndex_) if(_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        Buckets.moveLPs(
            fromBucket,
            toBucket,
            fromBucketLPs_,
            toBucketLPs_
        );
        _updateInterestParams(poolState, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, amountToMove, newLup);
    }

    function removeQuoteToken(
        uint256 maxAmount_,
        uint256 index_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_) {
        auctions.revertIfAuctionClearable(loans);

        PoolState memory poolState = _accruePoolInterest();
        _revertIfAuctionDebtLocked(index_, poolState.inflator);

        (uint256 lenderLPsBalance, uint256 lastDeposit) = buckets.getLenderInfo(
            index_,
            msg.sender
        );
        if (lenderLPsBalance == 0) revert NoClaim();      // revert if no LP to claim

        uint256 deposit = deposits.valueAt(index_);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        Buckets.Bucket storage bucket = buckets[index_];
        uint256 exchangeRate = Buckets.getExchangeRate(
            bucket.collateral,
            bucket.lps,
            deposit,
            PoolUtils.indexToPrice(index_)
        );
        removedAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance, exchangeRate));
        uint256 removedAmountBefore = removedAmount_;

        // remove min amount of lender entitled LPBs, max amount desired and deposit in bucket
        if (removedAmount_ > maxAmount_) removedAmount_ = maxAmount_;
        if (removedAmount_ > deposit)    removedAmount_ = deposit;

        if (removedAmountBefore == removedAmount_) redeemedLPs_ = lenderLPsBalance;
        else {
            redeemedLPs_ = Maths.min(lenderLPsBalance, Maths.wrdivr(removedAmount_, exchangeRate));
        }

        deposits.remove(index_, removedAmount_, deposit); // update FenwickTree

        uint256 newLup = _lup(poolState.accruedDebt);
        if (_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        // update bucket and lender LPs balances
        bucket.lps -= redeemedLPs_;
        bucket.lenders[msg.sender].lps -= redeemedLPs_;

        removedAmount_ = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState,
            lastDeposit,
            index_,
            0,
            removedAmount_
        );

        _updateInterestParams(poolState, newLup);

        emit RemoveQuoteToken(msg.sender, index_, removedAmount_, newLup);
        // move quote token amount from pool to lender
        _transferQuoteToken(msg.sender, removedAmount_);
    }

    function transferLPTokens(
        address owner_,
        address newOwner_,
        uint256[] calldata indexes_)
    external {
        uint256 tokensTransferred;
        uint256 indexesLength = indexes_.length;

        for (uint256 i = 0; i < indexesLength; ) {
            if (indexes_[i] > 8192 ) revert InvalidIndex();

            uint256 transferAmount = _lpTokenAllowances[owner_][newOwner_][indexes_[i]];
            (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = buckets.getLenderInfo(
                indexes_[i],
                owner_
            );
            if (transferAmount == 0 || transferAmount != lenderLpBalance) revert NoAllowance();

            delete _lpTokenAllowances[owner_][newOwner_][indexes_[i]]; // delete allowance

            buckets.transferLPs(
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

    function withdrawBonds() external {
        uint256 claimable = auctions.kickers[msg.sender].claimable;
        auctions.kickers[msg.sender].claimable = 0;
        _transferQuoteToken(msg.sender, claimable);
    }


    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function borrow(
        uint256 amountToBorrow_,
        uint256 limitIndex_
    ) external override {
        // if borrower auctioned then it cannot draw more debt
        auctions.revertIfActive(msg.sender);

        PoolState memory poolState     = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(msg.sender);
        uint256 borrowerDebt           = Maths.wmul(borrower.t0debt, poolState.inflator);

        // add origination fee to the amount to borrow and add to borrower's debt
        uint256 debtChange = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate) + Maths.WAD);
        borrowerDebt += debtChange;
        _checkMinDebt(poolState.accruedDebt, borrowerDebt);

        // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
        uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
        if (lupId > limitIndex_) revert LimitIndexReached();

        // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
        uint256 newLup = PoolUtils.indexToPrice(lupId);
        if (
            !_isCollateralized(borrowerDebt, borrower.collateral, newLup)
        ) revert BorrowerUnderCollateralized();

        // check borrow won't push pool into a state of under-collateralization
        poolState.accruedDebt += debtChange;
        if (
            !_isCollateralized(poolState.accruedDebt, poolState.collateral, newLup)
        ) revert PoolUnderCollateralized();

        uint256 t0debtChange = Maths.wdiv(debtChange, poolState.inflator);
        borrower.t0debt += t0debtChange;

        loans.update(
            deposits,
            msg.sender,
            true,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            newLup
        );

        t0poolDebt += t0debtChange;
        _updateInterestParams(poolState, newLup);

        emit Borrow(msg.sender, newLup, amountToBorrow_);
        // move borrowed amount from pool to sender
        _transferQuoteToken(msg.sender, amountToBorrow_);
    }

    function repay(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_
    ) external override {
        PoolState memory poolState     = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.t0debt == 0) revert NoDebt();

        uint256 t0repaidDebt = Maths.min(
            borrower.t0debt,
            Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState.inflator)
        );
        (uint256 quoteTokenAmountToRepay, uint256 newLup) = _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);

        emit Repay(borrowerAddress_, newLup, quoteTokenAmountToRepay);
        // move amount to repay from sender to pool
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmountToRepay);
    }

    /*****************************/
    /*** Liquidation Functions ***/
    /*****************************/

    function bucketTake(
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external override {
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0

        PoolState memory poolState = _accruePoolInterest();
        uint256 bucketDeposit = deposits.valueAt(index_);
        if (bucketDeposit == 0) revert InsufficientLiquidity(); // revert if no quote tokens in arbed bucket

        Auctions.TakeParams memory params = Auctions.bucketTake(
            auctions,
            deposits,
            buckets[index_],
            borrowerAddress_,
            borrower,
            bucketDeposit,
            index_,
            depositTake_,
            poolState.inflator
        );

        borrower.collateral  -= params.collateralAmount; // collateral is removed from the loan
        poolState.collateral -= params.collateralAmount; // collateral is removed from pledged collateral accumulator

        _payLoan(params.t0repayAmount, poolState, borrowerAddress_, borrower);
        pledgedCollateral = poolState.collateral;

        emit BucketTake(
            borrowerAddress_,
            index_,
            params.quoteTokenAmount,
            params.collateralAmount,
            params.bondChange,
            params.isRewarded
        );
    }

    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external override {
        PoolState memory poolState = _accruePoolInterest();
        uint256 reserves = Maths.wmul(t0poolDebt, poolState.inflator) + _getPoolQuoteTokenBalance() - deposits.treeSum() - auctions.totalBondEscrowed - reserveAuctionUnclaimed;
        Loans.Borrower storage borrower = loans.borrowers[borrowerAddress_];
        (uint256 remainingCollateral, uint256 remainingt0Debt) = Auctions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            borrower.collateral,
            borrower.t0debt,
            borrowerAddress_,
            reserves,
            poolState.inflator,
            maxDepth_
        );

        if (remainingt0Debt == 0) remainingCollateral = _settleAuction(borrowerAddress_, remainingCollateral);

        uint256 t0settledDebt = borrower.t0debt - remainingt0Debt;
        t0poolDebt      -= t0settledDebt;
        t0DebtInAuction -= t0settledDebt;

        poolState.collateral -= borrower.collateral - remainingCollateral;

        borrower.t0debt     = remainingt0Debt;
        borrower.collateral = remainingCollateral;

        pledgedCollateral = poolState.collateral;
        _updateInterestParams(poolState, _lup(poolState.accruedDebt));

        emit Settle(borrowerAddress_, t0settledDebt);
    }

    function kick(address borrowerAddress_) external override {
        auctions.revertIfActive(borrowerAddress_);

        Loans.Borrower storage borrower = loans.borrowers[borrowerAddress_];

        PoolState memory poolState = _accruePoolInterest();

        uint256 lup = _lup(poolState.accruedDebt);
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);
        if (
            _isCollateralized(borrowerDebt, borrower.collateral, lup)
        ) revert BorrowerOk();

        uint256 neutralPrice = Maths.wmul(borrower.t0Np, poolState.inflator);
 
        // kick auction
        (uint256 kickAuctionAmount, uint256 bondSize) = Auctions.kick(
            auctions,
            borrowerAddress_,
            borrowerDebt,
            borrowerDebt * Maths.WAD / borrower.collateral,
            deposits.momp(poolState.accruedDebt, loans.noOfLoans()),
            neutralPrice
        );

        loans.remove(borrowerAddress_);

        // when loan is kicked, penalty of three months of interest is added
        uint256 kickPenalty   =  Maths.wmul(Maths.wdiv(poolState.rate, 4 * 1e18), borrowerDebt);
        // update borrower & pool debt with kickPenalty
        borrowerDebt          += kickPenalty;
        poolState.accruedDebt += kickPenalty;

        // convert kick penalty to t0 amount
        kickPenalty     =  Maths.wdiv(kickPenalty, poolState.inflator);
        borrower.t0debt += kickPenalty;
        t0poolDebt      += kickPenalty;
        t0DebtInAuction += borrower.t0debt;

        _updateInterestParams(poolState, lup);

        emit Kick(borrowerAddress_, borrowerDebt, borrower.collateral, bondSize);
        if(kickAuctionAmount != 0) _transferQuoteTokenFrom(msg.sender, kickAuctionAmount);
    }


    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    function startClaimableReserveAuction() external override {
        uint256 curUnclaimedAuctionReserve = reserveAuctionUnclaimed;
        uint256 claimable = Auctions.claimableReserves(
            Maths.wmul(t0poolDebt, inflatorSnapshot),
            deposits.treeSum(),
            auctions.totalBondEscrowed,
            curUnclaimedAuctionReserve,
            _getPoolQuoteTokenBalance()
        );
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward;
        if (curUnclaimedAuctionReserve != 0) {
            reserveAuctionUnclaimed = curUnclaimedAuctionReserve;
            reserveAuctionKicked    = block.timestamp;
            emit ReserveAuction(curUnclaimedAuctionReserve, Auctions.reserveAuctionPrice(block.timestamp));
            _transferQuoteToken(msg.sender, kickerAward);
        } else revert NoReserves();
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 kicked = reserveAuctionKicked;

        if (kicked != 0 && block.timestamp - kicked <= 72 hours) {
            amount_ = Maths.min(reserveAuctionUnclaimed, maxAmount_);
            uint256 price = Auctions.reserveAuctionPrice(kicked);
            uint256 ajnaRequired = Maths.wmul(amount_, price);
            reserveAuctionUnclaimed -= amount_;

            emit ReserveAuction(reserveAuctionUnclaimed, price);

            IERC20Token ajnaToken = IERC20Token(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);
            if (!ajnaToken.transferFrom(msg.sender, address(this), ajnaRequired)) revert ERC20TransferFailed();
            ajnaToken.burn(ajnaRequired);
            _transferQuoteToken(msg.sender, amount_);
        } else revert NoReservesAuction();
    }


    /***********************************/
    /*** Borrower Internal Functions ***/
    /***********************************/

    function _pledgeCollateral(
        address borrowerAddress_,
        uint256 collateralAmountToPledge_
    ) internal {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);

        borrower.collateral  += collateralAmountToPledge_;
        poolState.collateral += collateralAmountToPledge_;

        uint256 newLup = _lup(poolState.accruedDebt);

        if (
            auctions.isActive(borrowerAddress_)
            &&
            _isCollateralized(
                Maths.wmul(borrower.t0debt, poolState.inflator),
                borrower.collateral,
                newLup
            )
        )
        {
            // borrower becomes collateralized, remove debt from pool accumulator and settle auction
            t0DebtInAuction     -= borrower.t0debt;
            borrower.collateral = _settleAuction(borrowerAddress_, borrower.collateral);
        }

        loans.update(
            deposits,
            borrowerAddress_,
            false,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            newLup
        );

        pledgedCollateral = poolState.collateral;
        _updateInterestParams(poolState, newLup);
    }

    function _pullCollateral(
        uint256 collateralAmountToPull_
    ) internal {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(msg.sender);
        uint256 borrowerDebt            = Maths.wmul(borrower.t0debt, poolState.inflator);

        uint256 curLup = _lup(poolState.accruedDebt);
        uint256 encumberedCollateral = borrower.t0debt != 0 ? Maths.wdiv(borrowerDebt, curLup) : 0;
        if (borrower.collateral - encumberedCollateral < collateralAmountToPull_) revert InsufficientCollateral();

        borrower.collateral  -= collateralAmountToPull_;
        poolState.collateral -= collateralAmountToPull_;

        loans.update(
            deposits,
            msg.sender,
            true,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            curLup
        );

        pledgedCollateral = poolState.collateral;
        _updateInterestParams(poolState, curLup);
    }

    function _payLoan(
        uint256 t0repaidDebt_,
        PoolState memory poolState_,
        address borrowerAddress_,
        Loans.Borrower memory borrower_
    ) internal returns(
        uint256 quoteTokenAmountToRepay_, 
        uint256 newLup_
    ) {
        quoteTokenAmountToRepay_ = Maths.wmul(t0repaidDebt_, poolState_.inflator);
        uint256 borrowerDebt     = Maths.wmul(borrower_.t0debt, poolState_.inflator) - quoteTokenAmountToRepay_;
        poolState_.accruedDebt   -= quoteTokenAmountToRepay_;

        // check that paying the loan doesn't leave borrower debt under min debt amount
        _checkMinDebt(poolState_.accruedDebt, borrowerDebt);

        newLup_ = _lup(poolState_.accruedDebt);

        if (auctions.isActive(borrowerAddress_)) {
            if (_isCollateralized(borrowerDebt, borrower_.collateral, newLup_)) {
                // borrower becomes re-collateralized
                // remove entire borrower debt from pool auctions debt accumulator
                t0DebtInAuction -= borrower_.t0debt;
                // settle auction and update borrower's collateral with value after settlement
                borrower_.collateral = _settleAuction(borrowerAddress_, borrower_.collateral);
            } else {
                // partial repay, remove only the paid debt from pool auctions debt accumulator
                t0DebtInAuction -= t0repaidDebt_;
            }
        }
        
        borrower_.t0debt -= t0repaidDebt_;
        loans.update(
            deposits,
            borrowerAddress_,
            false,
            borrower_,
            poolState_.accruedDebt,
            poolState_.inflator,
            poolState_.rate,
            newLup_
        );

        t0poolDebt -= t0repaidDebt_;
        _updateInterestParams(poolState_, newLup_);
    }

    function _checkMinDebt(uint256 accruedDebt_,  uint256 borrowerDebt_) internal view {
        if (borrowerDebt_ != 0) {
            uint256 loansCount = loans.noOfLoans();
            if (
                loansCount >= 10
                &&
                (borrowerDebt_ < PoolUtils.minDebtAmount(accruedDebt_, loansCount))
            ) revert AmountLTMinDebt();
        }
    }

    /*********************************/
    /*** Lender Internal Functions ***/
    /*********************************/

    function _addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();
        bucketLPs_ = Buckets.addCollateral(
            buckets[index_],
            msg.sender,
            deposits.valueAt(index_),
            collateralAmountToAdd_,
            PoolUtils.indexToPrice(index_))
        ;
        _updateInterestParams(poolState, _lup(poolState.accruedDebt));
    }


    /******************************/
    /*** Pool Virtual Functions ***/
    /******************************/

    /**
     *  @notice Collateralization calculation (implemented by each pool accordingly).
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal virtual returns (bool);

    /**
     *  @notice Settle an auction when it exits the auction queue (implemented by each pool accordingly).
     *  @param  borrowerAddress_    Address of the borrower that exits auction.
     *  @param  borrowerCollateral_ Borrower collateral amount before auction exit.
     *  @return Remaining borrower collateral after auction exit.
     */
    function _settleAuction(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal virtual returns (uint256);


    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
        uint256 t0Debt        = t0poolDebt;
        poolState_.collateral = pledgedCollateral;
        poolState_.inflator   = inflatorSnapshot;
        poolState_.rate       = interestRate;

        if (t0Debt != 0) {
            // Calculate prior pool debt
            poolState_.accruedDebt = Maths.wmul(t0Debt, poolState_.inflator);

            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;

            if (poolState_.isNewInterestAccrued) {
                // Scale the borrower inflator to update amount of interest owed by borrowers
                uint256 factor = BucketMath.pendingInterestFactor(poolState_.rate, elapsed);
                poolState_.inflator = Maths.wmul(poolState_.inflator, factor);

                // Scale the fenwick tree to update amount of debt owed to lenders
                deposits.accrueInterest(
                    poolState_.accruedDebt,
                    poolState_.collateral,
                    _htp(poolState_.inflator),
                    factor
                );

                // After debt owed to lenders has accrued, calculate current debt owed by borrowers
                poolState_.accruedDebt = Maths.wmul(t0Debt, poolState_.inflator);
            }
        }
    }

    function _updateInterestParams(PoolState memory poolState_, uint256 lup_) internal {
        if (block.timestamp - interestRateUpdate > 12 hours) {
            // update pool EMAs for target utilization calculation
            uint256 curDebtEma = Maths.wmul(
                    poolState_.accruedDebt,
                    EMA_7D_RATE_FACTOR
                ) + Maths.wmul(debtEma, LAMBDA_EMA_7D
            );
            uint256 curLupColEma = Maths.wmul(
                    Maths.wmul(lup_, poolState_.collateral),
                    EMA_7D_RATE_FACTOR
                ) + Maths.wmul(lupColEma, LAMBDA_EMA_7D
            );

            debtEma   = curDebtEma;
            lupColEma = curLupColEma;

            // update pool interest rate
            if (poolState_.accruedDebt != 0) {                
                int256 mau = int256(                                       // meaningful actual utilization                   
                    deposits.utilization(
                        poolState_.accruedDebt,
                        poolState_.collateral
                    )
                );
                int256 tu = int256(Maths.wdiv(curDebtEma, curLupColEma));  // target utilization

                if (!poolState_.isNewInterestAccrued) poolState_.rate = interestRate;
                // raise rates if 4*(tu-1.02*mau) < (tu+1.02*mau-1)^2-1
                // decrease rates if 4*(tu-mau) > 1-(tu+mau-1)^2
                int256 mau102 = mau * PERCENT_102 / 10**18;

                uint256 newInterestRate = poolState_.rate;
                if (4 * (tu - mau102) < ((tu + mau102 - 10**18) ** 2) / 10**18 - 10**18) {
                    newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
                } else if (4 * (tu - mau) > 10**18 - ((tu + mau - 10**18) ** 2) / 10**18) {
                    newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
                }

                if (poolState_.rate != newInterestRate) {
                    interestRate       = uint208(newInterestRate);
                    interestRateUpdate = uint48(block.timestamp);

                    emit UpdateInterestRate(poolState_.rate, newInterestRate);
                }
            }
        }

        // update pool inflator
        if (poolState_.isNewInterestAccrued) {
            inflatorSnapshot           = uint208(poolState_.inflator);
            lastInflatorSnapshotUpdate = uint48(block.timestamp);
        } else if (poolState_.accruedDebt == 0) {
            inflatorSnapshot           = uint208(Maths.WAD);
            lastInflatorSnapshotUpdate = uint48(block.timestamp);
        }
    }

    function _transferQuoteTokenFrom(address from_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(20)).transferFrom(from_, address(this), amount_ / _getArgUint256(40))) revert ERC20TransferFailed();
    }

    function _transferQuoteToken(address to_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(20)).transfer(to_, amount_ / _getArgUint256(40))) revert ERC20TransferFailed();
    }

    function _getPoolQuoteTokenBalance() internal view returns (uint256) {
        return IERC20Token(_getArgAddress(20)).balanceOf(address(this));
    }

    function _htp(uint256 inflator_) internal view returns (uint256) {
        return Maths.wmul(loans.getMax().thresholdPrice, inflator_);
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

    function auctionInfo(
        address borrower_
    ) external view override returns (address, uint256, uint256, uint256, uint256, address, address) {
        return (
            auctions.liquidations[borrower_].kicker,
            auctions.liquidations[borrower_].bondFactor,
            auctions.liquidations[borrower_].kickTime,
            auctions.liquidations[borrower_].kickMomp,
            auctions.liquidations[borrower_].neutralPrice,
            auctions.liquidations[borrower_].prev,
            auctions.liquidations[borrower_].next
        );
    }

    function borrowerInfo(
        address borrower_
    ) external view override returns (uint256, uint256, uint256) {
        return (
            loans.borrowers[borrower_].t0debt,
            loans.borrowers[borrower_].collateral,
            loans.borrowers[borrower_].t0Np
        );
    }

    function bucketInfo(
        uint256 index_
    ) external view override returns (uint256, uint256, uint256, uint256, uint256) {
        return (
            buckets[index_].lps,
            buckets[index_].collateral,
            buckets[index_].bankruptcyTime,
            deposits.valueAt(index_),
            deposits.scale(index_)
        );
    }

    function debtInfo() external view returns (uint256, uint256, uint256) {
        uint256 pendingInflator = BucketMath.pendingInflator(
            inflatorSnapshot,
            lastInflatorSnapshotUpdate,
            interestRate
        );
        return (
            Maths.wmul(t0poolDebt, pendingInflator),
            Maths.wmul(t0poolDebt, inflatorSnapshot),
            Maths.wmul(t0DebtInAuction, inflatorSnapshot)
        );
    }

    function depositIndex(uint256 debt_) external view override returns (uint256) {
        return deposits.findIndexOfSum(debt_);
    }

    function depositSize() external view override returns (uint256) {
        return deposits.treeSum();
    }

    function depositUtilization(
        uint256 debt_,
        uint256 collateral_
    ) external view override returns (uint256) {
        return deposits.utilization(debt_, collateral_);
    }

    function emasInfo() external view override returns (uint256, uint256) {
        return (
            debtEma,
            lupColEma
        );
    }

    function inflatorInfo() external view override returns (uint256, uint256) {
        return (
            inflatorSnapshot,
            lastInflatorSnapshotUpdate
        );
    }

    function kickerInfo(
        address kicker_
    ) external view override returns (uint256, uint256) {
        return(
            auctions.kickers[kicker_].claimable,
            auctions.kickers[kicker_].locked
        );
    }

    function lenderInfo(
        uint256 index_,
        address lender_
    ) external view override returns (uint256, uint256) {
        return buckets.getLenderInfo(index_, lender_);
    }

    function loansInfo() external view override returns (address, uint256, uint256) {
        return (
            loans.getMax().borrower,
            Maths.wmul(loans.getMax().thresholdPrice, inflatorSnapshot),
            loans.noOfLoans()
        );
    }

    function reservesInfo() external view override returns (uint256, uint256, uint256) {
        return (
            auctions.totalBondEscrowed,
            reserveAuctionUnclaimed,
            reserveAuctionKicked
        );
    }

    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(0);
    }

    function quoteTokenAddress() external pure override returns (address) {
        return _getArgAddress(20);
    }

    function quoteTokenScale() external pure override returns (uint256) {
        return _getArgUint256(40);
    }

    /**
     *  @notice Called by LPB removal functions assess whether or not LPB is locked.
     *  @param  index_    The bucket index from which LPB is attempting to be removed.
     *  @param  inflator_ The pool inflator used to properly assess t0 debt in auctions.
     */
    function _revertIfAuctionDebtLocked(
        uint256 index_,
        uint256 inflator_
    ) internal view {
        uint256 t0AuctionDebt = t0DebtInAuction;
        if (t0AuctionDebt != 0 ) {
            // deposit in buckets within liquidation debt from the top-of-book down are frozen.
            if (index_ <= deposits.findIndexOfSum(Maths.wmul(t0AuctionDebt, inflator_))) revert RemoveDepositLockedByAuctionDebt();
        } 
    }

}
