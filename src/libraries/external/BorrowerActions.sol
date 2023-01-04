// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import {
    PoolState,
    DepositsState,
    AuctionsState,
    DrawDebtResult,
    RepayDebtResult
} from '../../base/interfaces/IPool.sol';

import { _revertOnMinDebt } from '../../base/RevertsHelper.sol';

import './Auctions.sol';
import '../Buckets.sol';
import '../Deposits.sol';
import '../Loans.sol';

/**
    @notice External library containing logic for common borrower actions.
 */
library BorrowerActions {

    struct DrawDebtLocalVars {
        uint256 borrowerDebt; // borrower's accrued debt
        uint256 debtChange;   // additional debt resulted from draw debt action
        bool    inAuction;    // true if loan is auctioned
        uint256 lupId;        // id of new LUP
        bool    stampT0Np;    // true if loan's t0 neutral price should be restamped (when drawing debt or pledge settles auction)
    }

    struct RepayDebtLocalVars {
        uint256 borrowerDebt;          // borrower's accrued debt
        bool    inAuction;             // true if loan still in auction after repay, false otherwise
        uint256 newLup;                // LUP after repay debt action
        bool    pull;                  // true if pull action
        bool    repay;                 // true if repay action
        bool    stampT0Np;             // true if loan's t0 neutral price should be restamped (when repay settles auction or pull collateral)
        uint256 t0DebtInAuctionChange; // t0 change amount of debt after repayment
        uint256 t0RepaidDebt;          // t0 debt repaid
    }

    /**
     *  @notice Recipient of borrowed quote tokens doesn't match the caller of the drawDebt function.
     */
    error BorrowerNotSender();
    /**
     *  @notice Borrower is attempting to borrow more quote token than they have collateral for.
     */
    error BorrowerUnderCollateralized();
    /**
     *  @notice User is attempting to move or pull more collateral than is available.
     */
    error InsufficientCollateral();
    /**
     *  @notice Borrower is attempting to borrow more quote token than is available before the supplied limitIndex.
     */
    error LimitIndexReached();
    /**
     *  @notice Borrower has no debt to liquidate.
     *  @notice Borrower is attempting to repay when they have no outstanding debt.
     */
    error NoDebt();

    function drawDebt(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external returns (
        DrawDebtResult memory result_
    ) {
        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        result_.poolDebt       = poolState_.debt;
        result_.newLup         = _lup(deposits_, result_.poolDebt);
        result_.poolCollateral = poolState_.collateral;

        DrawDebtLocalVars memory vars;

        vars.borrowerDebt = Maths.wmul(borrower.t0Debt, poolState_.inflator);

        // pledge collateral to pool
        if (collateralToPledge_ != 0) {
            // add new amount of collateral to pledge to borrower balance
            borrower.collateral  += collateralToPledge_;

            // load loan's auction state
            vars.inAuction = _inAuction(auctions_, borrowerAddress_);
            // if loan is auctioned and becomes collateralized by newly pledged collateral then settle auction
            if (
                vars.inAuction &&
                _isCollateralized(vars.borrowerDebt, borrower.collateral, result_.newLup, poolState_.poolType)
            ) {
                // borrower becomes collateralized
                vars.inAuction = false;
                vars.stampT0Np = true;  // stamp borrower t0Np when exiting from auction

                result_.settledAuction = true;

                // remove debt from pool accumulator and settle auction
                result_.t0DebtInAuctionChange = borrower.t0Debt;

                // settle auction and update borrower's collateral with value after settlement
                result_.remainingCollateral = Auctions._settleAuction(
                    auctions_,
                    buckets_,
                    deposits_,
                    borrowerAddress_,
                    borrower.collateral,
                    poolState_.poolType
                );

                borrower.collateral = result_.remainingCollateral;
            }

            // add new amount of collateral to pledge to pool balance
            result_.poolCollateral += collateralToPledge_;
        }

        // borrow against pledged collateral
        // check both values to enable an intentional 0 borrow loan call to update borrower's loan state
        if (amountToBorrow_ != 0 || limitIndex_ != 0) {
            // only intended recipient can borrow quote
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();

            // add origination fee to the amount to borrow and add to borrower's debt
            vars.debtChange = Maths.wmul(amountToBorrow_, _feeRate(poolState_.rate) + Maths.WAD);

            vars.borrowerDebt += vars.debtChange;

            // check that drawing debt doesn't leave borrower debt under min debt amount
            _revertOnMinDebt(loans_, result_.poolDebt, vars.borrowerDebt, poolState_.quoteDustLimit);

            // add debt change to pool's debt
            result_.poolDebt += vars.debtChange;

            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            vars.lupId = _lupIndex(deposits_, result_.poolDebt);
            if (vars.lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            // this check also covers the scenario when loan is already auctioned
            result_.newLup = _priceAt(vars.lupId);

            if (!_isCollateralized(vars.borrowerDebt, borrower.collateral, result_.newLup, poolState_.poolType)) {
                revert BorrowerUnderCollateralized();
            }

            // stamp borrower t0Np when draw debt
            vars.stampT0Np = true;

            result_.t0DebtChange = Maths.wdiv(vars.debtChange, poolState_.inflator);

            borrower.t0Debt += result_.t0DebtChange;
        }

        // update loan state
        Loans.update(
            loans_,
            auctions_,
            deposits_,
            borrower,
            borrowerAddress_,
            vars.borrowerDebt,
            poolState_.rate,
            result_.newLup,
            vars.inAuction,
            vars.stampT0Np
        );
    }

    function repayDebt(
        AuctionsState storage auctions_,
        mapping(uint256 => Bucket) storage buckets_,
        DepositsState storage deposits_,
        LoansState    storage loans_,
        PoolState calldata poolState_,
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) external returns (
        RepayDebtResult memory result_
    ) {
        Borrower memory borrower = loans_.borrowers[borrowerAddress_];

        RepayDebtLocalVars memory vars;

        vars.repay        = maxQuoteTokenAmountToRepay_ != 0;
        vars.pull         = collateralAmountToPull_ != 0;
        vars.borrowerDebt = Maths.wmul(borrower.t0Debt, poolState_.inflator);

        result_.poolDebt       = poolState_.debt;
        result_.poolCollateral = poolState_.collateral;

        if (vars.repay) {
            if (borrower.t0Debt == 0) revert NoDebt();

            result_.t0RepaidDebt = Maths.min(
                borrower.t0Debt,
                Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState_.inflator)
            );

            result_.quoteTokenToRepay = Maths.wmul(result_.t0RepaidDebt, poolState_.inflator);

            result_.poolDebt -= result_.quoteTokenToRepay;
            vars.borrowerDebt -= result_.quoteTokenToRepay;

            // check that paying the loan doesn't leave borrower debt under min debt amount
            _revertOnMinDebt(loans_, result_.poolDebt, vars.borrowerDebt, poolState_.quoteDustLimit);

            result_.newLup = _lup(deposits_, result_.poolDebt);
            vars.inAuction = _inAuction(auctions_, borrowerAddress_);

            if (vars.inAuction) {
                if (_isCollateralized(vars.borrowerDebt, borrower.collateral, result_.newLup, poolState_.poolType)) {
                    // borrower becomes re-collateralized
                    vars.inAuction = false;
                    vars.stampT0Np = true;  // stamp borrower t0Np when exiting from auction

                    result_.settledAuction = true;

                    // remove entire borrower debt from pool auctions debt accumulator
                    result_.t0DebtInAuctionChange = borrower.t0Debt;

                    // settle auction and update borrower's collateral with value after settlement
                    result_.remainingCollateral = Auctions._settleAuction(
                        auctions_,
                        buckets_,
                        deposits_,
                        borrowerAddress_,
                        borrower.collateral,
                        poolState_.poolType
                    );

                    borrower.collateral = result_.remainingCollateral;
                } else {
                    // partial repay, remove only the paid debt from pool auctions debt accumulator
                    result_.t0DebtInAuctionChange = result_.t0RepaidDebt;
                }
            }

            borrower.t0Debt -= result_.t0RepaidDebt;
        }

        if (vars.pull) {
            // only intended recipient can pull collateral
            if (borrowerAddress_ != msg.sender) revert BorrowerNotSender();

            // calculate LUP only if it wasn't calculated by repay action
            if (!vars.repay) result_.newLup = _lup(deposits_, result_.poolDebt);

            uint256 encumberedCollateral = borrower.t0Debt != 0 ? Maths.wdiv(vars.borrowerDebt, result_.newLup) : 0;

            if (borrower.collateral - encumberedCollateral < collateralAmountToPull_) revert InsufficientCollateral();

            // stamp borrower t0Np when pull collateral action
            vars.stampT0Np = true;

            borrower.collateral    -= collateralAmountToPull_;
            result_.poolCollateral -= collateralAmountToPull_;
        }

        // calculate LUP if repay is called with 0 amount
        if (!vars.repay && !vars.pull) {
            result_.newLup = _lup(deposits_, result_.poolDebt);
        }

        // update loan state
        Loans.update(
            loans_,
            auctions_,
            deposits_,
            borrower,
            borrowerAddress_,
            vars.borrowerDebt,
            poolState_.rate,
            result_.newLup,
            vars.inAuction,
            vars.stampT0Np
        );
    }

    /**
     *  @notice Returns true if borrower is in auction.
     *  @dev    Used to accuratley increment and decrement t0DebtInAuction.
     *  @param  borrower_ Borrower address to check auction status for.
     *  @return  active_ Boolean, based on if borrower is in auction.
     */
    function _inAuction(
        AuctionsState storage auctions_,
        address borrower_
    ) internal view returns (bool) {
        return auctions_.liquidations[borrower_].kickTime != 0;
    }

    function _lupIndex(
        DepositsState storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return Deposits.findIndexOfSum(deposits_, debt_);
    }

    function _lup(
        DepositsState storage deposits_,
        uint256 debt_
    ) internal view returns (uint256) {
        return _priceAt(_lupIndex(deposits_, debt_));
    }

}
