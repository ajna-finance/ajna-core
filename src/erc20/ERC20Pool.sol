// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 }    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    IERC20Pool,
    IERC20PoolBorrowerActions,
    IERC20PoolImmutables,
    IERC20PoolLenderActions
}  from 'src/erc20/interfaces/IERC20Pool.sol';
import { IPoolLenderActions, IPoolLiquidationActions } from 'src/base/interfaces/IPool.sol';
import { IERC20Taker } from 'src/erc20/interfaces/IERC20Taker.sol';
import {
    IERC3156FlashBorrower,
    IERC3156FlashLender
} from 'src/base/interfaces/IERC3156FlashLender.sol';
import { IERC20Token } from 'src/base/interfaces/IPool.sol';
import { PoolState }   from 'src/base/interfaces/pool/IPoolState.sol';
import {
    DrawDebtResult,
    BucketTakeResult,
    RepayDebtResult,
    SettleParams,
    TakeResult
} from 'src/base/interfaces/pool/IPoolInternals.sol';

import { FlashloanablePool }         from 'src/base/FlashloanablePool.sol';
import { _revertIfAuctionClearable } from 'src/base/RevertsHelper.sol';

import { Loans }    from 'src/libraries/Loans.sol';
import { Deposits } from 'src/libraries/Deposits.sol';
import { Maths }    from 'src/libraries/Maths.sol';

import { BorrowerActions } from 'src/libraries/external/BorrowerActions.sol';
import { LenderActions }   from 'src/libraries/external/LenderActions.sol';
import { Auctions }        from 'src/libraries/external/Auctions.sol';

contract ERC20Pool is IERC20Pool, FlashloanablePool {
    using SafeERC20 for IERC20;

    /*****************/
    /*** Constants ***/
    /*****************/

    // immutable args offset
    uint256 internal constant COLLATERAL_SCALE = 93;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    /// @inheritdoc IERC20Pool
    function initialize(
        uint256 rate_
    ) external override {
        if (isPoolInitialized) revert AlreadyInitialized();

        inflatorState.inflator       = uint208(1e18);
        inflatorState.inflatorUpdate = uint48(block.timestamp);

        interestState.interestRate       = uint208(rate_);
        interestState.interestRateUpdate = uint48(block.timestamp);

        Loans.init(loans);

        // increment initializations count to ensure these values can't be updated
        isPoolInitialized = true;
    }

    /******************/
    /*** Immutables ***/
    /******************/

    /// @inheritdoc IERC20PoolImmutables
    function collateralScale() external pure override returns (uint256) {
        return _getArgUint256(COLLATERAL_SCALE);
    }

    /// @inheritdoc IERC20PoolImmutables
    function collateralDust(uint256 bucketIndex) external view override returns (uint256) {
        return _collateralDust(bucketIndex);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /// @inheritdoc IERC20PoolBorrowerActions
    function drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        // ensure the borrower is not credited with a fractional amount of collateral smaller than the token scale
        collateralToPledge_ = _roundToScale(collateralToPledge_, _collateralDust(0));

        DrawDebtResult memory result = BorrowerActions.drawDebt(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            amountToBorrow_,
            limitIndex_,
            collateralToPledge_
        );

        emit DrawDebt(borrowerAddress_, amountToBorrow_, collateralToPledge_, result.newLup);

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.collateral = result.poolCollateral;
        _updateInterestState(poolState, result.newLup);

        if (collateralToPledge_ != 0) {
            // update pool balances state
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= result.t0DebtInAuctionChange;
            }
            poolBalances.pledgedCollateral += collateralToPledge_;

            // move collateral from sender to pool
            _transferCollateralFrom(msg.sender, collateralToPledge_);
        }

        if (amountToBorrow_ != 0) {
            // update pool balances state
            poolBalances.t0Debt += result.t0DebtChange;

            // move borrowed amount from pool to sender
            _transferQuoteToken(msg.sender, amountToBorrow_);
        }
    }

    /// @inheritdoc IERC20PoolBorrowerActions
    function repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        RepayDebtResult memory result = BorrowerActions.repayDebt(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            maxQuoteTokenAmountToRepay_,
            collateralAmountToPull_,
            _collateralDust(0)
        );

        emit RepayDebt(borrowerAddress_, result.quoteTokenToRepay, collateralAmountToPull_, result.newLup);

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.collateral = result.poolCollateral;
        _updateInterestState(poolState, result.newLup);

        if (result.quoteTokenToRepay != 0) {
            // update pool balances state
            poolBalances.t0Debt -= result.t0RepaidDebt;
            if (result.t0DebtInAuctionChange != 0) {
                poolBalances.t0DebtInAuction -= result.t0DebtInAuctionChange;
            }

            // move amount to repay from sender to pool
            _transferQuoteTokenFrom(msg.sender, result.quoteTokenToRepay);
        }
        if (collateralAmountToPull_ != 0) {
            // update pool balances state
            poolBalances.pledgedCollateral = result.poolCollateral;

            // move collateral from pool to sender
            _transferCollateral(msg.sender, collateralAmountToPull_);
        }
    }

    /************************************/
    /*** Flashloan External Functions ***/
    /************************************/

    /// @inheritdoc FlashloanablePool
    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external override(IERC3156FlashLender, FlashloanablePool) nonReentrant returns (bool) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS)) return _flashLoanQuoteToken(receiver_, token_, amount_, data_);

        if (token_ == _getArgAddress(COLLATERAL_ADDRESS)) {
            _transferCollateral(address(receiver_), amount_);

            if (receiver_.onFlashLoan(msg.sender, token_, amount_, 0, data_) !=
                keccak256("ERC3156FlashBorrower.onFlashLoan")) revert FlashloanCallbackFailed();

            _transferCollateralFrom(address(receiver_), amount_);
            return true;
        }

        revert FlashloanUnavailableForToken();
    }

    /// @inheritdoc FlashloanablePool
    function flashFee(
        address token_,
        uint256
    ) external pure override(IERC3156FlashLender, FlashloanablePool) returns (uint256) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS) || token_ == _getArgAddress(COLLATERAL_ADDRESS)) return 0;
        revert FlashloanUnavailableForToken();
    }

    /// @inheritdoc FlashloanablePool
    function maxFlashLoan(
        address token_
    ) external view override(IERC3156FlashLender, FlashloanablePool) returns (uint256 maxLoan_) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS) || token_ == _getArgAddress(COLLATERAL_ADDRESS)) {
            maxLoan_ = IERC20Token(token_).balanceOf(address(this));
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /// @inheritdoc IERC20PoolLenderActions
    function addCollateral(
        uint256 amountToAdd_,
        uint256 index_
    ) external override nonReentrant returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        // revert if the dust amount was not exceeded, but round on the scale amount
        if (amountToAdd_ != 0 && amountToAdd_ < _collateralDust(index_)) revert DustAmountNotExceeded();
        amountToAdd_ = _roundToScale(amountToAdd_, _getArgUint256(COLLATERAL_SCALE));

        bucketLPs_ = LenderActions.addCollateral(
            buckets,
            deposits,
            amountToAdd_,
            index_
        );

        emit AddCollateral(msg.sender, index_, amountToAdd_, bucketLPs_);

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        // move required collateral from sender to pool
        _transferCollateralFrom(msg.sender, amountToAdd_);
    }

    /// @inheritdoc IPoolLenderActions
    function removeCollateral(
        uint256 maxAmount_,
        uint256 index_
    ) external override nonReentrant returns (uint256 collateralAmount_, uint256 lpAmount_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        (collateralAmount_, lpAmount_) = LenderActions.removeMaxCollateral(
            buckets,
            deposits,
            maxAmount_,
            index_,
            _collateralDust(index_)
        );

        emit RemoveCollateral(msg.sender, index_, collateralAmount_, lpAmount_);

        // update pool interest rate state
        _updateInterestState(poolState, _lup(poolState.debt));

        // move collateral from pool to lender
        _transferCollateral(msg.sender, collateralAmount_);
    }

    /*******************************/
    /*** Pool Auctions Functions ***/
    /*******************************/

    /// @inheritdoc IPoolLiquidationActions
    function settle(
        address borrowerAddress_,
        uint256 maxDepth_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        uint256 assets = Maths.wmul(poolBalances.t0Debt, poolState.inflator) + _getPoolQuoteTokenBalance();

        uint256 liabilities = Deposits.treeSum(deposits) + auctions.totalBondEscrowed + reserveAuction.unclaimed;

        (
            ,
            ,
            uint256 collateralSettled,
            uint256 t0DebtSettled
        ) = Auctions.settlePoolDebt(
            auctions,
            buckets,
            deposits,
            loans,
            SettleParams({
                borrower:    borrowerAddress_,
                reserves:    (assets > liabilities) ? (assets - liabilities) : 0,
                inflator:    poolState.inflator,
                bucketDepth: maxDepth_,
                poolType:    poolState.poolType
            })
        );

        // update pool balances state
        poolBalances.t0Debt            -= t0DebtSettled;
        poolBalances.t0DebtInAuction   -= t0DebtSettled;
        poolBalances.pledgedCollateral -= collateralSettled;

        // update pool interest rate state
        poolState.debt       -= Maths.wmul(t0DebtSettled, poolState.inflator);
        poolState.collateral -= collateralSettled;
        _updateInterestState(poolState, _lup(poolState.debt));
    }

    /// @inheritdoc IPoolLiquidationActions
    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        TakeResult memory result = Auctions.take(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            collateral_,
            _collateralDust(0)
        );
        // prevent caller from requesting an amount of collateral which costs 0 quote token
        if (result.quoteTokenAmount / _getArgUint256(QUOTE_SCALE) == 0) revert DustAmountNotExceeded();

        // update pool balances state
        uint256 t0PoolDebt      = poolBalances.t0Debt;
        uint256 t0DebtInAuction = poolBalances.t0DebtInAuction;

        if (result.t0DebtPenalty != 0) {
            t0PoolDebt      += result.t0DebtPenalty;
            t0DebtInAuction += result.t0DebtPenalty;
        }

        t0PoolDebt      -= result.t0RepayAmount;
        t0DebtInAuction -= result.t0DebtInAuctionChange;

        poolBalances.t0Debt            =  t0PoolDebt;
        poolBalances.t0DebtInAuction   =  t0DebtInAuction;
        poolBalances.pledgedCollateral -= result.collateralAmount;

        // update pool interest rate state
        poolState.debt       =  result.poolDebt;
        poolState.collateral -= result.collateralAmount;
        _updateInterestState(poolState, result.newLup);

        _transferCollateral(callee_, result.collateralAmount);

        if (data_.length != 0) {
            IERC20Taker(callee_).atomicSwapCallback(
                result.collateralAmount / _getArgUint256(COLLATERAL_SCALE), 
                result.quoteTokenAmount / _getArgUint256(QUOTE_SCALE), 
                data_
            );
        }

        _transferQuoteTokenFrom(callee_, result.quoteTokenAmount);
    }

    /// @inheritdoc IPoolLiquidationActions
    function bucketTake(
        address borrowerAddress_,
        bool    depositTake_,
        uint256 index_
    ) external override nonReentrant {

        PoolState memory poolState = _accruePoolInterest();

        BucketTakeResult memory result = Auctions.bucketTake(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            depositTake_,
            index_
        );

        // update pool balances state
        uint256 t0PoolDebt      = poolBalances.t0Debt;
        uint256 t0DebtInAuction = poolBalances.t0DebtInAuction;

        if (result.t0DebtPenalty != 0) {
            t0PoolDebt      += result.t0DebtPenalty;
            t0DebtInAuction += result.t0DebtPenalty;
        }

        t0PoolDebt      -= result.t0RepayAmount;
        t0DebtInAuction -= result.t0DebtInAuctionChange;

        poolBalances.t0Debt            =  t0PoolDebt;
        poolBalances.t0DebtInAuction   =  t0DebtInAuction;
        poolBalances.pledgedCollateral -= result.collateralAmount;

        // update pool interest rate state
        poolState.debt       = result.poolDebt;
        poolState.collateral -= result.collateralAmount;
        _updateInterestState(poolState, result.newLup);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    function _transferCollateralFrom(address from_, uint256 amount_) internal {
        IERC20(_getArgAddress(COLLATERAL_ADDRESS)).safeTransferFrom(from_, address(this), amount_ / _getArgUint256(COLLATERAL_SCALE));
    }

    function _transferCollateral(address to_, uint256 amount_) internal {
        IERC20(_getArgAddress(COLLATERAL_ADDRESS)).safeTransfer(to_, amount_ / _getArgUint256(COLLATERAL_SCALE));
    }

    function _collateralDust(uint256 bucketIndex) internal view returns (uint256) {
        // price precision adjustment will always be 0 for encumbered collateral
        uint256 pricePrecisionAdjustment = _getCollateralDustPricePrecisionAdjustment(bucketIndex);
        // difference between the normalized scale and the collateral token's scale
        uint256 scaleExponent            = 18 - IERC20Token(_getArgAddress(COLLATERAL_ADDRESS)).decimals();
        return 10 ** Maths.max(scaleExponent, pricePrecisionAdjustment);
    } 
}
