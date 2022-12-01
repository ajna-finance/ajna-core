// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';

import './interfaces/IPool.sol';
import './Storage.sol';

import '../libraries/Auctions.sol';
import '../libraries/Buckets.sol';
import '../libraries/Deposits.sol';
import '../libraries/Loans.sol';

contract Pool is Storage, Clone, ReentrancyGuard, Multicall, IPool {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

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

        uint256 newLup = _lup(poolState.accruedDebt); // move lup if necessary and check loan book's htp against new lup
        if (fromIndex_ < toIndex_) if(_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        Buckets.moveLPs(
            fromBucket,
            toBucket,
            fromBucketLPs_,
            toBucketLPs_
        );
        _updatePool(poolState, newLup);

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
        if (lenderLPsBalance == 0) revert NoClaim(); // revert if no LP to claim

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

        deposits.remove(index_, removedAmount_, deposit);  // update FenwickTree

        uint256 newLup = _lup(poolState.accruedDebt);
        if (_htp(poolState.inflator) > newLup) revert LUPBelowHTP();

        // update bucket LPs balance
        bucket.lps -= redeemedLPs_;
        // update lender LPs balance
        bucket.lenders[msg.sender].lps -= redeemedLPs_;

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
            if (indexes_[i] > 8192 ) revert InvalidIndex();

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
            _getPoolQuoteTokenBalance()
        );
        uint256 kickerAward = Maths.wmul(0.01 * 1e18, claimable);
        curUnclaimedAuctionReserve += claimable - kickerAward;
        if (curUnclaimedAuctionReserve != 0) {
            reserveAuctionUnclaimed = curUnclaimedAuctionReserve;
            reserveAuctionKicked    = block.timestamp;
            emit ReserveAuction(curUnclaimedAuctionReserve, PoolUtils.reserveAuctionPrice(block.timestamp));
            _transferQuoteToken(msg.sender, kickerAward);
        } else revert NoReserves();
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
        } else revert NoReservesAuction();
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

    function _updatePool(PoolState memory poolState_, uint256 lup_) internal {
        if (block.timestamp - interestRateUpdate > 12 hours) {
            // Update EMAs for target utilization

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

        pledgedCollateral = poolState_.collateral;

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
        uint256 pendingInflator = PoolUtils.pendingInflator(
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
     *  @param  index_   The bucket index from which LPB is attempting to be removed.
     *  @param  inflator_ The pool inflator used to properly assess t0DebtInAuction.
     */
    function _revertIfAuctionDebtLocked(
        uint256 index_,
        uint256 inflator_
    ) internal view {
        if (t0DebtInAuction != 0 ) {
            // deposit in buckets within liquidation debt from the top-of-book down are frozen.
            if (index_ <= deposits.findIndexOfSum(Maths.wmul(t0DebtInAuction, inflator_))) revert RemoveDepositLockedByAuctionDebt();
        } 
    }

}
