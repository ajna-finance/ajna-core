// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 }    from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { 
    IERC20Pool,
    IERC20PoolBorrowerActions,
    IERC20PoolImmutables,
    IERC20PoolLenderActions
}                              from './interfaces/pool/erc20/IERC20Pool.sol';
import { IERC20Taker }         from './interfaces/pool/erc20/IERC20Taker.sol';

import {
    IPoolLenderActions,
    IPoolLiquidationActions,
    IERC20Token
}                            from './interfaces/pool/IPool.sol';
import {
    IERC3156FlashBorrower,
    IERC3156FlashLender
}                            from './interfaces/pool/IERC3156FlashLender.sol';

import {
    DrawDebtResult,
    BucketTakeResult,
    RepayDebtResult,
    SettleParams,
    TakeResult
}                    from './interfaces/pool/commons/IPoolInternals.sol';
import { PoolState } from './interfaces/pool/commons/IPoolState.sol';

import { FlashloanablePool } from './base/FlashloanablePool.sol';

import {
    _getCollateralDustPricePrecisionAdjustment,
    _roundToScale,
    _roundUpToScale
}                                               from './libraries/helpers/PoolHelper.sol';
import { _revertIfAuctionClearable }            from './libraries/helpers/RevertsHelper.sol';

import { Loans }    from './libraries/internal/Loans.sol';
import { Deposits } from './libraries/internal/Deposits.sol';
import { Maths }    from './libraries/internal/Maths.sol';

import { BorrowerActions } from './libraries/external/BorrowerActions.sol';
import { LenderActions }   from './libraries/external/LenderActions.sol';
import { Auctions }        from './libraries/external/Auctions.sol';

/**
 *  @title  ERC20 Pool contract
 *  @notice Entrypoint of ERC20 Pool actions for pool actors:
 *          - Lenders: add, remove and move quote tokens; transfer LPs
 *          - Borrowers: draw and repay debt
 *          - Traders: add, remove and move quote tokens; add and remove collateral
 *          - Kickers: kick undercollateralized loans; settle auctions; claim bond rewards
 *          - Bidders: take auctioned collateral
 *          - Reserve purchasers: start auctions; take reserves
 *          - Flash borrowers: initiate flash loans on quote tokens and collateral
 *  @dev    Contract is FlashloanablePool with flash loan logic.
 *  @dev    Contract is base Pool with logic to handle ERC20 collateral.
 *  @dev    Calls logic from external PoolCommons, LenderActions, BorrowerActions and Auctions libraries.
 */
contract ERC20Pool is FlashloanablePool, IERC20Pool {
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

    /// @inheritdoc IERC20Pool
    function bucketCollateralDust(uint256 bucketIndex) external pure override returns (uint256) {
        return _bucketCollateralDust(bucketIndex);
    }

    /***********************************/
    /*** Borrower External Functions ***/
    /***********************************/

    /**
     *  @inheritdoc IERC20PoolBorrowerActions
     *  @dev write state:
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - increment poolBalances.pledgedCollateral accumulator
     *          - increment poolBalances.t0Debt accumulator
     *  @dev emit events:
     *          - DrawDebt
     */
    function drawDebt(
        address borrowerAddress_,
        uint256 amountToBorrow_,
        uint256 limitIndex_,
        uint256 collateralToPledge_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        // ensure the borrower is not credited with a fractional amount of collateral smaller than the token scale
        collateralToPledge_ = _roundToScale(collateralToPledge_, _bucketCollateralDust(0));

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

    /**
     *  @inheritdoc IERC20PoolBorrowerActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     *  @dev emit events:
     *          - RepayDebt
     */
    function repayDebt(
        address borrowerAddress_,
        uint256 maxQuoteTokenAmountToRepay_,
        uint256 collateralAmountToPull_
    ) external nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        // ensure accounting is performed using the appropriate token scale
        maxQuoteTokenAmountToRepay_ = _roundToScale(maxQuoteTokenAmountToRepay_, _getArgUint256(QUOTE_SCALE));
        collateralAmountToPull_     = _roundToScale(collateralAmountToPull_,     _bucketCollateralDust(0));

        RepayDebtResult memory result = BorrowerActions.repayDebt(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            maxQuoteTokenAmountToRepay_,
            collateralAmountToPull_
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

    /**
     *  @inheritdoc IERC20PoolLenderActions
     *  @dev reverts on:
     *          - DustAmountNotExceeded()
     *  @dev emit events:
     *          - AddCollateral
     */
    function addCollateral(
        uint256 amountToAdd_,
        uint256 index_
    ) external override nonReentrant returns (uint256 bucketLPs_) {
        PoolState memory poolState = _accruePoolInterest();

        // revert if the dust amount was not exceeded, but round on the scale amount
        if (amountToAdd_ != 0 && amountToAdd_ < _bucketCollateralDust(index_)) revert DustAmountNotExceeded();
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

    /**
     *  @inheritdoc IPoolLenderActions
     *  @dev emit events:
     *          - RemoveCollateral
     */
    function removeCollateral(
        uint256 maxAmount_,
        uint256 index_
    ) external override nonReentrant returns (uint256 collateralAmount_, uint256 lpAmount_) {
        _revertIfAuctionClearable(auctions, loans);

        PoolState memory poolState = _accruePoolInterest();

        // round the collateral amount appropriately based on token precision
        maxAmount_ = _roundToScale(maxAmount_, _getArgUint256(COLLATERAL_SCALE));

        (collateralAmount_, lpAmount_) = LenderActions.removeMaxCollateral(
            buckets,
            deposits,
            maxAmount_,
            index_
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

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
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

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
    function take(
        address        borrowerAddress_,
        uint256        collateral_,
        address        callee_,
        bytes calldata data_
    ) external override nonReentrant {
        PoolState memory poolState = _accruePoolInterest();

        uint256 collateralDust = _bucketCollateralDust(0);

        // round requested collateral to an amount which can actually be transferred
        collateral_ = _roundToScale(collateral_, collateralDust);

        TakeResult memory result = Auctions.take(
            auctions,
            buckets,
            deposits,
            loans,
            poolState,
            borrowerAddress_,
            collateral_,
            collateralDust
        );
        // round quote token up to cover the cost of purchasing the collateral
        result.quoteTokenAmount = _roundUpToScale(result.quoteTokenAmount, _getArgUint256(QUOTE_SCALE));

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

    /**
     *  @inheritdoc IPoolLiquidationActions
     *  @dev write state:
     *          - decrement poolBalances.t0Debt accumulator
     *          - decrement poolBalances.t0DebtInAuction accumulator
     *          - decrement poolBalances.pledgedCollateral accumulator
     */
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
            index_,
            _bucketCollateralDust(0)
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

    function _bucketCollateralDust(uint256 bucketIndex) internal pure returns (uint256) {
        // price precision adjustment will always be 0 for encumbered collateral
        uint256 pricePrecisionAdjustment = _getCollateralDustPricePrecisionAdjustment(bucketIndex);
        // difference between the normalized scale and the collateral token's scale
        return Maths.max(_getArgUint256(COLLATERAL_SCALE), 10 ** pricePrecisionAdjustment);
    } 
}
