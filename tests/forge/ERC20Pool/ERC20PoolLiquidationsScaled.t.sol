// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20DSTestPlus }     from './ERC20DSTestPlus.sol';
import { ERC20Pool }           from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }    from 'src/ERC20PoolFactory.sol';
import { TokenWithNDecimals }  from '../utils/Tokens.sol';

import 'src/PoolInfoUtils.sol';
import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

contract ERC20PoolLiquidationsScaledTest is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    uint256 internal constant BUCKETS_WITH_DEPOSIT = 4;

    address            internal _bidder;
    address            internal _borrower;
    address            internal _borrower2;
    uint256            internal _collateralPrecision;
    uint256            internal _quoteTokenPrecision;
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
        vm.label(address(_pool), "ERC20Pool");
        _poolUtils  = new PoolInfoUtils();

        _collateralPrecision = uint256(10) ** collateralPrecisionDecimals_;
        _quoteTokenPrecision = uint256(10) ** quotePrecisionDecimals_;
        
        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");
        
        uint256 lenderDepositDenormalized = 200_000 * _quoteTokenPrecision;

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
        assertLt(startBucketId, 7388 - BUCKETS_WITH_DEPOSIT + 1);
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

    function drawDebt(
        address borrower_, 
        uint256 debtToDraw_, 
        uint256 collateralization_
    ) internal returns (uint256 collateralPledged_) {
        // calculate desired amount of collateral
        ( , , , , , uint256 lupIndex) = _poolUtils.poolPricesInfo(address(_pool));
        if (lupIndex == 0) lupIndex = _startBucketId;
        uint256 price         = _priceAt(lupIndex);
        uint256 colScale      = ERC20Pool(address(_pool)).collateralScale();
        collateralPledged_    = Maths.wmul(Maths.wdiv(debtToDraw_, price), collateralization_);
        collateralPledged_    = (collateralPledged_ / colScale) * colScale;
        while (Maths.wdiv(Maths.wmul(collateralPledged_, price), debtToDraw_) < collateralization_) {
            collateralPledged_ += colScale;
        }

        // mint and approve collateral tokens
        changePrank(borrower_);
        uint256 denormalizationFactor = 10 ** (18 - _collateral.decimals());
        deal(address(_collateral), borrower_, collateralPledged_ / denormalizationFactor);
        _collateral.approve(address(_pool), collateralPledged_ / denormalizationFactor);

        // pledge collateral and draw debt
        _drawDebtNoLupCheck({
            from:               borrower_,
            borrower:           borrower_,
            amountToBorrow:     debtToDraw_,
            limitIndex:         lupIndex + BUCKETS_WITH_DEPOSIT,
            collateralToPledge: collateralPledged_
        });
    }

    /********************/
    /*** Test Methods ***/
    /********************/

    function testLiquidationSingleBorrower(
        uint8  collateralPrecisionDecimals_, 
        uint8  quotePrecisionDecimals_,
        uint16 startBucketId_
    ) external tearDown {

        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 6,    18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1,    18);
        uint256 startBucketId       = bound(uint256(startBucketId_),               2000, 5388);
        init(boundColPrecision, boundQuotePrecision);
        addLiquidity(startBucketId);

        // Borrow half the pool's liquidity at 101% collateralization, leaving room for origination fee
        (uint256 collateralPledged) = drawDebt(_borrower, 99_000 * 1e18, 1.01 * 1e18);
        assertGt(_borrowerCollateralization(_borrower), 1e18);

        // Wait until borrower is undercollateralized
        skip(9 weeks);
        assertLt(_borrowerCollateralization(_borrower), 1e18);

        // Kick off an auction and wait the grace period
        _kick(_borrower, _bidder);
        skip(1 hours);

        // Wait until price drops below utilized portion of book
        uint256 auctionCollateral;
        uint256 auctionPrice;        
        for (uint i=0; i<72; ++i) {
            (auctionPrice, , auctionCollateral) = _advanceAuction(1 hours);
            if (auctionPrice < _priceAt(_startBucketId)) break;
        }

        // Test take
        assertEq(auctionCollateral, collateralPledged); 
        uint256 collateralToTake = Maths.wdiv(auctionCollateral, 3 * 1e18);
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

    function testSettleAuctionWithoutTakes(
        uint8  collateralPrecisionDecimals_, 
        uint8  quotePrecisionDecimals_,
        uint16 startBucketId_) external tearDown
    {
        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 6,    18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      6,    18);
        uint256 startBucketId       = bound(uint256(startBucketId_),               1000, 6388);
        init(boundColPrecision, boundQuotePrecision);
        addLiquidity(startBucketId);
        uint256 collateralDust = ERC20Pool(address(_pool)).bucketCollateralDust(0);

        // Borrow everything from the first bucket, with origination fee tapping into the second bucket
        drawDebt(_borrower, 50_000 * 1e18, 1.01 * 1e18);
        assertGt(_borrowerCollateralization(_borrower), 1e18);

        // Wait until borrower is undercollateralized
        skip(26 weeks);
        assertLt(_borrowerCollateralization(_borrower), 1e18);

        // Kick an auction and wait for a meaningful price
        _kick(_borrower, _bidder);
        (uint256 auctionPrice, uint256 auctionDebt, uint256 auctionCollateral) = _advanceAuction(9 hours);
        assertGt(auctionPrice, 0);
        assertGt(auctionDebt, 0);
        assertGt(auctionCollateral, collateralDust);

        // settle the auction without any legitimate takes
        (auctionPrice, auctionDebt, auctionCollateral) = _advanceAuction(72 hours);
        assertEq(auctionPrice, 0);
        assertGt(auctionDebt, 0);
        assertGt(auctionCollateral, collateralDust);
        _settle();
    }

    function testLiquidationKickWithDeposit(
        uint8  collateralPrecisionDecimals_, 
        uint8  quotePrecisionDecimals_,
        uint16 startBucketId_
    ) external tearDown {

        uint256 boundColPrecision   = bound(uint256(collateralPrecisionDecimals_), 12, 18);
        uint256 boundQuotePrecision = bound(uint256(quotePrecisionDecimals_),      1,  18);
        uint256 startBucketId       = bound(uint256(startBucketId_),               1,  7388 - BUCKETS_WITH_DEPOSIT);
        init(boundColPrecision, boundQuotePrecision);
        addLiquidity(startBucketId);

        // Draw debt from all four buckets
        drawDebt(_borrower, 151_000 * 1e18, 1.02 * 1e18);
        assertGt(_borrowerCollateralization(_borrower), 1e18);

        // Wait until borrower is undercollateralized
        skip(9 weeks);
        assertLt(_borrowerCollateralization(_borrower), 1e18);

        // Kick off an auction and wait the grace period
        _kickWithDeposit(_lender, _startBucketId);
        skip(1 hours);

        // Wait until price drops below utilized portion of book
        uint256 auctionCollateral;
        uint256 auctionPrice;        
        for (uint i=0; i<72; ++i) {
            (auctionPrice, , auctionCollateral) = _advanceAuction(1 hours);
            if (auctionPrice < _priceAt(_startBucketId)) break;
        }

        // Test arbTake and depositTake in same block
        _arbTake(_startBucketId, _bidder);
        _depositTake(_startBucketId + 1);

        // Take remainder of collateral
        (auctionPrice, , auctionCollateral) = _advanceAuction(33 minutes);
        _take(auctionCollateral, _bidder);
        uint256 auctionDebt;
        (, auctionDebt, auctionCollateral) = _advanceAuction(0);
        assertEq(auctionCollateral, 0);

        // Settle the auction
        if (auctionDebt != 0) skip(72 hours);
        _settle();
    }

    /************************/
    /*** Auction Wrappers ***/
    /************************/

    function _kick(address borrower, address kicker) internal {
        changePrank(kicker);
        _pool.kick(borrower);
        _checkAuctionStateUponKick(kicker);
    }

    function _kickWithDeposit(address lender, uint256 bucketId) internal {
        (uint256 lastLenderLPs, ) = _pool.lenderInfo(bucketId, lender);
        (, uint256 lastBucketDeposit, , uint256 lastBucketLPs, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);

        changePrank(lender);
        _pool.kickWithDeposit(bucketId);
        _checkAuctionStateUponKick(lender);

        // confirm user has redeemed some of their LPs to post liquidation bond
        (uint256 lenderLPs, ) = _pool.lenderInfo(bucketId, lender);
        assertLt(lenderLPs, lastLenderLPs);

        // confirm deposit has been removed from bucket
        (, uint256 bucketDeposit, , uint256 bucketLPs, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
        assertLt(bucketDeposit, lastBucketDeposit);
        assertLt(bucketLPs, lastBucketLPs);
    }

    function _checkAuctionStateUponKick(address kicker) internal {
        uint timeSinceStart = block.timestamp - _startTime;
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
        assertEq(auctionKickTime,     _startTime + timeSinceStart);
        assertGt(auctionKickMomp,     _priceAt(_startBucketId + BUCKETS_WITH_DEPOSIT));
        assertLt(auctionKickMomp,     _priceAt(_startBucketId));
        assertGt(auctionNeutralPrice, _priceAt(_startBucketId));
        assertLt(auctionNeutralPrice, Maths.wmul(_priceAt(_startBucketId), 1.1 * 1e18));
    }

    function _take(uint256 collateralToTake, address bidder) internal {
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertGt(lastAuctionDebt,       0);
        assertGt(lastAuctionCollateral, 0);

        changePrank(bidder);
        _pool.take(_borrower, collateralToTake, bidder, new bytes(0));

        (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertLt(auctionDebt, lastAuctionDebt);
        assertLt(auctionCollateral, lastAuctionCollateral);
    }

    function _depositTake(uint256 bucketId) internal {
        (uint256 lastAuctionDebt, uint256 lastAuctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertGt(lastAuctionDebt,       0);
        assertGt(lastAuctionCollateral, 0);
        (, uint256 lastBucketDeposit, uint256 lastBucketCollateral, uint256 lastBucketLPs, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
        uint256 lastKickerLPs = _kickerLPs(bucketId);
        assertGt(lastAuctionDebt,       0);
        assertGt(lastAuctionCollateral, 0);

        _pool.bucketTake(_borrower, true, bucketId);

        // confirm auction debt and collateral have decremented
        uint256 bucketLPs;
        {
            (uint256 auctionDebt, uint256 auctionCollateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
            assertLt(auctionDebt,       lastAuctionDebt);
            assertLt(auctionCollateral, lastAuctionCollateral);
            uint256 collateralTaken = lastAuctionCollateral - auctionCollateral;

            // confirm bucket deposit was exchanged for collateral
            uint256 bucketDeposit;
            uint256 bucketCollateral;
            (, bucketDeposit, bucketCollateral, bucketLPs, , ) = _poolUtils.bucketInfo(address(_pool), bucketId);
            assertLt(bucketDeposit, lastBucketDeposit);
            assertEq(bucketCollateral, lastBucketCollateral + collateralTaken);
        }

        // confirm LPs were awarded to the kicker
        (address kicker, , , uint256 kickTime, uint256 kickMomp, uint256 neutralPrice, , , ) = _pool.auctionInfo(_borrower);
        uint256 auctionPrice = Auctions._auctionPrice(kickMomp, neutralPrice, kickTime);
        if (auctionPrice < neutralPrice) {
            uint256 kickerLPs = _kickerLPs(bucketId);
            assertGt(kickerLPs, lastKickerLPs);
            uint256 kickerLpChange = kickerLPs - lastKickerLPs;            
            assertEq(bucketLPs, lastBucketLPs + kickerLpChange);
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
        (uint256 lastBidderLPs, ) = _pool.lenderInfo(bucketId, bidder);
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
            (uint256 bidderLPs, ) = _pool.lenderInfo(bucketId, bidder);
            assertGt(bidderLPs, lastBidderLPs);
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

    function _kickerLPs(uint256 bucketId) internal view returns (uint256) {
        (address kicker, , , , , , , , ) = _pool.auctionInfo(_borrower);
        (uint256 kickerLPs, ) = _pool.lenderInfo(bucketId, kicker);
        return kickerLPs;
    }
}
