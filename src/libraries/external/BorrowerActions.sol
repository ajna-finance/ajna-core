// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import {
    PoolState,
    DepositsState,
    AuctionsState,
    DrawDebtResult
} from '../../base/interfaces/IPool.sol';

import './Auctions.sol';
import '../Buckets.sol';
import '../Deposits.sol';
import '../Loans.sol';

/**
    @notice External library containing logic for common borrower actions.
 */
library BorrowerActions {

    struct DrawDebtLocalVars {
        uint256 borrowerDebt;
        bool    inAuction;
        uint256 lupId;
        uint256 debtChange;
    }

    /**
     *  @notice Borrower is attempting to create or modify a loan such that their loan's quote token would be less than the pool's minimum debt amount.
     */
    error AmountLTMinDebt();

    /**
     *  @notice Recipient of borrowed quote tokens doesn't match the caller of the drawDebt function.
     */
    error BorrowerNotSender();

    /**
     *  @notice Borrower is attempting to borrow more quote token than they have collateral for.
     */
    error BorrowerUnderCollateralized();

    /**
     *  @notice Borrower is attempting to borrow more quote token than is available before the supplied limitIndex.
     */
    error LimitIndexReached();

    event AuctionNFTSettle(
        address indexed borrower,
        uint256 collateral,
        uint256 lps,
        uint256 index
    );

    event AuctionSettle(
        address indexed borrower,
        uint256 collateral
    );

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
        Borrower memory borrower = Loans.getBorrowerInfo(loans_, borrowerAddress_);

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
            vars.inAuction = Auctions.isActive(auctions_, borrowerAddress_);
            // if loan is auctioned and becomes collateralized by newly pledged collateral then settle auction
            if (
                vars.inAuction
                &&
                _isCollateralized(vars.borrowerDebt, borrower.collateral, result_.newLup, poolState_.poolType)
            )
            {
                // borrower becomes collateralized, remove debt from pool accumulator and settle auction
                result_.t0DebtInAuctionChange = borrower.t0Debt;

                if (poolState_.poolType == uint8(PoolType.ERC721)) {
                    uint256 lps;
                    uint256 bucketIndex;
                    (result_.settledCollateral, lps, bucketIndex) = Auctions.settleNFTAuction(
                        auctions_,
                        buckets_,
                        deposits_,
                        borrowerAddress_,
                        borrower.collateral
                    );
                    borrower.collateral = result_.settledCollateral;
                    emit AuctionNFTSettle(borrowerAddress_, result_.settledCollateral, lps, bucketIndex);
                } else {
                    Auctions._removeAuction(auctions_, borrowerAddress_);
                    emit AuctionSettle(borrowerAddress_, borrower.collateral);
                }

                // auction was settled, reset inAuction flag
                vars.inAuction = false;
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
            vars.debtChange   = Maths.wmul(amountToBorrow_, _feeRate(poolState_.rate) + Maths.WAD);
            vars.borrowerDebt += vars.debtChange;

            // check that drawing debt doesn't leave borrower debt under min debt amount
            _revertOnMinDebt(loans_, result_.poolDebt, vars.borrowerDebt);

            // add debt change to pool's debt
            result_.poolDebt += vars.debtChange;
            // determine new lup index and revert if borrow happens at a price higher than the specified limit (lower index than lup index)
            vars.lupId = _lupIndex(deposits_, result_.poolDebt);
            if (vars.lupId > limitIndex_) revert LimitIndexReached();

            // calculate new lup and check borrow action won't push borrower into a state of under-collateralization
            // this check also covers the scenario when loan is already auctioned
            result_.newLup = _priceAt(vars.lupId);
            if (
                !_isCollateralized(vars.borrowerDebt, borrower.collateral, result_.newLup, poolState_.poolType)
            ) revert BorrowerUnderCollateralized();

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
            true
        );
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

    function _revertOnMinDebt(LoansState storage loans_, uint256 poolDebt_, uint256 borrowerDebt_) internal view {
        if (borrowerDebt_ != 0) {
            uint256 loansCount = Loans.noOfLoans(loans_);
            if (
                loansCount >= 10
                &&
                (borrowerDebt_ < _minDebtAmount(poolDebt_, loansCount))
            ) revert AmountLTMinDebt();
        }
    }

}
