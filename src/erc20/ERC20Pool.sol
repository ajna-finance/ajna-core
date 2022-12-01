// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@clones/Clone.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';

import './interfaces/IERC20Pool.sol';
import './interfaces/IERC20Taker.sol';
import '../base/FlashloanablePool.sol';
import '../base/Storage.sol';

contract ERC20Pool is Storage, IERC20Pool, Clone, ReentrancyGuard {
    using Auctions for Auctions.Data;
    using Buckets  for mapping(uint256 => Buckets.Bucket);
    using Deposits for Deposits.Data;
    using Loans    for Loans.Data;

    /***********************/
    /*** State Variables ***/
    /***********************/

    uint128 public override collateralScale;
    address immutable public pool;

    struct PoolState {
        uint256 accruedDebt;
        uint256 collateral;
        bool    isNewInterestAccrued;
        uint256 rate;
        uint256 inflator;
    }

    constructor(address pool_) {
        pool = pool_;
    }

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(
        uint256 collateralScale_,
        uint256 rate_
    ) external override {
        if (poolInitializations != 0) revert AlreadyInitialized();

        collateralScale = uint128(collateralScale_);

        inflatorSnapshot           = uint208(10**18);
        lastInflatorSnapshotUpdate = uint48(block.timestamp);
        interestRate               = uint208(rate_);
        interestRateUpdate         = uint48(block.timestamp);

        loans.init();

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    function pledgeCollateral(
        address borrower_,
        uint256 collateralAmountToPledge_
    ) external override {
        _pledgeCollateral(borrower_, collateralAmountToPledge_);

        // move collateral from sender to pool
        emit PledgeCollateral(borrower_, collateralAmountToPledge_);
        _transferCollateralFrom(msg.sender, collateralAmountToPledge_);
    }

    function pullCollateral(
        uint256 collateralAmountToPull_
    ) external override {
        _pullCollateral(collateralAmountToPull_);

        // move collateral from pool to sender
        emit PullCollateral(msg.sender, collateralAmountToPull_);
        _transferCollateral(msg.sender, collateralAmountToPull_);
    }

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
            !_isCollateralized(
                borrowerDebt,
                borrower.collateral,
                newLup
            )
            ||
            borrower.collateral == 0
        ) revert BorrowerUnderCollateralized();

        // check borrow won't push pool into a state of under-collateralization
        poolState.accruedDebt += debtChange;
        if (
            !_isCollateralized(
                poolState.accruedDebt,
                poolState.collateral,
                newLup
            )
        ) revert PoolUnderCollateralized();

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

        uint256 t0repaidDebt = Maths.min(
            borrower.t0debt,
            Maths.wdiv(maxQuoteTokenAmountToRepay_, poolState.inflator)
        );
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
        t0poolDebt           -= t0settledDebt;
        t0DebtInAuction      -= t0settledDebt;
        poolState.collateral -= borrower.collateral - remainingCollateral;

        borrower.t0debt     = remainingt0Debt;
        borrower.collateral = remainingCollateral;

        _updatePool(poolState, _lup(poolState.accruedDebt));

        emit Settle(borrowerAddress_, t0settledDebt);
    }

    function kick(address borrowerAddress_) external override {
        auctions.revertIfActive(borrowerAddress_);

        Loans.Borrower storage borrower = loans.borrowers[borrowerAddress_];

        PoolState memory poolState = _accruePoolInterest();

        uint256 lup = _lup(poolState.accruedDebt);
        uint256 borrowerDebt = Maths.wmul(borrower.t0debt, poolState.inflator);
        if (
            _isCollateralized(
                borrowerDebt,
                borrower.collateral,
                lup
            )
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

        // update loan heap
        loans.remove(borrowerAddress_);

        // update borrower & pool debt with kickPenalty
        uint256 kickPenalty   =  Maths.wmul(Maths.wdiv(poolState.rate, 4 * 1e18), borrowerDebt); // when loan is kicked, penalty of three months of interest is added
        borrowerDebt          += kickPenalty;
        poolState.accruedDebt += kickPenalty; 

        kickPenalty     =  Maths.wdiv(kickPenalty, poolState.inflator); // convert to t0
        borrower.t0debt += kickPenalty;
        t0poolDebt      += kickPenalty;
        t0DebtInAuction += borrower.t0debt;

        // update pool state
        _updatePool(poolState, lup);

        emit Kick(borrowerAddress_, borrowerDebt, borrower.collateral, bondSize);
        if(kickAuctionAmount != 0) _transferQuoteTokenFrom(msg.sender, kickAuctionAmount);
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function addCollateral(
        uint256 collateralAmountToAdd_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _addCollateral(collateralAmountToAdd_, index_);

        // move required collateral from sender to pool
        emit AddCollateral(msg.sender, index_, collateralAmountToAdd_);
        _transferCollateralFrom(msg.sender, collateralAmountToAdd_);
    }

    function removeAllCollateral(
        uint256 index_
    ) external override returns (uint256 collateralAmountRemoved_, uint256 redeemedLenderLPs_) {
        auctions.revertIfAuctionClearable(loans);

        (uint256 lenderLPsBalance, ) = buckets.getLenderInfo(
            index_,
            msg.sender
        );

        PoolState memory poolState = _accruePoolInterest();

        Buckets.Bucket storage bucket = buckets[index_];
        (collateralAmountRemoved_, redeemedLenderLPs_) = Buckets.lpsToCollateral(
            bucket.collateral,
            bucket.lps,
            deposits.valueAt(index_),
            lenderLPsBalance,
            PoolUtils.indexToPrice(index_)
        );
        if (collateralAmountRemoved_ == 0) revert NoClaim();

        Buckets.removeCollateral(
            bucket,
            collateralAmountRemoved_,
            redeemedLenderLPs_)
        ;

        _updatePool(poolState, _lup(poolState.accruedDebt));

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountRemoved_);
        _transferCollateral(msg.sender, collateralAmountRemoved_);
    }

    function removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) external override returns (uint256 bucketLPs_) {
        bucketLPs_ = _removeCollateral(collateralAmountToRemove_, index_);

        // move collateral from pool to lender
        emit RemoveCollateral(msg.sender, index_, collateralAmountToRemove_);
        _transferCollateral(msg.sender, collateralAmountToRemove_);
    }

    /*******************************/
    /*** Pool External Functions ***/
    /*******************************/

    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState      memory poolState = _accruePoolInterest();
        Loans.Borrower memory borrower  = loans.getBorrowerInfo(borrowerAddress_);
        if (borrower.collateral == 0 || collateral_ == 0) revert InsufficientCollateral(); // revert if borrower's collateral is 0 or if maxCollateral to be taken is 0

        Auctions.TakeParams memory params = Auctions.take(
            auctions,
            borrowerAddress_,
            borrower,
            collateral_,
            poolState.inflator
        );

        borrower.collateral  -= params.collateralAmount;
        poolState.collateral -= params.collateralAmount;

        emit Take(
            borrowerAddress_,
            params.quoteTokenAmount,
            params.collateralAmount,
            params.bondChange,
            params.isRewarded
        );

        _payLoan(params.t0repayAmount, poolState, borrowerAddress_, borrower);

        _transferCollateral(callee_, params.collateralAmount);

        if (data_.length != 0) {
            IERC20Taker(callee_).atomicSwapCallback(
                params.collateralAmount / collateralScale, 
                params.quoteTokenAmount / _getArgUint256(40), 
                data_
            );
        }

        _transferQuoteTokenFrom(callee_, params.quoteTokenAmount);
    }

    /*******************************/
    /*** Pool Override Functions ***/
    /*******************************/

    /**
     *  @notice ERC20 collateralization calculation.
     *  @param debt_       Debt to calculate collateralization for.
     *  @param collateral_ Collateral to calculate collateralization for.
     *  @param price_      Price to calculate collateralization for.
     *  @return True if collateralization calculated is equal or greater than 1.
     */
    function _isCollateralized(
        uint256 debt_,
        uint256 collateral_,
        uint256 price_
    ) internal pure returns (bool) {
        return Maths.wmul(collateral_, price_) >= debt_;
    }

   /**
     *  @notice Settle an ERC20 pool auction, remove from auction queue and emit event.
     *  @param borrowerAddress_    Address of the borrower that exits auction.
     *  @param borrowerCollateral_ Borrower collateral amount before auction exit.
     *  @return floorCollateral_   Remaining borrower collateral after auction exit.
     */
    function _settleAuction(
        address borrowerAddress_,
        uint256 borrowerCollateral_
    ) internal returns (uint256) {
        Auctions.settleERC20Auction(auctions, borrowerAddress_);
        emit AuctionSettle(borrowerAddress_, borrowerCollateral_);
        return borrowerCollateral_;
    }


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
        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

    function _removeCollateral(
        uint256 collateralAmountToRemove_,
        uint256 index_
    ) internal returns (uint256 bucketLPs_) {
        auctions.revertIfAuctionClearable(loans);

        Buckets.Bucket storage bucket = buckets[index_];
        if (collateralAmountToRemove_ > bucket.collateral) revert InsufficientCollateral();

        PoolState memory poolState = _accruePoolInterest();
        
        bucketLPs_ = Buckets.collateralToLPs(
            bucket.collateral,
            bucket.lps,
            deposits.valueAt(index_),
            collateralAmountToRemove_,
            PoolUtils.indexToPrice(index_)
        );

        (uint256 lenderLpBalance, ) = buckets.getLenderInfo(index_, msg.sender);
        if (lenderLpBalance == 0 || bucketLPs_ > lenderLpBalance) revert InsufficientLPs(); // ensure user can actually remove that much

        Buckets.removeCollateral(
            bucket,
            collateralAmountToRemove_,
            bucketLPs_
        );

        _updatePool(poolState, _lup(poolState.accruedDebt));
    }

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
            _isCollateralized(
                Maths.wmul(borrower.t0debt, poolState.inflator),
                borrower.collateral,
                newLup
            ) && auctions.isActive(borrowerAddress_)) { // borrower becomes collateralized, settle auction
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
            true,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            curLup
        );
        _updatePool(poolState, curLup);
    }

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

        _checkMinDebt(poolState.accruedDebt, borrowerDebt); // check that repay or take doesn't leave borrower debt under min debt amount

        newLup_ = _lup(poolState.accruedDebt);

        if (auctions.isActive(borrowerAddress)) {
            if (_isCollateralized(borrowerDebt, borrower.collateral, newLup_)) {            // borrower becomes collateralized, settle auction
                t0DebtInAuction     -= borrower.t0debt;                                     // remove entire borrower debt from pool accumulator
                borrower.collateral = _settleAuction(borrowerAddress, borrower.collateral); // settle auction and update borrower's collateral with value after settlement
            } else {
                t0DebtInAuction -= t0repaidDebt;                                            // partial repaid, remove only the paid debt
            }
        }
        
        borrower.t0debt -= t0repaidDebt;
        loans.update(
            deposits,
            borrowerAddress,
            false,
            borrower,
            poolState.accruedDebt,
            poolState.inflator,
            poolState.rate,
            newLup_
        );
        _updatePool(poolState, newLup_);
        t0poolDebt -= t0repaidDebt;
    }

    function _htp(uint256 inflator_) internal view returns (uint256) {
        return Maths.wmul(loans.getMax().thresholdPrice, inflator_);
    }

    function _lup(uint256 debt_) internal view returns (uint256) {
        return PoolUtils.indexToPrice(_lupIndex(debt_));
    }

    function _lupIndex(uint256 debt_) internal view returns (uint256) {
        return deposits.findIndexOfSum(debt_);
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

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _transferCollateralFrom(address from_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(0)).transferFrom(from_, address(this), amount_ / collateralScale)) revert ERC20TransferFailed();
    }

    function _transferCollateral(address to_, uint256 amount_) internal {
        if (!IERC20Token(_getArgAddress(0)).transfer(to_, amount_ / collateralScale)) revert ERC20TransferFailed();
    }


    /************************/
    /***     Fallback     ***/
    /************************/

    fallback() external {
        address facetAddress = pool;
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facetAddress, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
                case 0 {
                    revert(0, returndatasize())
                }
                default {
                    return(0, returndatasize())
                }
        }
    }

}
