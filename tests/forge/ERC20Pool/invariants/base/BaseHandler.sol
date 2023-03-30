// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import '@std/Test.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { PoolCommons }      from 'src/libraries/external/PoolCommons.sol';
import {
    MAX_FENWICK_INDEX,
    MAX_PRICE,
    MIN_PRICE
}                           from 'src/libraries/helpers/PoolHelper.sol';

import { TokenWithNDecimals, BurnableToken } from '../../../utils/Tokens.sol';

import 'src/libraries/internal/Maths.sol';
import '../interfaces/ITestBase.sol';

uint256 constant LENDER_MIN_BUCKET_INDEX = 2570;
uint256 constant LENDER_MAX_BUCKET_INDEX = 2572;

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;

uint256 constant MIN_AMOUNT = 1e6;
uint256 constant MAX_AMOUNT = 1e28;

abstract contract BaseHandler is Test {

    // Tokens
    TokenWithNDecimals internal _quote;
    TokenWithNDecimals internal _collateral;

    BurnableToken internal _ajna;

    // Pool
    ERC20Pool     internal _pool;
    PoolInfoUtils internal _poolInfo;

    // Test invariant contract
    ITestBase internal testContract;

    // Modifiers
    address internal _actor;
    uint256 internal _lenderBucketIndex;
    uint256 internal _limitIndex;

    // deposits invariant test state
    uint256[7389]                                   internal fenwickDeposits;
    mapping(address => mapping(uint256 => uint256)) public lenderDepositTime; // mapping of lender address to bucket index to deposit time

    address[] public actors;
    mapping(bytes32 => uint256)   public numberOfCalls;  // Logging
    mapping(address => uint256[]) public touchedBuckets; // Bucket tracking

    // exchange rate invariant test state
    mapping(uint256 => bool)    public exchangeRateShouldNotChange; // bucket exchange rate invariant check
    mapping(uint256 => uint256) public previousExchangeRate;        // mapping from bucket index to exchange rate before action

    // reserves invariant test state
    uint256 public previousReserves;    // reserves before action
    uint256 public increaseInReserves;  // amount of reserve decrease
    uint256 public decreaseInReserves;  // amount of reserve increase

    // auctions invariant test state
    bool                     public firstTake;        // if take is called on auction first time
    mapping(address => bool) public alreadyTaken;     // mapping borrower address to true if auction taken atleast once

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) {
        // Tokens
        _ajna       = BurnableToken(ajna_);
        _quote      = TokenWithNDecimals(quote_);
        _collateral = TokenWithNDecimals(collateral_);

        // Pool
        _pool     = ERC20Pool(pool_);
        _poolInfo = PoolInfoUtils(poolInfo_);

        // Actors
        actors = _buildActors(numOfActors_);

        // Test invariant contract
        testContract = ITestBase(testContract_);
    }

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
     * @dev Use and update test invariant contract timestamp to make timestamp consistent throughout invariant test run.
     */
    modifier useTimestamps() {
        vm.warp(testContract.currentTimestamp());

        _;

        testContract.setCurrentTimestamp(block.timestamp);
    }

    /**
     * @dev Resets all local states before each action.
     */
    modifier updateLocalStateAndPoolInterest() {
        _updateLocalFenwick();
        _fenwickAccrueInterest();
        _updatePoolState();

        _resetAndRecordReservesAndExchangeRate();

        _;
    }

    modifier useRandomActor(uint256 actorIndex_) {
        vm.stopPrank();

        _actor = actors[constrictToRange(actorIndex_, 0, actors.length - 1)];

        vm.startPrank(_actor);
        _;
        vm.stopPrank();
    }

    modifier useRandomLenderBucket(uint256 bucketIndex_) {
        uint256[] storage lenderBucketIndexes = touchedBuckets[_actor];

        if (lenderBucketIndexes.length < 3) {
            // if actor has touched less than three buckets, add a new bucket
            _lenderBucketIndex = constrictToRange(bucketIndex_, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);

            lenderBucketIndexes.push(_lenderBucketIndex);
        } else {
            // if actor has touched more than three buckets, reuse one of the touched buckets
            _lenderBucketIndex = lenderBucketIndexes[constrictToRange(bucketIndex_, 0, lenderBucketIndexes.length - 1)];
        }

        _;
    }

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _buildActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actorsAddress = new address[](noOfActors_);

        for (uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actorsAddress[i] = actor;

            vm.startPrank(actor);

            _quote.mint(actor, 1e45);
            _quote.approve(address(_pool), 1e45);

            _collateral.mint(actor, 1e45);
            _collateral.approve(address(_pool), 1e45);

            vm.stopPrank();
        }

        return actorsAddress;
    }

    function _updatePoolState() internal {
        _pool.updateInterest();
    }

    /**
     * @dev Ensure that error is an Pool expected error.
     */
    function _ensurePoolError(bytes memory err_) internal pure {
        bytes32 err = keccak256(err_);

        require(
            err == keccak256(abi.encodeWithSignature("InvalidAmount()")) ||
            err == keccak256(abi.encodeWithSignature("BucketBankruptcyBlock()")) ||
            err == keccak256(abi.encodeWithSignature("LUPBelowHTP()")) ||
            err == keccak256(abi.encodeWithSignature("InsufficientLiquidity()")) ||
            err == keccak256(abi.encodeWithSignature("RemoveDepositLockedByAuctionDebt()")) ||
            err == keccak256(abi.encodeWithSignature("NoClaim()")) ||
            err == keccak256(abi.encodeWithSignature("MoveToSameIndex()")) ||
            err == keccak256(abi.encodeWithSignature("DustAmountNotExceeded()")) ||
            err == keccak256(abi.encodeWithSignature("InvalidIndex()")) ||
            err == keccak256(abi.encodeWithSignature("InsufficientLPs()")) || 
            err == keccak256(abi.encodeWithSignature("AuctionNotCleared()")) ||
            err == keccak256(abi.encodeWithSignature("TransferorNotApproved()")) ||
            err == keccak256(abi.encodeWithSignature("TransferToSameOwner()")) ||
            err == keccak256(abi.encodeWithSignature("NoAllowance()")) ||
            err == keccak256(abi.encodeWithSignature("InsufficientCollateral()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionActive()")) ||
            err == keccak256(abi.encodeWithSignature("BorrowerUnderCollateralized()")) ||
            err == keccak256(abi.encodeWithSignature("NoDebt()")) ||
            err == keccak256(abi.encodeWithSignature("AmountLTMinDebt()")) ||
            err == keccak256(abi.encodeWithSignature("BorrowerOk()")) ||
            err == keccak256(abi.encodeWithSignature("LimitIndexExceeded()")) ||
            err == keccak256(abi.encodeWithSignature("PriceBelowLUP()")) ||
            err == keccak256(abi.encodeWithSignature("NoAuction()")) ||
            err == keccak256(abi.encodeWithSignature("TakeNotPastCooldown()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionPriceGtBucketPrice()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionNotClearable()")) ||
            err == keccak256(abi.encodeWithSignature("ReserveAuctionTooSoon()")) ||
            err == keccak256(abi.encodeWithSignature("NoReserves()")) ||
            err == keccak256(abi.encodeWithSignature("NoReservesAuction()")),
            "Unexpected revert error"
        );
    }

    /**************************************/
    /*** Exchange Rate Helper Functions ***/
    /**************************************/

    /**
     * @dev Record the reserves and exchange rates before each action.
     */
    function _resetAndRecordReservesAndExchangeRate() internal {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            // reset the change flag before each action
            exchangeRateShouldNotChange[bucketIndex] = false;
            // record exchange rate before each action
            previousExchangeRate[bucketIndex] = _pool.bucketExchangeRate(bucketIndex);
        }

        // reset the reserves before each action 
        increaseInReserves = 0;
        decreaseInReserves  = 0;
        // record reserves before each action
        (previousReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));
    }

    /********************************/
    /*** Fenwick Helper Functions ***/
    /********************************/

    function _fenwickAdd(uint256 amount_, uint256 bucketIndex_) internal {
        fenwickDeposits[bucketIndex_] += amount_;
    }

    function _fenwickRemove(uint256 removedAmount_, uint256 bucketIndex_) internal {
        fenwickDeposits[bucketIndex_] -= removedAmount_;
    }

    function _fenwickAccrueInterest() internal {
        ( , , , , uint256 pendingFactor) = _poolInfo.poolLoansInfo(address(_pool));

        // poolLoansInfo returns 1e18 if no interest is pending or time elapsed... the contracts calculate 0 time elapsed which causes discrep
        if (pendingFactor == 1e18) return;

        // get TP of worst loan, pendingInflator and poolDebt
        uint256 maxThresholdPrice;
        uint256 pendingInflator;
        uint256 poolDebt;
        {
            (, poolDebt ,) = _pool.debtInfo();

            (uint256 inflator, uint256 inflatorUpdate) = _pool.inflatorInfo();

            (, maxThresholdPrice,) =  _pool.loansInfo();
            maxThresholdPrice = Maths.wdiv(maxThresholdPrice, inflator);

            (uint256 interestRate, ) = _pool.interestRateInfo();

            pendingInflator = PoolCommons.pendingInflator(
                inflator,
                inflatorUpdate,
                interestRate
            );
        }

        // get HTP and deposit above HTP
        uint256 htp = Maths.wmul(maxThresholdPrice, pendingInflator);
        uint256 htpIndex;

        if (htp > MAX_PRICE)      htpIndex = 1;                          // if HTP is over the highest price bucket then no buckets earn interest
        else if (htp < MIN_PRICE) htpIndex = MAX_FENWICK_INDEX;          // if HTP is under the lowest price bucket then all buckets earn interest
        else                      htpIndex = _poolInfo.priceToIndex(htp);
        
        uint256 depositAboveHtp = fenwickSumTillIndex(htpIndex);

        if (depositAboveHtp != 0) {
            uint256 utilization          = _pool.depositUtilization();
            uint256 lenderInterestMargin = PoolCommons.lenderInterestMargin(utilization);

            uint256 newInterest = Maths.wmul(
                lenderInterestMargin,
                Maths.wmul(pendingFactor - Maths.WAD, poolDebt)
            );

            uint256 scale = (newInterest * 1e18) / depositAboveHtp + Maths.WAD;

            // simulate scale being applied to all deposits above HTP
            _fenwickMult(htpIndex, scale);
        } 
    }

    function _fenwickMult(uint256 index_, uint256 scale_) internal {
        while (index_ > 0) {
            fenwickDeposits[index_] = Maths.wmul(fenwickDeposits[index_], scale_);

            index_--;
        }
    }
    
    // update local fenwick to pool fenwick before each action
    function _updateLocalFenwick() internal {
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            (, , , uint256 deposits, ) = _pool.bucketInfo(bucketIndex);
            fenwickDeposits[bucketIndex] = deposits;
        }
    }

    /*********************************/
    /*** Auctions Helper Functions ***/
    /*********************************/

    /**
     * @dev Called by actions that can settle auctions in order to reset test state.
     */
    function _auctionSettleStateReset(address actor_) internal {
        (address kicker, , , , , , , , , ) = _pool.auctionInfo(actor_);

        // auction is settled if kicker is 0x
        bool auctionSettled = kicker == address(0);
        // reset alreadyTaken flag if auction is settled
        if (auctionSettled) alreadyTaken[actor_] = false;
    }

    function _getKickerBond(address kicker_) internal view returns (uint256 bond_) {
        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker_);
        bond_ = claimableBond + lockedBond;
    }

    function _updateCurrentTakeState(address borrower_, uint256 borrowerDebt_) internal {
        if (!alreadyTaken[borrower_]) {
            alreadyTaken[borrower_] = true;

            // **RE7**: Reserves increase by 7% of the loan quantity upon the first take.
            increaseInReserves += Maths.wmul(borrowerDebt_, 0.07 * 1e18);
            firstTake = true;

        } else firstTake = false;

        // reset taken flag in case auction was settled by take action
        _auctionSettleStateReset(borrower_);
    }

    /**********************************/
    /*** Fenwick External Functions ***/
    /**********************************/

    function fenwickSumTillIndex(uint256 index_) public view returns (uint256 sum_) {
        while (index_ > 0) {
            sum_ += fenwickDeposits[index_];

            index_--;
        }
    }

    function fenwickIndexForSum(uint256 debt_) public view returns (uint256) {
        uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX;

        while (debt_ != 0 && bucketIndex <= LENDER_MAX_BUCKET_INDEX) {
            if (fenwickDeposits[bucketIndex] >= debt_) return bucketIndex;

            debt_ -= fenwickDeposits[bucketIndex];

            bucketIndex += 1;
        }

        return MAX_FENWICK_INDEX;
    }

    function fenwickSumAtIndex(uint256 index_) public view returns(uint256) {
        return fenwickDeposits[index_];
    }

    function fenwickTreeSum() external view returns (uint256) {
        return fenwickSumTillIndex(fenwickDeposits.length - 1);    
    }

    /*************************************/
    /*** Test Utils External Functions ***/
    /*************************************/

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

    function constrictToRange(
        uint256 x_,
        uint256 min_,
        uint256 max_
    ) pure public returns (uint256 result_) {
        require(max_ >= min_, "MAX_LESS_THAN_MIN");

        uint256 size = max_ - min_;

        if (size == 0) return min_;            // Using max would be equivalent as well.
        if (max_ != type(uint256).max) size++; // Make the max inclusive.

        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max_ == type(uint256).max && x_ != 0) x_--; // Accounted for later.

        if (x_ < min_) x_ += size * (((min_ - x_) / size) + 1);

        result_ = min_ + ((x_ - min_) % size);

        // Account for decrementing x to make max inclusive.
        if (max_ == type(uint256).max && x_ != 0) result_++;
    }

}