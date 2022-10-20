// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import "forge-std/console.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/IPool.sol';

import '../libraries/Auctions.sol';
import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';
import '../libraries/Maths.sol';
import '../libraries/PoolUtils.sol';

abstract contract Pool is Clone, Multicall, IPool {
    using SafeERC20 for ERC20;

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

    uint256 public override inflatorSnapshot;           // [WAD]
    uint256 public override lastInflatorSnapshotUpdate; // [SEC]
    uint256 public override minFee;                     // [WAD]
    uint256 public override interestRate;               // [WAD]
    uint256 public override interestRateUpdate;         // [SEC]

    uint256 public override quoteTokenScale;
    uint256 public override pledgedCollateral; // [WAD]

    uint256 public override debtEma;      // [WAD]
    uint256 public override lupColEma;    // [WAD]

    uint256 public override reserveAuctionKicked;    // Time a Claimable Reserve Auction was last kicked.
    uint256 public override reserveAuctionUnclaimed; // Amount of claimable reserves which has not been taken in the Claimable Reserve Auction.

    mapping(uint256 => Buckets.Bucket)              public override buckets;     // deposit index -> bucket
    mapping(address => mapping(address => mapping(uint256 => uint256))) private _lpTokenAllowances; // owner address -> new owner address -> deposit index -> allowed amount

    Auctions.Data internal auctions;
    Deposits.Data internal deposits;
    Loans.Data    internal loans;
    address       internal ajnaTokenAddress;    // Address of the Ajna token, needed for Claimable Reserve Auctions.
    uint256       internal poolInitializations;
    uint256       internal t0poolDebt;          // Pool debt as if the whole amount was incurred upon the first loan. [WAD]

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
        _updatePool(poolState, 0, newLup);

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
            minFee,
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
        _updatePool(poolState, 0, newLup);

        emit MoveQuoteToken(msg.sender, fromIndex_, toIndex_, quoteTokenAmountToMove, newLup);
    }

    function removeAllQuoteToken(
        uint256 index_
    ) external returns (uint256 quoteTokenAmountRemoved_, uint256 redeemedLenderLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(
            index_,
            msg.sender
        );
        if (lenderLPsBalance == 0) revert NoClaim();

        uint256 deposit = deposits.valueAt(index_);
        (quoteTokenAmountRemoved_, , redeemedLenderLPs_) = buckets.lpsToQuoteToken(
            deposit,
            lenderLPsBalance,
            deposit,
            index_
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
        if (quoteTokenAmountToRemove_ > deposit) revert InsufficientLiquidity();

        bucketLPs_ = buckets.quoteTokensToLPs(
            deposit,
            quoteTokenAmountToRemove_,
            index_
        );

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        if (lenderLPsBalance == 0 || bucketLPs_ > lenderLPsBalance) revert InsufficientLPs();

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


    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function borrow(
        uint256 amountToBorrow_,
        uint256 limitIndex_
    ) external override {

        // if borrower auctioned then it cannot draw more debt
        (bool auctionKicked, ) = auctions.getStatus(msg.sender);
        if (auctionKicked) revert AuctionActive();

        PoolState memory poolState = _accruePoolInterest();

        uint256 lupId = _lupIndex(poolState.accruedDebt + amountToBorrow_);
        if (lupId > limitIndex_) revert LimitIndexReached();

        Loans.Borrower memory borrower = loans.getBorrowerInfo(msg.sender);
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);
        uint256 loansCount = loans.noOfLoans();
        if (
            loansCount >= 10
            &&
            (borrowerDebt + amountToBorrow_ < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
        )  revert AmountLTMinDebt();

        // increase debt by the origination fee
        // TODO: rename these to indicate they measure the *change* in debt
        uint256 debt = Maths.wmul(amountToBorrow_, PoolUtils.feeRate(interestRate, minFee) + Maths.WAD);
        require(debt < uint256(type(int256).max), "BORROWER-DEBT-OVERFLOW");   // TODO: make custom error
        int256 t0debt = int256(Maths.wdiv(debt, poolState.inflator));
        borrowerDebt += debt;

        // FIXME: newLup should be calculated on debt including origination fee
        uint256 newLup = PoolUtils.indexToPrice(lupId);

        // check borrow won't push borrower into a state of under-collateralization
        if (
            _collateralization(borrowerDebt, borrower.collateral, newLup) < Maths.WAD
            ||
            borrower.collateral == 0
        ) revert BorrowerUnderCollateralized();

        // check borrow won't push pool into a state of under-collateralization
        poolState.accruedDebt += debt;
        if (_collateralization(poolState.accruedDebt, poolState.collateral, newLup) < Maths.WAD) revert PoolUnderCollateralized();

        loans.update(
            deposits,
            msg.sender,
            borrower,
            t0debt,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, t0debt, newLup);

        // move borrowed amount from pool to sender
        emit Borrow(msg.sender, newLup, amountToBorrow_);
        quoteToken().safeTransfer(msg.sender, amountToBorrow_ / quoteTokenScale);
    }

    function repay(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_
    ) external override {

        PoolState memory poolState = _accruePoolInterest();

        Loans.Borrower memory borrower = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.t0debt == 0) revert NoDebt();
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);

        uint256 quoteTokenAmountToRepay = Maths.min(borrowerDebt, maxQuoteTokenAmountToRepay_);
        int256 t0repaid       = int256(Maths.wdiv(quoteTokenAmountToRepay, poolState.inflator)) * -1;
        borrowerDebt          -= quoteTokenAmountToRepay;
        poolState.accruedDebt        -= quoteTokenAmountToRepay;

        if (borrowerDebt != 0) {
            uint256 loansCount = loans.noOfLoans();
            if (loansCount >= 10
                &&
                (borrowerDebt < PoolUtils.minDebtAmount(poolState.accruedDebt, loansCount))
            ) revert AmountLTMinDebt();
        }

        uint256 newLup = _lup(poolState.accruedDebt);

        auctions.checkAndRemove(
            borrowerAddress_,
            _collateralization(borrowerDebt, borrower.collateral, newLup)
        );
        loans.update(
            deposits,
            borrowerAddress_,
            borrower,
            t0repaid,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, t0repaid, newLup);

        // move amount to repay from sender to pool
        emit Repay(borrowerAddress_, newLup, quoteTokenAmountToRepay);
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenAmountToRepay / quoteTokenScale);
    }


    /*****************************/
    /*** Liquidation Functions ***/
    /*****************************/

    function kick(address borrowerAddress_) external override {

        (bool auctionKicked, ) = auctions.getStatus(borrowerAddress_);
        if (auctionKicked) revert AuctionActive();

        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.t0debt == 0) revert NoDebt();

        uint256 lup = _lup(poolState.accruedDebt);
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);
        if (_collateralization(borrowerDebt, borrower.collateral, lup) >= Maths.WAD) revert BorrowerOk();

        poolState.accruedDebt += loans.kick(
                borrowerAddress_,
                borrower.debt,
                poolState.inflator,
                poolState.rate
            );

        // kick auction
        uint256 kickAuctionAmount = auctions.kick(
            borrowerAddress_,
            borrower.debt,
            borrower.debt * Maths.WAD / borrower.collateral,
            deposits.momp(poolState.accruedDebt, loans.noOfLoans())
        );

        // update pool state
        _updatePool(poolState, 0, lup);

        emit Kick(borrowerAddress_, borrowerDebt, borrower.collateral);
        quoteToken().safeTransferFrom(msg.sender, address(this), kickAuctionAmount / quoteTokenScale);
    }


    /*********************************/
    /*** Reserve Auction Functions ***/
    /*********************************/

    function startClaimableReserveAuction() external override {
        uint256 curUnclaimedAuctionReserve = reserveAuctionUnclaimed;
        uint256 claimable = PoolUtils.claimableReserves(
            Maths.wmul(t0poolDebt, inflatorSnapshot),
            deposits.treeSum(),
            auctions.liquidationBondEscrowed,
            curUnclaimedAuctionReserve,
            quoteToken().balanceOf(address(this))
        );
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward;
        if (curUnclaimedAuctionReserve == 0) revert NoReserves();

        reserveAuctionUnclaimed = curUnclaimedAuctionReserve;
        reserveAuctionKicked    = block.timestamp;
        emit ReserveAuction(curUnclaimedAuctionReserve, PoolUtils.reserveAuctionPrice(block.timestamp));
        quoteToken().safeTransfer(msg.sender, kickerAward / quoteTokenScale);
    }

    function takeReserves(uint256 maxAmount_) external override returns (uint256 amount_) {
        uint256 kicked = reserveAuctionKicked;
        if (kicked == 0 || block.timestamp - kicked > 72 hours) revert NoReservesAuction();

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
            _collateralization(Maths.wmul(borrower.t0debt, poolState.inflator) , borrower.collateral, newLup)
        );
        loans.update(
            deposits,
            borrowerAddress_,
            borrower,
            0,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, 0, newLup);
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
            0,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, 0, curLup);
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
        _updatePool(poolState, 0, _lup(poolState.accruedDebt));
    }

    function _removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {

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

        _updatePool(poolState, 0, _lup(poolState.accruedDebt));
    }

    function _redeemLPForQuoteToken(
        uint256 index_,
        PoolState memory poolState_,
        uint256 lpAmount_,
        uint256 amount
    ) internal {
        deposits.remove(index_, amount);  // update FenwickTree

        uint256 newLup = _lup(poolState_.accruedDebt);
        if (_htp(poolState_.inflator) > newLup) revert LUPBelowHTP();

        // persist bucket changes
        buckets.removeLPs(lpAmount_, index_);

        (, uint256 lastDeposit) = buckets.getLenderInfo(index_, msg.sender);
        amount = PoolUtils.applyEarlyWithdrawalPenalty(
            poolState_,
            minFee,
            lastDeposit,
            index_,
            0,
            amount
        );

        _updatePool(poolState_, 0, newLup);

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
     *  @param borrowerAddress_   Address of the borower take is being called upon.
     *  @param collateral_        Max amount of collateral to take, submited by the taker.
     *  @return collateralTaken_  Amount of collateral taken from the auction and sent to the taker.
     */
    function _take(
        address borrowerAddress_,
        uint256 collateral_
    ) internal returns(uint256) {

        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0) revert InsufficientCollateral();

        (
            uint256 quoteTokenAmount,
            uint256 repayAmount,
            uint256 collateralTaken,
            uint256 bondChange,
            bool isRewarded
        ) = auctions.take(borrowerAddress_, borrower, collateral_, poolState.inflator);

        int256  t0repaid      = int256(Maths.wdiv(repayAmount, poolState.inflator)) * -1;
        uint256 borrowerDebt  = Maths.wmul(borrower.t0debt, poolState.inflator) - repayAmount;
        borrower.collateral   -= collateralTaken;
        poolState.accruedDebt -= repayAmount;
        poolState.collateral  -= collateralTaken;

        // check that take doesn't leave borrower debt under min debt amount
        if (
            borrower.t0debt != 0
            &&
            borrowerDebt < PoolUtils.minDebtAmount(poolState.accruedDebt, loans.noOfLoans())
        ) revert AmountLTMinDebt();

        uint256 newLup = _lup(poolState.accruedDebt);

        auctions.checkAndRemove(
            borrowerAddress_,
            _collateralization(borrowerDebt, borrower.collateral, newLup)
        );
        loans.update(
            deposits,
            borrowerAddress_,
            borrower,
            t0repaid,
            poolState.accruedDebt,
            poolState.inflator
        );
        _updatePool(poolState, t0repaid, newLup);

        emit Take(borrowerAddress_, quoteTokenAmount, collateralTaken, bondChange, isRewarded);
        quoteToken().safeTransferFrom(msg.sender, address(this), quoteTokenAmount / quoteTokenScale);
        return collateralTaken;
    }


    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _accruePoolInterest() internal returns (PoolState memory poolState_) {
        poolState_.collateral  = pledgedCollateral;
        poolState_.inflator    = inflatorSnapshot;
        // TODO: when new interest has accrued, this gets overwriten, wasting a storage read and multiplication
        poolState_.accruedDebt = Maths.wmul(t0poolDebt, poolState_.inflator);

        if (t0poolDebt != 0) {
            uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
            poolState_.isNewInterestAccrued = elapsed != 0;
            if (poolState_.isNewInterestAccrued) {
                poolState_.rate = interestRate;
                uint256 factor = PoolUtils.pendingInterestFactor(poolState_.rate, elapsed);
                // Scale the borrower inflator to update amount of interest owed by borrowers
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

                // Calculate pool debt using the new inflator
                poolState_.accruedDebt = Maths.wmul(t0poolDebt, poolState_.inflator);
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

    function _updatePool(PoolState memory poolState_, int256 t0debtChange_, uint256 lup_) internal {
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

            if (_collateralization(poolState_.accruedDebt, poolState_.collateral, lup_) != Maths.WAD) {

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

        // TODO: inefficient; would like to mutate this with a += in borrow, -= in repay
        t0poolDebt        = Maths.uadd(t0poolDebt, t0debtChange_);
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

    function borrowers(address borrower_) external view override returns (uint256, uint256, uint256) {
        uint256 pendingInflator = PoolUtils.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);
        return (
            Maths.wmul(loans.borrowers[borrower_].t0debt, pendingInflator),
            loans.borrowers[borrower_].collateral,
            loans.borrowers[borrower_].mompFactor
        );
    }

    function bucketDeposit(uint256 index_) external view override returns (uint256) {
        return deposits.valueAt(index_);
    }

    function bucketScale(uint256 index_) external view override returns (uint256) {
        return deposits.scale(index_);
    }

    function collateralAddress() external pure override returns (address) {
        return _getArgAddress(0);
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

    function kickers(address kicker_) external view override returns (uint256, uint256) {
        return(
            auctions.kickers[kicker_].claimable,
            auctions.kickers[kicker_].locked
        );
    }

    function lenders(uint256 index_, address lender_) external view override returns (uint256, uint256) {
        return buckets.getLenderInfo(index_, lender_);
    }

    function liquidationBondEscrowed() external view override returns (uint256) {
        return auctions.liquidationBondEscrowed;
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

    function maxBorrower() external view override returns (address) {
        return loans.getMax().borrower;
    }

    function maxThresholdPrice() external view override returns (uint256) {
        return loans.getMax().thresholdPrice;
    }

    function noOfLoans() external view override returns (uint256) {
        return loans.noOfLoans();
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
