// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolReserveAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 5_000 * 1e18);
        _mintAndApproveAjnaTokens( _bidder,   80_000 * 1e18);
        assertEq(_ajnaToken.balanceOf(_bidder), 80_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 12);

        // lender adds liquidity and borrower draws debt
        uint16 bucketId = 1663;

        _addInitialLiquidity({
            from:   _lender,
            amount: 200_000 * 1e18,
            index:  bucketId
        });

        // borrower draws debt
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     175_000 * 1e18,
            indexLimit: bucketId,
            newLup:     251_183.992399245533703810 * 1e18
        });

        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt - 175_000 * 1e18, 168.26923076923085 * 1e18);

        skip(26 weeks);

        (poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt - 175_000 * 1e18, 4_590.373946590638353626 * 1e18);  // debt matches develop
    }

    function testClaimableReserveNoAuction() external tearDown {
        // ensure empty state is returned
        _assertReserveAuction({
            reserves:                   177.401650860555050000 * 1e18,
            claimableReserves :         177.401450869687470091 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // ensure cannot take when no auction was started
        _assertTakeReservesNoAuctionRevert({
            amount: 555 * 1e18
        });
    }

    function testReserveAuctionPricing() external tearDown {
        // borrower repays all debt (auction for full reserves)
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    205_000 * 1e18,
            amountRepaid:     179_590.373946590638353626 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        _assertReserveAuction({
            reserves:                   840.717358233766377865 * 1e18,
            claimableReserves :         840.717154484109789508 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 840.717154484109789508 * 1e18,
            price:             1_189_460.682069263974570223 * 1e18,
            epoch:             1
        });

        _assertReserveAuctionPrice(1_189_460.682069263974570223 * 1e18);

        // check prices
        skip(37 minutes);
        _assertReserveAuctionPrice(775_737.751280902122928059 * 1e18);

        skip(23 hours);     // 23 hours 37 minutes
        _assertReserveAuctionPrice(0.092475146207916989 * 1e18);

        skip(1400);         // 24 hours 0 minutes 20 seconds
        _assertReserveAuctionPrice(0.070897381429032324 * 1e18);

        skip(100);          // 24 hours 2 minutes
        _assertReserveAuctionPrice(0.069278082999263921 * 1e18);

        skip(58 minutes);   // 25 hours
        _assertReserveAuctionPrice(0.035448690714516162 * 1e18);

        skip(5 hours);      // 30 hours
        _assertReserveAuctionPrice(0.00110777158482863 * 1e18);

        skip(6 hours);      // 36 hours
        _assertReserveAuctionPrice(0.000017308931012947 * 1e18);

        skip(12 hours);     // 48 hours
        _assertReserveAuctionPrice(0.000000004225813235 * 1e18);

        skip(24 hours);     // 72 hours
        _assertReserveAuctionPrice(0.000000000000000251 * 1e18);
    }

    function testReserveAuctionTiming() external tearDown {
        // borrower repays all debt (auction for full reserves)
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    205_000 * 1e18,
            amountRepaid:     179_590.373946590638353626 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 840.717154484109789508 * 1e18,
            price:             1_189_460.682069263974570223 * 1e18,
            epoch:             1
        });

        // pass time to allow the price to decrease
        skip(24 hours);

        // check that you can't start a new auction if a previous auction is active
        _assertReserveAuctionTooSoon();

        (, uint256 unclaimed, , ,) = _pool.reservesInfo();

        uint256 expectedPrice = 0.070897381429032324 * 1e18;
        _takeReserves({
            from:              _bidder,
            amount:            Maths.wdiv(unclaimed, Maths.wad(2)),
            remainingReserves: Maths.wdiv(unclaimed, Maths.wad(2)),
            price:             expectedPrice,
            epoch:             1
        });

        // pass time to allow auction to complete
        skip(48 hours);

        // check that you can't start a new auction immediately after the last one finished...
        _assertReserveAuctionTooSoon();

        // ...or a day later...
        skip(24 hours);
        _assertReserveAuctionTooSoon();

        // ...but you can start another auction five days after the last one was kicked
        skip(24 hours);
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 420.358577242054894754 * 1e18,
            price:             2_378_921.364138527949140447 * 1e18,
            epoch:             2
        });
    }

    function testClaimableReserveAuction() external tearDown {
        // borrower repays all debt (auction for full reserves)
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    205_000 * 1e18,
            amountRepaid:     179_590.373946590638353626 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });
        (uint256 debt,,,) = _pool.debtInfo();
        assertEq(debt, 0);

        uint256 reserves          = 840.717358233766377865 * 1e18;
        uint256 claimableReserves = 840.717154484109789508 * 1e18;
        uint256 expectedReserves  = claimableReserves;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        uint256 expectedPrice = 1_189_460.682069263974570223 * 1e18;
        uint256 expectedQuoteBalance = _quote.balanceOf(_bidder);
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             1
        });
        reserves = 0.000203749656588357 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              3 days
        });
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        
        // bid once the price becomes attractive
        skip(16 hours);
        expectedPrice = 18.149729645832275002 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: 840.717154484109789508 * 1e18,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 16 hours
        });
        _takeReserves({
            from:              _bidder,
            amount:            300 * 1e18,
            remainingReserves: 540.717154484109789508 * 1e18,
            price:             expectedPrice,
            epoch:             1
        });

        expectedQuoteBalance += 300 * 1e18;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajnaToken.balanceOf(_bidder), 74_555.081106250317499400 * 1e18);
        expectedReserves -= 300 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 16 hours
        });

        // bid max amount
        skip(5 minutes);
        expectedPrice = 17.131063594818494900 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 16 hours - 5 minutes
        });
        _takeReserves({
            from:              _bidder,
            amount:            600 * 1e18,
            remainingReserves: 0,
            price:             expectedPrice,
            epoch:             1
        });
        expectedQuoteBalance += expectedReserves;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajnaToken.balanceOf(_bidder),  65_292.021145973736199572 * 1e18);

        expectedReserves = 0;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 16 hours - 5 minutes
        });

        // ensure take reverts after auction ends
        skip(72 hours);

        _assertTakeReservesNoAuctionRevert({
            amount: 777 * 1e18
        });

        // ensure auction cannot be kicked when no reserves are claimable
        skip(5 days);
        _assertKickReservesNoReservesRevert();

        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
    }

    function testReserveAuctionPartiallyTaken() external tearDown {
        // borrower repays partial debt (auction for full reserves)
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    100_000 * 1e18,
            amountRepaid:     100_000 * 1e18,
            collateralToPull: 0,
            newLup:           251_183.992399245533703810 * 1e18
        });
        uint256 reserves          = 840.717358233766377865 * 1e18;
        uint256 claimableReserves = 840.717154484109789508 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        uint256 expectedPrice     = 1_189_460.682069263974570223 * 1e18;
        uint256 expectedReserves  = claimableReserves;
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             1
        });
        reserves          = 0.000203749656588357 * 1e18;
        claimableReserves = 0;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              3 days
        });

        // partial take
        skip(1 days);
        expectedPrice = 0.070897381429032324 * 1e18;
        expectedReserves -= 100 * 1e18;
        _takeReserves({
            from:              _bidder,
            amount:            100 * 1e18,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             1
        });
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              2 days
        });

        // wait until auction ends
        skip(3 days);
        expectedPrice = 0;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              0
        });

        // after more interest accumulates, borrower repays remaining debt
        skip(4 weeks);
        vm.roll(block.number + 201_600);

        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    105_000 * 1e18,
            amountRepaid:     79_975.078950647281196428 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

        // start an auction, confirm old claimable reserves are included alongside new claimable reserves
        skip(1 days);

        reserves = 28.785107815609080430 * 1e18;
        uint256 newClaimableReserves = 28.784903710032392082 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         newClaimableReserves,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              0
        });
        expectedPrice = 1_299_541.683289044748128697 * 1e18;
        expectedReserves += newClaimableReserves;
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             2
        });

        // lender redeem their shares
        changePrank(_lender);
        _pool.removeQuoteToken(type(uint256).max, 1663);

        // ensure entire reserves can still be taken
        skip(18 hours);
        reserves             = 0.000204105576599248 * 1e18;
        newClaimableReserves = 0.000204105576599248 * 1e18;
        assertEq(expectedReserves, 769.502058194142181590 * 1e18);
        expectedPrice        = 4.957358105808428757 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         newClaimableReserves,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 18 hours
        });
        _takeReserves({
            from:              _bidder,
            amount:            expectedReserves,
            remainingReserves: 0,
            price:             expectedPrice,
            epoch:             2
        });

        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         newClaimableReserves,
            claimableReservesRemaining: 0,
            auctionPrice:               expectedPrice,
            timeRemaining:              72 hours - 18 hours
        });
    }
}
