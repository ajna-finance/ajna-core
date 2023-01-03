// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/console2.sol";
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20DSTestPlus }     from './ERC20DSTestPlus.sol';
import { ERC20Pool }           from 'src/erc20/ERC20Pool.sol';
import { ERC20PoolFactory }    from 'src/erc20/ERC20PoolFactory.sol';
import { TokenWithNDecimals }  from '../utils/Tokens.sol';

import 'src/base/PoolInfoUtils.sol';
import 'src/base/PoolHelper.sol';
import 'src/erc20/interfaces/IERC20Pool.sol';

contract ERC20PoolLiquidationsScaledTest is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 internal constant BUCKETS_WITH_DEPOSIT = 4;

    address            internal _bidder;
    address            internal _borrower;
    address            internal _borrower2;
    uint256            internal _collateralPrecision;
    address            internal _lender;
    TokenWithNDecimals internal _collateral;
    TokenWithNDecimals internal _quote;
    uint256            internal _startBucketId;

    /*********************/
    /*** Setup Methods ***/
    /*********************/

    function init(uint256 collateralPrecisionDecimals_, uint256 quotePrecisionDecimals_) internal {
        _collateral = new TokenWithNDecimals("Collateral", "C", uint8(collateralPrecisionDecimals_));
        _quote      = new TokenWithNDecimals("Quote", "Q", uint8(quotePrecisionDecimals_));
        _pool       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils  = new PoolInfoUtils();

        _collateralPrecision   = uint256(10) ** collateralPrecisionDecimals_;
        uint256 quotePrecision = uint256(10) ** quotePrecisionDecimals_;
        
        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");
        
        uint256 lenderDepositDenormalized = 200_000 * quotePrecision;

        // give bidder quote token to cover liquidation bond
        vm.startPrank(_bidder);
        deal(address(_quote), _bidder,  lenderDepositDenormalized);
        _quote.approve(address(_pool), lenderDepositDenormalized);

        // give lender quote token to add liquidity to pool
        changePrank(_lender);
        deal(address(_quote), _lender,  lenderDepositDenormalized);
        _quote.approve(address(_pool), lenderDepositDenormalized);

        skip(1 days); // to avoid deposit time 0 equals bucket bankruptcy time
        _startTime = block.timestamp;
    }

    // Deposits into contiguous buckets
    function addLiquidity(uint256 startBucketId) internal {
        // ensure start bucket is in appropriate range
        assertGt(startBucketId, 0);
        assertLt(startBucketId, 7388 - BUCKETS_WITH_DEPOSIT);
        _startBucketId = startBucketId;

        // deposit 200k quote token across 4 buckets
        uint256 lpBalance;
        for (uint i=0; i<4; ++i) {
            _addInitialLiquidity(
                {
                    from:   _lender,
                    amount: 50_000 * 1e18,
                    index:  startBucketId + i
                }
            );
            (lpBalance, ) = _pool.lenderInfo(startBucketId + i, _lender);
            assertEq(lpBalance, 50_000 * 1e27);
        }
        assertEq(_pool.depositSize(), 200_000 * 1e18);
    }

    function drawDebt(address borrower_, uint256 debtToDraw_, uint256 collateralization_) internal returns (
        uint256 _collateralPledged
    ) {
        ( , , , , , uint256 lupIndex) = _poolUtils.poolPricesInfo(address(_pool));
        if (lupIndex == 0) lupIndex = _startBucketId;
        uint256 lup = _priceAt(lupIndex);
        _collateralPledged = Maths.wmul(Maths.wdiv(debtToDraw_, lup), collateralization_);
        console2.log("need %s collateral to draw %s debt at lup %s", _collateralPledged, debtToDraw_, lup);

        // mint and approve collateral tokens
        changePrank(borrower_);
        deal(address(_collateral), borrower_, _collateralPledged);  // TODO: denormalized for non-18-decimal collateral
        _collateral.approve(address(_pool), _collateralPledged);

        // pledge collateral and draw debt
        _drawDebtNoLupCheck({
            from:               borrower_,
            borrower:           borrower_,
            amountToBorrow:     debtToDraw_,
            limitIndex:         lupIndex + BUCKETS_WITH_DEPOSIT,
            collateralToPledge: _collateralPledged
        });
    }

    /********************/
    /*** Test Methods ***/
    /********************/

    function testLiquidationSingleBorrower(
        uint8  collateralPrecisionDecimals_, 
        uint8  quotePrecisionDecimals_,
        uint16 startBucketId_) external virtual tearDown
    {
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 18, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1,  18);
        // FIXME: set lower bound to 1 once issue #470 is resolved
        uint256 startBucketId       = bound(uint256(startBucketId_),               200,  7388 - BUCKETS_WITH_DEPOSIT);
        init(boundColPrecision, boundQuotePrecision);
        addLiquidity(startBucketId);

        // Borrow half the pool's liquidity at 101% collateralization, leaving room for origination fee
        (uint256 collateralPledged) = drawDebt(_borrower, 99_000 * 1e18, 1.01 * 1e18);
        assertGt(_borrowerCollateralization(_borrower), 1e18);

        // Wait until borrower is undercollateralized
        skip(6 weeks);
        assertLt(_borrowerCollateralization(_borrower), 1e18);

        // Kick off an auction and wait the grace period
        _kick(_borrower, _bidder);
        skip(1 hours);

        // Wait until price drops below utilized portion of book
        uint256 auctionCollateral;
        uint256 auctionPrice;        
        for (uint i=0; i<72; ++i) {
            console2.log("after %s hours, price is %s", i, auctionPrice);
            (auctionPrice, , auctionCollateral) = _advanceAuction(1 hours);
            if (auctionPrice < _priceAt(_startBucketId)) break;
        }

        // Test take
        assertEq(auctionCollateral, collateralPledged);
        uint256 collateralToTake = Maths.wdiv(auctionCollateral, 3 * 1e18);
        console2.log("taking %s at price %s", collateralToTake, auctionPrice);
        _take(collateralToTake, _bidder);
        
        // Test depositTake
        _advanceAuction(17 minutes);
        _depositTake(_startBucketId);

        // Test arbTake
        _advanceAuction(16 minutes);
        _arbTake(_startBucketId + 1, _bidder);

        // Settle auction
        _advanceAuction(72 hours);
        _settle();
    }

    // TODO: testKickWithDeposit


    /************************/
    /*** Auction Wrappers ***/
    /************************/

    function _kick(address borrower, address kicker) internal {
        changePrank(kicker);
        _pool.kick(borrower);
        (
            address auctionKicker,
            uint256 auctionBondFactor,
            uint256 auctionBondSize,
            uint256 auctionKickTime,
            uint256 auctionKickMomp,
            uint256 auctionNeutralPrice,
            ,
            ,
        ) = _pool.auctionInfo(_borrower);
        assertEq(auctionKicker,       kicker);
        assertGe(auctionBondFactor,   0.01 * 1e18);
        assertLe(auctionBondFactor,   0.3  * 1e18);
        assertGt(auctionBondSize,     0);
        assertLt(auctionBondSize,     _pool.depositSize());
        assertEq(auctionKickTime,     _startTime + 6 weeks);
        assertGt(auctionKickMomp,     _priceAt(_startBucketId + BUCKETS_WITH_DEPOSIT));
        assertLt(auctionKickMomp,     _priceAt(_startBucketId));
        assertGt(auctionNeutralPrice, _priceAt(_startBucketId));
        assertLt(auctionNeutralPrice, Maths.wmul(_priceAt(_startBucketId), 1.1 * 1e18));
    }

    function _take(uint256 collateralToTake, address bidder) internal {
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        changePrank(bidder);
        _pool.take(_borrower, collateralToTake, bidder, new bytes(0));

        (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertLt(auctionDebt,       lastAuctionDebt);
        assertEq(auctionCollateral, lastAuctionCollateral - collateralToTake);
    }

    function _depositTake(uint256 bucketId) internal {
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        (, uint256 lastBucketDeposit, uint256 lastBucketCollateral, uint256 lastBucketLps, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
        uint256 lastKickerLps = _kickerLps(bucketId);
        assertGt(lastAuctionDebt,       0);
        assertGt(lastAuctionCollateral, 0);

        _pool.bucketTake(_borrower, true, bucketId);

        // confirm auction debt and collateral have decremented
        uint256 bucketLps;
        {
            (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
            assertLt(auctionDebt,       lastAuctionDebt);
            assertLt(auctionCollateral, lastAuctionCollateral);
            uint256 collateralTaken = lastAuctionCollateral - auctionCollateral;

            // confirm bucket deposit was exchanged for collateral
            uint256 bucketDeposit;
            uint256 bucketCollateral;
            (, bucketDeposit, bucketCollateral, bucketLps, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
            assertLt(bucketDeposit, lastBucketDeposit);
            assertEq(bucketCollateral, lastBucketCollateral + collateralTaken);
        }

        // confirm LPs were awarded to the kicker
        (address kicker, , , uint256 kickTime, uint256 kickMomp, uint256 neutralPrice, , , ) = _pool.auctionInfo(_borrower);
        uint256 auctionPrice = Auctions._auctionPrice(kickMomp, neutralPrice, kickTime);
        if (auctionPrice < neutralPrice) {
            uint256 kickerLps = _kickerLps(bucketId);
            assertGt(kickerLps, lastKickerLps);
            uint256 kickerLpChange = kickerLps - lastKickerLps;            
            assertEq(bucketLps, lastBucketLps + kickerLpChange);
        }

        // Add for tearDown
        lenders.add(kicker);
        lendersDepositedIndex[kicker].add(bucketId);
        bucketsUsed.add(bucketId);
    }

    function _arbTake(uint256 bucketId, address bidder) internal {
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertGt(lastAuctionDebt,       0);
        assertGt(lastAuctionCollateral, 0);
        (, uint256 lastBucketDeposit, uint256 lastBucketCollateral, , , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
        (uint256 lastBidderLps, ) = _pool.lenderInfo(bucketId, bidder);
        uint256 lastBidderQuoteBalance = _quote.balanceOf(bidder);

        changePrank(bidder);
        _pool.bucketTake(_borrower, false, bucketId);

        // confirm auction debt and collateral have decremented
        (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertLt(auctionDebt,       lastAuctionDebt);
        assertLt(auctionCollateral, lastAuctionCollateral);
        uint256 collateralTaken = lastAuctionCollateral - auctionCollateral;

        // confirm bidder was awarded LPs without spending any quote token
        {
            (uint256 bidderLps, ) = _pool.lenderInfo(bucketId, bidder);
            assertGt(bidderLps, lastBidderLps);
            assertEq(_quote.balanceOf(bidder), lastBidderQuoteBalance);
        }

        // confirm collateral moved to the bucket
        {
            (, uint256 bucketDeposit, uint256 bucketCollateral, , , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
            assertLt(bucketDeposit, lastBucketDeposit);
            assertEq(bucketCollateral, lastBucketCollateral + collateralTaken);
        }

        // Add for tearDown
        lenders.add(bidder);
        lendersDepositedIndex[bidder].add(bucketId);
        bucketsUsed.add(bucketId);
    }

    function _settle() internal {
        _pool.settle(_borrower, BUCKETS_WITH_DEPOSIT);

        // Added for tearDown
        // Borrowers may receive LP in 7388 during settle if 0 deposit in book
        lenders.add(_borrower);
        lendersDepositedIndex[_borrower].add(7388);
        bucketsUsed.add(7388);
    }

    /**********************/
    /*** Helper Methods ***/
    /**********************/

    function _advanceAuction(uint secondsToSkip) internal returns (
        uint256 auctionPrice_,
        uint256 auctionDebt_,
        uint256 auctionCollateral_
    ){
        (, , , uint256 kickTime, uint256 kickMomp, uint256 neutralPrice, , , ) = _pool.auctionInfo(_borrower);
        uint256 lastAuctionPrice = Auctions._auctionPrice(kickMomp, neutralPrice, kickTime);
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        if (secondsToSkip != 0) {
            skip(secondsToSkip);
            auctionPrice_ = Auctions._auctionPrice(kickMomp, neutralPrice, kickTime);
            (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
            // ensure auction price decreases and auction debt increases as time passes
            assertLt(auctionPrice_,     lastAuctionPrice);
            assertGt(auctionDebt,       lastAuctionDebt);
            assertEq(auctionCollateral, lastAuctionCollateral);
            auctionDebt_       = auctionDebt;
            auctionCollateral_ = auctionCollateral;
        } else {
            auctionPrice_      = lastAuctionPrice;
            auctionDebt_       = lastAuctionDebt;
            auctionCollateral_ = lastAuctionCollateral;
        }
    }

    function _auctionPrice() internal view returns (uint256) {
        (, , , uint256 kickTime, uint256 kickMomp, uint256 neutralPrice, , , ) = _pool.auctionInfo(_borrower);
        return Auctions._auctionPrice(kickMomp, neutralPrice, kickTime);
    }

    function _borrowerCollateralization(address borrower) internal view returns (uint256) {
        (uint256 debt, uint256 collateral, ) = _poolUtils.borrowerInfo(address(_pool), borrower);
        return _collateralization(debt, collateral, _lup());
    }

    function _kickerLps(uint256 bucketId) internal view returns (uint256) {
        (address kicker, , , , , , , , ) = _pool.auctionInfo(_borrower);
        (uint256 kickerLps, ) = _pool.lenderInfo(bucketId, kicker);
        return kickerLps;
    }
}
