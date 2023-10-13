// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@std/Test.sol';
import { EnumerableSet }   from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { Pool }             from 'src/base/Pool.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { PoolCommons }      from 'src/libraries/external/PoolCommons.sol';
import {
    MAX_FENWICK_INDEX,
    MAX_PRICE,
    MIN_PRICE,
    _indexOf
}                           from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }            from 'src/libraries/internal/Maths.sol';

import { TokenWithNDecimals, BurnableToken } from '../../../../utils/Tokens.sol';

import '../../../interfaces/ITestBase.sol';

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;

abstract contract BaseHandler is Test {

    using EnumerableSet for EnumerableSet.UintSet;

    // Tokens
    TokenWithNDecimals internal _quote;
    BurnableToken      internal _ajna;

    // Pool
    Pool          internal _pool;
    PoolInfoUtils internal _poolInfo;

    // Lender bucket index
    uint256 public LENDER_MIN_BUCKET_INDEX;
    uint256 public LENDER_MAX_BUCKET_INDEX;

    uint256 internal MIN_QUOTE_AMOUNT;
    uint256 internal MAX_QUOTE_AMOUNT;
    uint256 internal MIN_DEBT_AMOUNT;
    uint256 internal MAX_DEBT_AMOUNT;

    uint256 internal MIN_COLLATERAL_AMOUNT;
    uint256 internal MAX_COLLATERAL_AMOUNT;

    // Test invariant contract
    ITestBase internal testContract;

    // Modifiers
    address internal _actor;
    uint256 internal _lenderBucketIndex;
    uint256 internal _limitIndex;
    uint256 internal maxPoolDebt = uint256(vm.envOr("MAX_POOL_DEBT", uint256(1e55)));

    // deposits invariant test state
    uint256[7389]                                   internal fenwickDeposits;
    mapping(address => mapping(uint256 => uint256)) public lenderDepositTime; // mapping of lender address to bucket index to deposit time

    address[] public actors;
    mapping(bytes => uint256)   public numberOfCalls;    // Logging
    mapping(bytes => uint256)   public numberOfActions;  // Logging
    mapping(address => uint256[]) public touchedBuckets; // Bucket tracking

    // exchange rate invariant test state
    mapping(uint256 => bool)    public exchangeRateShouldNotChange; // bucket exchange rate invariant check
    mapping(uint256 => uint256) public previousExchangeRate;        // mapping from bucket index to exchange rate before action
    mapping(uint256 => uint256) public previousBankruptcy;          // mapping from bucket index to last bankruptcy before action

    // reserves invariant test state
    uint256 public previousReserves;    // reserves before action
    uint256 public increaseInReserves;  // amount of reserve increase
    uint256 public decreaseInReserves;  // amount of reserve decrease

    // Auction bond invariant test state
    uint256 public previousTotalBonds; // total bond before action
    uint256 public increaseInBonds;    // amount of bond increase
    uint256 public decreaseInBonds;    // amount of bond decrease

    // Take penalty test state
    uint256 public borrowerPenalty; // Borrower penalty on take
    uint256 public kickerReward;    // Kicker reward on take

    // All Buckets used in invariant testing that also includes Buckets where collateral is added when a borrower is in auction and has partial NFT
    EnumerableSet.UintSet internal buckets;

    // auctions invariant test state
    bool                     public firstTake;        // if take is called on auction first time

    string  internal path = "logFile.txt";
    bool    internal logToFile;
    uint256 internal logVerbosity;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        address testContract_
    ) {
        // Pool
        _pool     = Pool(pool_);
        _poolInfo = PoolInfoUtils(poolInfo_);

        // Tokens
        _ajna       = BurnableToken(ajna_);
        _quote      = TokenWithNDecimals(_pool.quoteTokenAddress());

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
     * @dev Skips some time before each action
     */
    modifier skipTime(uint256 time_) {
        address currentActor = _actor;

        // clear head auction if more than 72 hours passed
        (, , , , , , address headAuction, , ) = _pool.auctionInfo(address(0));
        if (headAuction != address(0)) {
            (, , , uint256 kickTime, , , , , ) = _pool.auctionInfo(headAuction);
            if (block.timestamp - kickTime > 72 hours) {
                (uint256 auctionedDebt, , ) = _poolInfo.borrowerInfo(address(_pool), headAuction);

                try vm.startPrank(headAuction) {
                } catch {
                    changePrank(headAuction);
                }

                _ensureQuoteAmount(headAuction, auctionedDebt);
                _repayBorrowerDebt(headAuction, auctionedDebt);
            }
        }

        (uint256 poolDebt, , ,) = _pool.debtInfo();

        // skip time only if max debt not exceeded (to prevent additional interest accumulation)
        if (maxPoolDebt > poolDebt) {
            time_ = constrictToRange(time_, 0, vm.envOr("SKIP_TIME", uint256(24 hours)));
            vm.warp(block.timestamp + time_);
        } else {
            // repay from loans if pool debt exceeds configured max debt
            // max repayments that can be done to prevent running out of gas
            uint256 maxLoansRepayments = 5;

            while (maxPoolDebt < poolDebt && maxLoansRepayments > 0) {
                (address borrower, , ) = _pool.loansInfo();

                if (borrower != address(0)) {
                    (uint256 debt, , )     = _poolInfo.borrowerInfo(address(_pool), borrower);

                    try vm.startPrank(borrower) {
                    } catch {
                        changePrank(borrower);
                    }

                    _ensureQuoteAmount(borrower, debt);
                    _repayBorrowerDebt(borrower, debt);
                } else {
                    // max borrower is 0x address, exit loop
                    break;
                }

                (poolDebt, , ,) = _pool.debtInfo();

                --maxLoansRepayments;
            }
        }

        _actor = currentActor;

        try vm.startPrank(currentActor) {
        } catch {
            changePrank(currentActor);
        }

        _;
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
        _actor = actors[constrictToRange(actorIndex_, 0, actors.length - 1)];

        // if prank already started in test then use change prank to change actor
        try vm.startPrank(_actor) {
        } catch {
            changePrank(_actor);
        }
        _;
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

    modifier writeLogs() {
        _;
        // Verbosity of Log file for pools
        logVerbosity = uint256(vm.envOr("LOGS_VERBOSITY_POOL", uint256(0)));

        if (logVerbosity != 0) logToFile = true;

        if (logToFile == true) {
            if (numberOfCalls["Write logs"]++ == 0) vm.writeFile(path, "");
            printInNextLine(string(abi.encodePacked("================= Handler Call : ", Strings.toString(numberOfCalls["Write logs"]), " ==================")));
        }

        if (logVerbosity > 0) {
            writePoolStateLogs();
            if (logVerbosity > 1) writeAuctionLogs();
            if (logVerbosity > 2) writeBucketsLogs();
            if (logVerbosity > 3) writeLenderLogs();
            if (logVerbosity > 4) writeBorrowerLogs();
        }
    }

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _getKickSkipTime() internal returns (uint256) {
        return vm.envOr("SKIP_TIME_TO_KICK", uint256(200 days));
    }

    function _ensureQuoteAmount(address actor_, uint256 amount_) internal {
        uint256 normalizedActorBalance = _quote.balanceOf(actor_) * _pool.quoteTokenScale();
        if (amount_> normalizedActorBalance) {
            _quote.mint(actor_, amount_ - normalizedActorBalance);
        }
        _quote.approve(address(_pool), _quote.balanceOf(actor_));
    }

    function _ensureAjnaAmount(address actor_, uint256 amount_) internal {
        uint256 actorBalance = _ajna.balanceOf(actor_);
        if (amount_> actorBalance) {
            _ajna.mint(actor_, amount_ - actorBalance);
        }
        _ajna.approve(address(_pool), _ajna.balanceOf(actor_));
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
            err == keccak256(abi.encodeWithSignature("InsufficientLP()")) || 
            err == keccak256(abi.encodeWithSignature("AuctionNotCleared()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionNotTakeable()")) ||
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
            err == keccak256(abi.encodeWithSignature("AuctionPriceGtBucketPrice()")) ||
            err == keccak256(abi.encodeWithSignature("AuctionNotClearable()")) ||
            err == keccak256(abi.encodeWithSignature("ReserveAuctionTooSoon()")) ||
            err == keccak256(abi.encodeWithSignature("NoReserves()")) ||
            err == keccak256(abi.encodeWithSignature("ZeroThresholdPrice()")) ||
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
            // record bankrupcy block before each action
            (,,uint256 bankruptcyTimestamp,,) = _pool.bucketInfo(bucketIndex);
            previousBankruptcy[bucketIndex] = bankruptcyTimestamp;
        }

        // reset the reserves before each action 
        increaseInReserves = 0;
        decreaseInReserves = 0;
        // record reserves before each action
        (previousReserves, , , , ) = _poolInfo.poolReservesInfo(address(_pool));

        // reset penalties before each action
        borrowerPenalty = 0;
        kickerReward = 0;

        // reset the bonds before each action
        increaseInBonds = 0;
        decreaseInBonds = 0;
        // record totalBondEscrowed before each action
        (previousTotalBonds, , , ) = _pool.reservesInfo();
    }

    /********************************/
    /*** Fenwick Helper Functions ***/
    /********************************/

    function _fenwickAdd(uint256 amount_, uint256 bucketIndex_) internal {
        fenwickDeposits[bucketIndex_] += amount_;
    }

    function _fenwickRemove(uint256 removedAmount_, uint256 bucketIndex_) internal {
        // removedAmount can be slightly greater than fenwickDeposits due to rounding in accrue interest
        fenwickDeposits[bucketIndex_] -= Maths.min(fenwickDeposits[bucketIndex_], removedAmount_);
    }

    function _fenwickAccrueInterest() internal {
        ( , , , , uint256 pendingFactor) = _poolInfo.poolLoansInfo(address(_pool));

        // poolLoansInfo returns 1e18 if no interest is pending or time elapsed... the contracts calculate 0 time elapsed which causes discrep
        if (pendingFactor == 1e18) return;

        // get TP of worst loan
        (, uint256 htp,) = _pool.loansInfo();

        uint256 accrualIndex;

        if (htp > MAX_PRICE)      accrualIndex = 1;                          // if HTP is over the highest price bucket then no buckets earn interest
        else if (htp < MIN_PRICE) accrualIndex = MAX_FENWICK_INDEX;          // if HTP is under the lowest price bucket then all buckets earn interest
        else                      accrualIndex = _poolInfo.priceToIndex(htp);

        (, uint256 poolDebt, , ) = _pool.debtInfo();
        uint256 lupIndex = _pool.depositIndex(poolDebt);

        // accrual price is less of lup and htp, and prices decrease as index increases
        if (lupIndex > accrualIndex) accrualIndex = lupIndex;
        
        uint256 interestEarningDeposit = fenwickSumTillIndex(accrualIndex);

        if (interestEarningDeposit != 0) {
            uint256 utilization          = _pool.depositUtilization();
            uint256 lenderInterestMargin = PoolCommons.lenderInterestMargin(utilization);

            uint256 newInterest = Maths.wmul(
                lenderInterestMargin,
                Maths.wmul(pendingFactor - Maths.WAD, poolDebt)
            );

            // Cap lender factor at 10x the interest factor for borrowers
            uint256 scale = Maths.min(
                (newInterest * 1e18) / interestEarningDeposit,
                10 * (pendingFactor - Maths.WAD)
            ) + Maths.WAD;

            // simulate scale being applied to all deposits above HTP
            _fenwickMult(accrualIndex, scale);
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

    function _getKickerBond(address kicker_) internal view returns (uint256 bond_) {
        (uint256 claimableBond, uint256 lockedBond) = _pool.kickerInfo(kicker_);
        bond_ = claimableBond + lockedBond;
    }

    function _recordSettleBucket(
        address borrower_,
        uint256 borrowerCollateralBefore_,
        uint256 kickTimeBefore_,
        uint256 auctionPrice_
    ) internal {
        (uint256 kickTimeAfter, , , , , ) = _poolInfo.auctionStatus(address(_pool), borrower_);

        // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
        if (kickTimeBefore_ != 0 && kickTimeAfter == 0 && borrowerCollateralBefore_ % 1e18 != 0) {
            if (auctionPrice_ < MIN_PRICE) {
                buckets.add(7388);
                lenderDepositTime[borrower_][7388] = block.timestamp;
            } else if (auctionPrice_ > MAX_PRICE) {
                buckets.add(0);
                lenderDepositTime[borrower_][0] = block.timestamp;
            } else {
                uint256 bucketIndex = _indexOf(auctionPrice_);
                buckets.add(bucketIndex);
                lenderDepositTime[borrower_][bucketIndex] = block.timestamp;
            }
        }
    }

    /********************************/
    /*** Logging Helper Functions ***/
    /********************************/

    function writePoolStateLogs() internal {
        uint256 pledgedCollateral    = _pool.pledgedCollateral();
        uint256 totalT0debt          = _pool.totalT0Debt();
        uint256 totalAuctions        = _pool.totalAuctionsInPool();
        uint256 totalT0debtInAuction = _pool.totalT0DebtInAuction();
        uint256 depositSize          = _pool.depositSize();
        (uint256 interestRate, )     = _pool.interestRateInfo();
        uint256 currentEpoch         = _pool.currentBurnEpoch();

        (
            uint256 totalBond,
            uint256 reserveUnclaimed, ,
            uint256 totalInterest
        ) = _pool.reservesInfo();

        (
            ,
            uint256 noOfLoans,
            address maxBorrower,
            uint256 pendingInflator,
        ) = _poolInfo.poolLoansInfo(address(_pool));

        (
            , , , , , ,
            address headAuction, ,
        ) = _pool.auctionInfo(address(0));

        printLog("Time                     = ", block.timestamp);
        printLog("Quote pool Balance       = ", _quote.balanceOf(address(_pool)));
        printLog("Total deposits           = ", depositSize);
        printLog("Pledged Collateral       = ", pledgedCollateral);
        printLog("Interest Rate            = ", interestRate);
        printLine("");
        printLog("Total t0 debt            = ", totalT0debt);
        printLog("Total t0 debt in auction = ", totalT0debtInAuction);
        printLog("Total debt               = ", Maths.wmul(totalT0debt, pendingInflator));
        printLog("Total debt in auction    = ", Maths.wmul(totalT0debtInAuction, pendingInflator));
        printLog("Total bond escrowed      = ", totalBond);
        printLine("");
        printLog("Total Loans              = ", noOfLoans);
        printLog("Total Auctions           = ", totalAuctions);
        printLine(
            string(
                abi.encodePacked("Max Borrower             = ", Strings.toHexString(uint160(maxBorrower), 20), "")
            )
        );
        printLine(
            string(
                abi.encodePacked("Head Auction             = ", Strings.toHexString(uint160(headAuction), 20), "")
            )
        );
        printLine("");

        printLog("Current Epoch            = ", currentEpoch);
        printLog("Total reserves unclaimed = ", reserveUnclaimed);
        printLog("Total interest earned    = ", totalInterest);
        printLine("");
        printLog("Successful kicks        = ", numberOfActions["kick"]);
        printLog("Successful lender kicks = ", numberOfActions["lenderKick"]);
        printLog("Successful takes        = ", numberOfActions["take"]);
        printLog("Successful bucket takes = ", numberOfActions["bucketTake"]);
        printLog("Successful settles      = ", numberOfActions["settle"]);

        printInNextLine("=======================");
    }

    function writeLenderLogs() internal {
        printInNextLine("== Lenders Details ==");
        string memory data;
        for (uint256 i = 0; i < actors.length; i++) {
            printLine("");
            printLog("Actor ", i + 1);
            for (uint256 j = 0; j < buckets.length(); j++) {
                uint256 bucketIndex = buckets.at(j);
                (uint256 lenderLps, ) = _pool.lenderInfo(bucketIndex, actors[i]);
                if (lenderLps != 0) {
                    data = string(abi.encodePacked("Lps at ", Strings.toString(bucketIndex), " = ", Strings.toString(lenderLps)));
                    printLine(data);
                }
            }
        }
        printInNextLine("=======================");
    }

    function writeBorrowerLogs() internal {
        printInNextLine("== Borrowers Details ==");
        for (uint256 i = 0; i < actors.length; i++) {
            printLine("");
            printLog("Actor ", i + 1);
            (uint256 debt, uint256 pledgedCollateral, ) = _poolInfo.borrowerInfo(address(_pool), actors[i]);
            if (debt != 0 || pledgedCollateral != 0) {
                printLog("Debt               = ", debt);
                printLog("Pledged collateral = ", pledgedCollateral);
            }
        }
        printInNextLine("=======================");
    }

    function writeBucketsLogs() internal {
        printInNextLine("== Buckets Detail ==");
        for (uint256 i = 0; i < buckets.length(); i++) {
            printLine("");
            uint256 bucketIndex = buckets.at(i);
            printLog("Bucket:", bucketIndex);
            (
                ,
                uint256 quoteTokens,
                uint256 collateral,
                uint256 bucketLP,
                uint256 scale,
                uint256 exchangeRate
            ) = _poolInfo.bucketInfo(address(_pool), bucketIndex);

            printLog("Quote tokens  = ", quoteTokens);
            printLog("Collateral    = ", collateral);
            printLog("Bucket Lps    = ", bucketLP);
            printLog("Scale         = ", scale);
            printLog("Exchange Rate = ", exchangeRate);
        }
        printInNextLine("=======================");
    }

    function writeAuctionLogs() internal {
        printInNextLine("== Auctions Details ==");
        string memory data;
        address nextBorrower;
        uint256 kickTime;
        uint256 referencePrice;
        uint256 bondFactor;
        uint256 bondSize;
        uint256 neutralPrice;
        (,,,,,, nextBorrower,,) = _pool.auctionInfo(address(0));
        while (nextBorrower != address(0)) {
            data = string(abi.encodePacked("Borrower ", Strings.toHexString(uint160(nextBorrower), 20), " Auction Details :"));
            printInNextLine(data);
            (, bondFactor, bondSize, kickTime, referencePrice, neutralPrice,, nextBorrower,) = _pool.auctionInfo(nextBorrower);

            printLog("Bond Factor     = ", bondFactor);
            printLog("Bond Size       = ", bondSize);
            printLog("Kick Time       = ", kickTime);
            printLog("Reference Price = ", referencePrice);
            printLog("Neutral Price   = ", neutralPrice);
        }
        printInNextLine("=======================");
    }

    function printLog(string memory key, uint256 value) internal {
        string memory data = string(abi.encodePacked(key, Strings.toString(value)));
        printLine(data);
    }

    function printLine(string memory data) internal {
        vm.writeLine(path, data);
    }

    function printInNextLine(string memory data) internal {
        printLine("");
        printLine(data);
    }

    /**********************************/
    /*** Fenwick External Functions ***/
    /**********************************/

    function fenwickSumTillIndex(uint256 index_) public view returns (uint256 sum_) {
        uint256[] memory depositBuckets = getBuckets();

        for (uint256 i = 0; i < depositBuckets.length; i++) {
            uint256 bucket = depositBuckets[i];
            if (bucket <= index_) {
                sum_ += fenwickDeposits[bucket];
            }
        }
    }

    function fenwickIndexForSum(uint256 debt_) public view returns (uint256) {
        uint256 minIndex = LENDER_MIN_BUCKET_INDEX;
        uint256 maxIndex = LENDER_MAX_BUCKET_INDEX;

        uint256[] memory depositBuckets = getBuckets();
        for (uint256 i = 0; i < depositBuckets.length; i++) {
            minIndex = Maths.min(minIndex, depositBuckets[i]);
            maxIndex = Maths.max(maxIndex, depositBuckets[i]);
        }

        while (debt_ != 0 && minIndex <= maxIndex) {
            if (fenwickDeposits[minIndex] >= debt_) return minIndex;

            debt_ -= fenwickDeposits[minIndex];

            minIndex += 1;
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

    function getBuckets() public view returns(uint256[] memory) {
        return buckets.values();
    }

    function _repayBorrowerDebt(address borrower_, uint256 amount_) internal virtual;

}
