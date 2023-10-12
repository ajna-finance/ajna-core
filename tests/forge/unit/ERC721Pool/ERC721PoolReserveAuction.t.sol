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

    function testClaimableReserveNoAuction() external {
        // ensure empty state is returned
        _assertReserveAuction({
            reserves:                   168.26923076923085 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // ensure cannot take when no auction was started
        _assertTakeReservesNoAuctionRevert({
            amount: 555 * 1e18
        });
    }

    function testUnclaimableReserves() external {
        // borrower repays partial debt, ensure cannot kick when there are no claimable reserves
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * 1e18,
            amountRepaid:     5_000 * 1e18,
            collateralToPull: 0,
            newLup:           251_183.992399245533703810 * 1e18
        });

        _assertReserveAuction({
            reserves:                   831.584938142442153626 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        changePrank(_bidder);

        _assertTakeReservesNoReservesRevert();
    }

    function testReserveAuctionPricing() external {
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
            reserves:                   831.584938142442153626 * 1e18,
            claimableReserves :         831.584734383653145178 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 831.584734383653145178 * 1e18,
            price:             1_000_000_000 * 1e18,
            epoch:             1
        });

        _assertReserveAuctionPrice(1_000_000_000 * 1e18);

        // check prices
        skip(37 minutes);
        _assertReserveAuctionPrice(652176034.882782126826643053 * 1e18);

        skip(23 hours);     // 23 hours 37 minutes
        _assertReserveAuctionPrice(77.745441780421987394 * 1e18);

        skip(1400);         // 24 hours 0 minutes 20 seconds
        _assertReserveAuctionPrice(59.604644775390625 * 1e18);

        skip(100);          // 24 hours 2 minutes
        _assertReserveAuctionPrice(58.243272807255146201 * 1e18);

        skip(58 minutes);   // 25 hours
        _assertReserveAuctionPrice(29.8023223876953125 * 1e18);

        skip(5 hours);      // 30 hours
        _assertReserveAuctionPrice(0.931322574615478515 * 1e18);

        skip(121 minutes);  // 32 hours 1 minute
        _assertReserveAuctionPrice(0.230156355619639189 * 1e18);

        skip(7700 seconds); // 34 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.052459681325756842 * 1e18);

        skip(8 hours);      // 42 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.000204920630178738 * 1e18);

        skip(6 hours);      // 42 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.000003201884846542 * 1e18);

        skip(3100 seconds); // 43 hours
        _assertReserveAuctionPrice(0.000001755953640897 * 1e18);

        skip(5 hours);      // 48 hours
        _assertReserveAuctionPrice(0.000000054873551278 * 1e18);

        skip(12 hours);     // 60 hours
        _assertReserveAuctionPrice(0.000000000013396863 * 1e18);

        skip(11 hours);     // 71 hours
        _assertReserveAuctionPrice(0.000000000000006541 * 1e18);

        skip(3599 seconds); // 71 hours 59 minutes 59 seconds
        _assertReserveAuctionPrice(0.000000000000003308 * 1e18);

        skip(1 seconds);    // 72 hours
        _assertReserveAuctionPrice(0.000000000000003270 * 1e18);
    }

    function testReserveAuctionTiming() external {
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
            remainingReserves: 831.584734383653145178 * 1e18,
            price:             1_000_000_000 * 1e18,
            epoch:             1
        });

        // pass time to allow the price to decrease
        skip(24 hours);

        // check that you can't start a new auction if a previous auction is active
        _assertReserveAuctionTooSoon();

        (, uint256 unclaimed, , ) = _pool.reservesInfo();

        uint256 expectedPrice = 59.604644775390625 * 1e18;
        _takeReserves({
            from:              _bidder,
            amount:            Maths.wdiv(unclaimed, Maths.wad(2)),
            remainingReserves: Maths.wdiv(unclaimed, Maths.wad(2)),
            price:             expectedPrice,
            epoch:             1
        });

        // pass time to allow auction to complete
        skip(48 hours);

        // check that you can't start a new auction unless two weeks have passed
        _assertReserveAuctionTooSoon();
    }

    function testClaimableReserveAuction() external {
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

        uint256 reserves          = 831.584938142442153626 * 1e18;
        uint256 claimableReserves = 831.584734383653145178 * 1e18;
        uint256 expectedReserves  = claimableReserves;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 expectedQuoteBalance = _quote.balanceOf(_bidder);

        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             1
        });
        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              3 days
        });
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        
        // bid once the price becomes attractive
        skip(24 hours);
        expectedPrice = 59.604644775390625 * 1e18;
        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 831.584734383653145178 * 1e18,
            auctionPrice:               expectedPrice,
            timeRemaining:              2 days
        });

        _takeReserves({
            from:              _bidder,
            amount:            300 * 1e18,
            remainingReserves: 531.584734383653145178 * 1e18,
            price:             expectedPrice,
            epoch:             1
        });

        expectedQuoteBalance += 300 * 1e18;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajnaToken.balanceOf(_bidder), 62_118.606567382812500000 * 1e18);
        expectedReserves -= 300 * 1e18;
        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              2 days
        });

        // bid max amount
        skip(5 minutes);
        expectedPrice = 56.259293120008319416 * 1e18;
        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              2875 minutes
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
        assertEq(_ajnaToken.balanceOf(_bidder),  32_212.025177571105194476 * 1e18);

        expectedReserves = 0;
        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              2875 minutes
        });

        // ensure take reverts after auction ends
        skip(72 hours);

        _assertTakeReservesNoAuctionRevert({
            amount: 777 * 1e18
        });

        _assertReserveAuction({
            reserves:                   0.000203758789008448 * 1e18,
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
        uint256 reserves          = 831.584938142442153626 * 1e18;
        uint256 claimableReserves = 433.632864650699953410 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         claimableReserves,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        uint256 expectedPrice     = 1_000_000_000 * 1e18;
        uint256 expectedReserves  = claimableReserves;

        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: expectedReserves,
            price:             expectedPrice,
            epoch:             1
        });
        reserves          = 397.952073491742200216 * 1e18;
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

        expectedPrice = 59.604644775390625 * 1e18;
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
            reserves:                   397.952073491742200216 * 1e18,
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

        reserves = 426.740068998777899912 * 1e18;
        uint256 newClaimableReserves = 426.739864884071882914 * 1e18;
        _assertReserveAuction({
            reserves:                   reserves,
            claimableReserves :         newClaimableReserves,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              0
        });
        expectedPrice = 1_000_000_000 * 1e18;
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
        skip(28 hours);
        assertEq(expectedReserves, 760.372729534771836324 * 1e18);
        expectedPrice = 3.725290298461914062 * 1e18;
        _assertReserveAuction({
            reserves:                   0.000204114705960104 * 1e18,
            claimableReserves :         0.000204114705960104 * 1e18,
            claimableReservesRemaining: expectedReserves,
            auctionPrice:               expectedPrice,
            timeRemaining:              44 hours
        });
        _takeReserves({
            from:              _bidder,
            amount:            expectedReserves,
            remainingReserves: 0,
            price:             expectedPrice,
            epoch:             2
        });

        _assertReserveAuction({
            reserves:                   0.000204114705960104 * 1e18,
            claimableReserves :         0.000204114705960104 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               expectedPrice,
            timeRemaining:              44 hours
        });

    }
}
