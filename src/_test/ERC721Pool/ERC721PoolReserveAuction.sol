// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../erc721/interfaces/IERC721Pool.sol';
import '../../erc721/interfaces/pool/IERC721PoolErrors.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';

contract ERC721PoolReserveAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 5_000 * 1e18);
        _mintAndApproveAjnaTokens( _bidder,   40_000 * 1e18);
        assertEq(_ajna.balanceOf(_bidder), 40_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 12);

        // lender adds liquidity and borrower draws debt
        changePrank(_lender);
        uint16 bucketId = 1663;
        uint256 bucketPrice = _indexToPrice(bucketId);
        assertEq(bucketPrice, 251_183.992399245533703810 * 1e18);
        _pool.addQuoteToken(200_000 * 1e18, bucketId);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _pool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _pool.borrow(175_000 * 1e18, bucketId);

        _assertPool(
            PoolState({
                htp:                  175_168.269230769230850000 * 1e18,
                lup:                  bucketPrice,
                poolSize:             200_000 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 0.697370352137516918 * 1e18,
                borrowerDebt:         175_168.269230769230850000 * 1e18,
                actualUtilization:    0.875841346153846154 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        17_516.826923076923085000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower
            })
        );
        skip(26 weeks);
    }

    function testClaimableReserveNoAuction() external {
        // ensure empty state is returned
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            })
        );

        // ensure cannot take when no auction was started
        vm.expectRevert(IPoolErrors.NoAuction.selector);
        _pool.takeReserves(555 * 1e18);
        (uint256 reserves, , , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 168.26923076923085 * 1e18);
    }

    function testUnclaimableReserves() external {
        // borrower repays partial debt, ensure cannot kick when there are no claimable reserves
        changePrank(_borrower);
        _pool.repay(_borrower, 50_000 * 1e18);
        (uint256 reserves, uint256 claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 499.181304561658553626 * 1e18);
        changePrank(_bidder);
        assertEq(claimableReserves, 0);
        vm.expectRevert(IPoolErrors.KickNoReserves.selector);
        _pool.startClaimableReserveAuction();
    }

    function testReserveAuctionPricing() external {
        // borrower repays all debt (auction for full reserves)
        changePrank(_borrower);
        _pool.repay(_borrower, 205_000 * 1e18);
        (uint256 reserves, , , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 499.181304561658553626 * 1e18);

        // kick off a new auction
        changePrank(_bidder);
        _pool.startClaimableReserveAuction();
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

    function testClaimableReserveAuction() external {
        // borrower repays all debt (auction for full reserves)
        changePrank(_borrower);
        _pool.repay(_borrower, 205_000 * 1e18);
        (uint256 reserves, uint256 claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 499.181304561658553626 * 1e18);

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 expectedReserves = claimableReserves;
        assertEq(expectedReserves, reserves);
        assertEq(expectedReserves, 499.181304561658553626 * 1e18);
        uint256 kickAward = Maths.wmul(expectedReserves, 0.01 * 1e18);
        uint256 expectedQuoteBalance = _quote.balanceOf(_bidder) + kickAward;
        expectedReserves -= kickAward;
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _pool.startClaimableReserveAuction();
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              3 days
            })
        );
        (reserves, claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 0);
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);

        // bid once the price becomes attractive
        skip(24 hours);
        expectedPrice = 59.604644775390625 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              2 days
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(194.189491516041968090 * 1e18, expectedPrice);
        _pool.takeReserves(300 * 1e18);
        expectedQuoteBalance += 300 * 1e18;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 22_118.6065673828125 * 1e18);
        expectedReserves -= 300 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              2 days
            })
        );

        // bid max amount
        skip(5 minutes);
        expectedPrice = 56.259293120008319416 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              2875 minutes
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(0, expectedPrice);
        _pool.takeReserves(400 * 1e18);
        expectedQuoteBalance += expectedReserves;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 11_193.643043356438691840 * 1e18);
        expectedReserves = 0;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              2875 minutes
            })
        );

        // ensure take reverts after auction ends
        skip(72 hours);
        vm.expectRevert(IPoolErrors.NoAuction.selector);
        _pool.takeReserves(777 * 1e18);
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0,
                timeRemaining:              0
            })
        );
        (reserves, claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 0);
    }

    function testReserveAuctionPartiallyTaken() external {
        // borrower repays partial debt (auction for full reserves)
        changePrank(_borrower);
        _pool.repay(_borrower, 100_000 * 1e18);
        (uint256 reserves, uint256 claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 499.181304561658553626 * 1e18);
        uint256 expectedReserves = claimableReserves;
        assertEq(expectedReserves, 101.229434828705361858 * 1e18);

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 kickAward = Maths.wmul(expectedReserves, 0.01 * 1e18);
        expectedReserves -= kickAward;
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _pool.startClaimableReserveAuction();
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              3 days
            })
        );
        (reserves, claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 610.479702351371553626 * 1e18 - 212.527832618418361858 * 1e18);

        // partial take
        skip(1 days);
        changePrank(_bidder);
        expectedPrice = 59.604644775390625 * 1e18;
        _pool.takeReserves(100 * 1e18);
        expectedReserves -= 100 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              2 days
            })
        );

        // wait until auction ends
        skip(3 days);
        expectedPrice = 0;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              0
            })
        );

        // after more interest accumulates, borrower repays remaining debt
        skip(4 weeks);
        changePrank(_borrower);
        _pool.repay(_borrower, 105_000 * 1e18);

        // start an auction, confirm old claimable reserves are included alongside new claimable reserves
        skip(1 days);
        changePrank(_bidder);
        (reserves, claimableReserves, , , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 442.433476150631408531 * 1e18);
        uint256 newClaimableReserves = claimableReserves;
        assertEq(newClaimableReserves, 442.433476150631408531 * 1e18);
        expectedPrice = 1_000_000_000 * 1e18;
        kickAward = Maths.wmul(newClaimableReserves, 0.01 * 1e18);
        expectedReserves += newClaimableReserves - kickAward;
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _pool.startClaimableReserveAuction();

        // take everything
        skip(28 hours);
        assertEq(expectedReserves, 438.226281869543402685 * 1e18);
        expectedPrice = 3.725290298461914062 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              44 hours
            })
        );
        expectedReserves = 0;
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _pool.takeReserves(600 * 1e18);
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice,
                timeRemaining:              44 hours
            })
        );
    }
}