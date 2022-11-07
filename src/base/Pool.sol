// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/IPool.sol';

import '../libraries/Auctions.sol';
import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';
import '../libraries/Maths.sol';
import '../libraries/PoolUtils.sol';

abstract contract Pool is Clone, Multicall, IPool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    uint256 internal constant INCREASE_COEFFICIENT = 1.1 * 10**18;
    uint256 internal constant DECREASE_COEFFICIENT = 0.9 * 10**18;

    uint256 internal constant LAMBDA_EMA_7D      = 0.905723664263906671 * 1e18; // Lambda used for interest EMAs calculated as exp(-1/7   * ln2)
    uint256 internal constant EMA_7D_RATE_FACTOR = 1e18 - LAMBDA_EMA_7D;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint256 public override interestRate;       // [WAD]
    uint256 public override interestRateUpdate; // [SEC]
    uint256 public override pledgedCollateral;  // [WAD]

    uint256 internal debtEma;   // [WAD]
    uint256 internal lupColEma; // [WAD]

    uint256 internal inflatorSnapshot;           // [WAD]
    uint256 internal lastInflatorSnapshotUpdate; // [SEC]

    uint256 internal reserveAuctionKicked;    // Time a Claimable Reserve Auction was last kicked.
    uint256 internal reserveAuctionUnclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.

    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    Auctions.Data                      internal auctions;
    mapping(uint256 => Buckets.Bucket) internal buckets;              // deposit index -> bucket
    Deposits.Data                      internal deposits;
    Loans.Data                         internal loans;
    uint256                            internal poolInitializations;
    uint256                            internal t0poolDebt;           // Pool debt as if the whole amount was incurred upon the first loan. [WAD]

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

        bucketLPs_ = buckets.addQuoteToken(
            deposits.valueAt(index_),
            quoteTokenAmountToAdd_,
            index_
        );
        deposits.add(index_, quoteTokenAmountToAdd_);

        uint256 newLup = _lup(poolState.accruedDebt);
        _updatePool(poolState, newLup);

        // move quote token amount from lender to pool
        emit AddQuoteToken(msg.sender, index_, quoteTokenAmountToAdd_, newLup);
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
        uint256 maxQuoteTokenAmountToMove_,
        uint256 fromIndex_,
        uint256 toIndex_
    ) external override returns (uint256 fromBucketLPs_, uint256 toBucketLPs_) {
        if (fromIndex_ == toIndex_) revert MoveToSamePrice();

        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = buckets.getLenderInfo(
            fromIndex_,
            msg.sender
        );
        uint256 quoteTokenAmountToMove;
        (quoteTokenAmountToMove, fromBucketLPs_, ) = buckets.lpsToQuoteToken(
            deposits.valueAt(fromIndex_),
            lenderLpBalance,
            maxQuoteTokenAmountToMove_,
            fromIndex_
        );

        deposits.remove(fromIndex_, quoteTokenAmountToMove);

        // apply early withdrawal penalty if quote token is moved from above the PTP to below the PTP
        quoteTokenAmountToMove = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState,
            lenderLastDepositTime,
            fromIndex_,
            toIndex_,
            quoteTokenAmountToMove
        );

        toBucketLPs_ = buckets.quoteTokensToLPs(
            deposits.valueAt(toIndex_),
            quoteTokenAmountToMove,
            toIndex_
        );

        deposits.add(toIndex_, quoteTokenAmountToMove);

        uint256 newLup = _lup(poolState.accruedDebt); // move lup if necessary and check loan book's htp against new lup
        if (fromIndex_ < toIndex_) if(_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        buckets.moveLPs(fromBucketLPs_, toBucketLPs_, fromIndex_, toIndex_);
        _updatePool(poolState, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, quoteTokenAmountToMove, newLup);
    }

    function removeQuoteToken(
        uint256 maxAmount_,
        uint256 index_
    ) external returns (uint256 removedAmount_, uint256 redeemedLPs_) {
        auctions.revertIfAuctionClearable(loans);

        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLPsBalance, uint256 lastDeposit) = buckets.getLenderInfo(
            index_,
            msg.sender
        );
        if (lenderLPsBalance == 0) revert NoClaim(); // revert if no LP to claim

        uint256 deposit = deposits.valueAt(index_);
        if (deposit == 0) revert InsufficientLiquidity(); // revert if there's no liquidity in bucket

        (uint256 exchangeRate, ) = buckets.getExchangeRate(deposit, index_);
        removedAmount_ = Maths.rayToWad(Maths.rmul(lenderLPsBalance, exchangeRate));

        // remove min amount of lender entitled LPBs, max amount desired and deposit in bucket
        if (removedAmount_ > maxAmount_) removedAmount_ = maxAmount_;
        if (removedAmount_ > deposit)    removedAmount_ = deposit;
        redeemedLPs_ = Maths.min(lenderLPsBalance, Maths.wrdivr(removedAmount_, exchangeRate));

        deposits.remove(index_, removedAmount_);  // update FenwickTree

        uint256 newLup = _lup(poolState.accruedDebt);
        if (_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        // persist bucket changes
        buckets.removeLPs(redeemedLPs_, index_);

        removedAmount_ = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState,
            lastDeposit,
            index_,
            0,
            removedAmount_
        );

        _updatePool(poolState, newLup);

        // move quote token amount from pool to lender
        emit RemoveQuoteToken(msg.sender, index_, removedAmount_, newLup);
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
            if (!Deposits.isDepositIndex(indexes_[i])) revert InvalidIndex();

            uint256 transferAmount = _lpTokenAllowances[owner_][newOwner_][indexes_[i]];
            if (transferAmount == 0) revert NoAllowance();

            (uint256 lenderLpBalance, uint256 lenderLastDepositTime) = buckets.getLenderInfo(
                indexes_[i],
                owner_
            );
            if (transferAmount != lenderLpBalance) revert NoAllowance();

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

        // increase debt by the origination fee
        uint256 debtChange   = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate) + Maths.WAD);
        uint256 t0debtChange = Maths.wdiv(debtChange, poolState.inflator);
        borrowerDebt += debtChange;
        _checkMinDebt(poolState.accruedDebt, borrowerDebt);

        // calculate the new LUP
        uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
        if (lupId > limitIndex_) revert LimitIndexReached();
        uint256 newLup = PoolUtils.indexToPrice(lupId);

        // check borrow won't push borrower into a state of under-collateralization
        if (
            _collateralization(
                borrowerDebt,
                borrower.collateral,
                newLup
            ) < Maths.WAD
            ||
            borrower.collateral == 0
        ) revert BorrowerUnderCollateralized();

        // check borrow won't push pool into a state of under-collateralization
        poolState.accruedDebt += debtChange;
        if (
            _collateralization(
                poolState.accruedDebt,
                poolState.collateral,
                newLup
            ) < Maths.WAD
        ) revert PoolUnderCollateralized();

        borrower.t0debt += t0debtChange;
        loans.update(
            deposits,
            msg.sender,
            borrower,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, newLup);
        t0poolDebt += t0debtChange;

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amountToBorrow_);
        _transferQuoteToken(msg.sender, amountToBorrow_);
    }

    function repay(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_
    ) external override {
        PoolState memory poolState     = _accruePoolInterest();
        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.t0debt == 0) revert NoDebt();

        uint256 t0repaidDebt = Maths.min(borrower.t0debt, Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState.inflator));

        (
            uint256 quoteTokenAmountToRepay, 
            uint256 newLup
        ) = _payLoan(t0repaidDebt, poolState, borrowerAddress_, borrower);

        // move amount to repay from sender to pool
        emit Repay(borrowerAddress_, newLup, quoteTokenAmountToRepay);
        _transferQuoteTokenFrom(msg.sender, quoteTokenAmountToRepay);
    }

    /*****************************/
    /*** Liquidation Functions ***/
    /*****************************/

    function heal(
        address borrower_,
        uint256 maxDepth_
    ) external override {
        uint256 poolDebt          = Maths.wmul(t0poolDebt, inflatorSnapshot);
        uint256 quoteTokenBalance = IERC20Token(_getArgAddress(20)).balanceOf(address(this));
        uint256 reserves          = poolDebt + quoteTokenBalance - deposits.treeSum() - auctions.totalBondEscrowed - reserveAuctionUnclaimed;
        uint256 healedDebt        = auctions.heal(
            loans,
            buckets,
            deposits,
            borrower_,
            reserves, maxDepth_,
            inflatorSnapshot
        );
        if (healedDebt != 0) {
            t0poolDebt -= Maths.wdiv(healedDebt, inflatorSnapshot);
            emit Heal(borrower_, healedDebt);
        }
    }

    function kick(address borrowerAddress_) external override {
        auctions.revertIfActive(borrowerAddress_);

        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.t0debt == 0) revert NoDebt();

        uint256 lup = _lup(poolState.accruedDebt);
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);
        if (
            _collateralization(
                borrowerDebt,
                borrower.collateral,
                lup
            ) >= Maths.WAD
        ) revert BorrowerOk();

        uint256 kickPenalty = loans.kick(
            borrowerAddress_,
            borrowerDebt,
            poolState.inflator,
            poolState.rate
        );
        poolState.accruedDebt += kickPenalty;
        t0poolDebt += Maths.wdiv(kickPenalty, poolState.inflator);
        
        // kick auction
        uint256 kickAuctionAmount = auctions.kick(
            borrowerAddress_,
            borrowerDebt,
            borrowerDebt * Maths.WAD / borrower.collateral,
            deposits.momp(poolState.accruedDebt, loans.noOfLoans())
        );

        // update pool state
        _updatePool(poolState, lup);

        emit Kick(borrowerAddress_, borrowerDebt, borrower.collateral);
        _transferQuoteTokenFrom(msg.sender, kickAuctionAmount);
    }


    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    function startClaimableReserveAuction() external override {
        uint256 curUnclaimedAuctionReserve = reserveAuctionUnclaimed;
        uint256 claimable = PoolUtils.claimableReserves(
            Maths.wmul(t0poolDebt, inflatorSnapshot),
            deposits.treeSum(),
            auctions.totalBondEscrowed,
            curUnclaimedAuctionReserve,
            IERC20Token(_getArgAddress(20)).balanceOf(address(this))
        );
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward;
        if (curUnclaimedAuctionReserve != 0) {
            reserveAuctionUnclaimed = curUnclaimedAuctionReserve;
            reserveAuctionKicked    = block.timestamp;
            emit ReserveAuction(curUnclaimedAuctionReserve, PoolUtils.reserveAuctionPrice(block.timestamp));
            _transferQuoteToken(msg.sender, kickerAward);
        }
        else revert NoReserves();
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 kicked = reserveAuctionKicked;

        if (kicked != 0 && block.timestamp - kicked <= 72 hours) {
            amount_ = Maths.min(reserveAuctionUnclaimed, maxAmount_);
            uint256 price = PoolUtils.reserveAuctionPrice(kicked);
            uint256 ajnaRequired = Maths.wmul(amount_, price);
            reserveAuctionUnclaimed -= amount_;

            emit ReserveAuction(reserveAuctionUnclaimed, price);

            IERC20Token ajnaToken = IERC20Token(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079);
            if (!ajnaToken.transferFrom(msg.sender, address(this), ajnaRequired)) revert ERC20TransferFailed();
            ajnaToken.burn(ajnaRequired);
            _transferQuoteToken(msg.sender, amount_);
        }
        else revert NoReservesAuction();
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

        auctions.checkAndRemove(
            borrowerAddress_,
            _collateralization(
                Maths.wmul(borrower.t0debt, poolState.inflator),
                borrower.collateral,
                newLup
            )
        );
        loans.update(
            deposits,
            borrowerAddress_,
            borrower,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, newLup);
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
            borrower,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, curLup);
    }

    function _payLoan(
        uint256 t0repaidDebt, 
        PoolState memory poolState, 
        address borrowerAddress,
        Loans.Borrower memory borrower
    ) internal returns(
        uint256 quoteTokenAmountToRepay_, 
        uint256 newLup_
    ) {
        quoteTokenAmountToRepay_ = Maths.wmul(t0repaidDebt, poolState.inflator);
        uint256 borrowerDebt     = Maths.wmul(borrower.t0debt, poolState.inflator) - quoteTokenAmountToRepay_;
        poolState.accruedDebt    -= quoteTokenAmountToRepay_;

        // check that repay or take doesn't leave borrower debt under min debt amount
        _checkMinDebt(poolState.accruedDebt, borrowerDebt);

        newLup_ = _lup(poolState.accruedDebt);

        auctions.checkAndRemove(
            borrowerAddress,
            _collateralization(
                borrowerDebt,
                borrower.collateral,
                newLup_
            )
        );
        
        borrower.t0debt -= t0repaidDebt;
        loans.update(
            deposits,
            borrowerAddress,
            borrower,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, newLup_);
        t0poolDebt -= t0repaidDebt;
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
        bucketLPs_ = buckets.addCollateral(deposits.valueAt(index_), collateralAmountToAdd_, index_);
        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        auctions.revertIfAuctionClearable(loans);

        PoolState memory poolState = _accruePoolInterest();

        uint256 bucketCollateral;
        (bucketLPs_, bucketCollateral) = buckets.collateralToLPs(
            deposits.valueAt(index_),
            collateralAmountToRemove_,
            index_
        );
        if (collateralAmountToRemove_ > bucketCollateral) revert InsufficientCollateral();

        (uint256 lenderLpBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        if (lenderLpBalance == 0 || bucketLPs_ > lenderLpBalance) revert InsufficientLPs(); // ensure user can actually remove that much

        buckets.removeCollateral(collateralAmountToRemove_, bucketLPs_, index_);

        _updatePool(poolState, _lup(poolState.accruedDebt));
    }


    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
        uint256 t0Debt        = t0poolDebt;
        poolState_.collateral = pledgedCollateral;
        poolState_.inflator   = inflatorSnapshot;

        if (t0Debt != 0) {
            // Calculate prior pool debt
            poolState_.accruedDebt = Maths.wmul(t0Debt, poolState_.inflator);

            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;

            if (poolState_.isNewInterestAccrued) {
                // Scale the borrower inflator to update amount of interest owed by borrowers
                poolState_.rate = interestRate;
                uint256 factor = PoolUtils.pendingInterestFactor(poolState_.rate, elapsed);
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

    /**
     *  @notice Default collateralization calculation (to be overridden in other pool implementations like NFT's).
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return Collateralization value.
     */
    function _collateralization(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal virtual returns (uint256) {
        uint256 encumbered = price_ != 0 && debt_ != 0 ? Maths.wdiv(debt_, price_) : 0;
        return encumbered != 0 ? Maths.wdiv(collateral_, encumbered) : Maths.WAD;
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
                _collateralization(
                    poolState_.accruedDebt,
                    poolState_.collateral,
                    lup_
                ) != Maths.WAD
            ) {

                int256 actualUtilization = int256(
                    deposits.utilization(
                        poolState_.accruedDebt,
                        poolState_.collateral
                    )
                );
                int256 targetUtilization = int256(Maths.wdiv(curDebtEma, curLupColEma));

                // raise rates if 4*(targetUtilization-actualUtilization) < (targetUtilization+actualUtilization-1)^2-1
                // decrease rates if 4*(targetUtilization-mau) > -(targetUtilization+mau-1)^2+1
                int256 decreaseFactor = 4 * (targetUtilization - actualUtilization);
                int256 increaseFactor = ((targetUtilization + actualUtilization - 10**18) ** 2) / 10**18;

                if (!poolState_.isNewInterestAccrued) poolState_.rate = interestRate;

                uint256 newInterestRate = poolState_.rate;
                if (decreaseFactor < increaseFactor - 10**18) {
                    newInterestRate = Maths.wmul(poolState_.rate, INCREASE_COEFFICIENT);
                } else if (decreaseFactor > 10**18 - increaseFactor) {
                    newInterestRate = Maths.wmul(poolState_.rate, DECREASE_COEFFICIENT);
                }
                if (poolState_.rate != newInterestRate) {
                    interestRate       = newInterestRate;
                    interestRateUpdate = block.timestamp;

                    emit UpdateInterestRate(poolState_.rate, newInterestRate);
                }
            }
        }

        pledgedCollateral = poolState_.collateral;

        if (poolState_.isNewInterestAccrued) {
            inflatorSnapshot           = poolState_.inflator;
            lastInflatorSnapshotUpdate = block.timestamp;
        } else if (poolState_.accruedDebt == 0) {
            inflatorSnapshot           = Maths.WAD;
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    function _transferQuoteTokenFrom(address from_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(20)).transferFrom(from_, address(this), amount_ / _getArgUint256(40))) revert ERC20TransferFailed();
    }

    function _transferQuoteToken(address to_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(20)).transfer(to_, amount_ / _getArgUint256(40))) revert ERC20TransferFailed();
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
    )
        external
        view
        override
        returns (
            address,
            uint256,
            uint256,
            uint256,
            address,
            address
        )
    {
        return (
            auctions.liquidations[borrower_].kicker,
            auctions.liquidations[borrower_].bondFactor,
            auctions.liquidations[borrower_].kickTime,
            auctions.liquidations[borrower_].kickMomp,
            auctions.liquidations[borrower_].prev,
            auctions.liquidations[borrower_].next
        );
    }

    function borrowerInfo(
        address borrower_
    )
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (
            loans.borrowers[borrower_].t0debt,
            loans.borrowers[borrower_].collateral,
            loans.borrowers[borrower_].mompFactor
        );
    }

    function bucketInfo(
        uint256 index_
    )
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            buckets[index_].lps,
            buckets[index_].collateral,
            buckets[index_].bankruptcyTime,
            deposits.valueAt(index_),
            deposits.scale(index_)
        );
    }

    // TODO: only PoolInfoUtils should access this
    function accruedDebt() external view override returns (uint256 accruedDebt_)
    {
        return Maths.wmul(t0poolDebt, inflatorSnapshot);
    }

    function debt() external view override returns (uint256 borrowerDebt_) {
        uint256 pendingInflator = PoolUtils.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);
        return Maths.wmul(t0poolDebt, pendingInflator);
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

    function emasInfo()
        external
        view
        override
        returns (
            uint256,
            uint256
        )
    {
        return (
            debtEma,
            lupColEma
        );
    }

    function inflatorInfo()
        external
        view
        override
        returns (
            uint256,
            uint256
        )
    {
        return (
            inflatorSnapshot,
            lastInflatorSnapshotUpdate
        );
    }

    function kickerInfo(
        address kicker_
    )
        external
        view
        override
        returns (
            uint256,
            uint256
    )
    {
        return(
            auctions.kickers[kicker_].claimable,
            auctions.kickers[kicker_].locked
        );
    }

    function lenderInfo(
        uint256 index_,
        address lender_
    )
        external
        view
        override
        returns (
            uint256,
            uint256
        )
    {
        return buckets.getLenderInfo(index_, lender_);
    }

    function lpsToQuoteTokens(
        uint256 deposit_,
        uint256 lpTokens_,
        uint256 index_
    ) external view override returns (uint256 quoteTokenAmount_) {
        (quoteTokenAmount_, , ) = buckets.lpsToQuoteToken(
            deposit_,
            lpTokens_,
            deposit_,
            index_
        );
    }

    function loansInfo()
        external
        view
        override
        returns (
            address,
            uint256,
            uint256
        )
    {
        return (
            loans.getMax().borrower,
            Maths.wmul(loans.getMax().thresholdPrice, inflatorSnapshot),
            loans.noOfLoans()
        );
    }

    function reservesInfo()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256
        )
    {
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
}
