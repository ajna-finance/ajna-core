// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }           from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory }    from "../../erc721/ERC721PoolFactory.sol";
import { IERC721Pool }          from "../../erc721/interfaces/IERC721Pool.sol";
import { IScaledPool }          from "../../base/interfaces/IScaledPool.sol";

import { BucketMath }           from "../../libraries/BucketMath.sol";
import { Maths }                from "../../libraries/Maths.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

contract ERC721ScaledReserveAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _collectionPool = _deployCollectionPool();
        address[] memory poolAddresses_ = new address[](1);
        poolAddresses_[0] = address(_collectionPool);
        _mintAndApproveQuoteTokens(poolAddresses_, _lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(poolAddresses_, _borrower, 5_000 * 1e18);
        _mintAndApproveAjnaTokens( poolAddresses_, _bidder,   40_000 * 1e18);
        assertEq(_ajna.balanceOf(_bidder), 40_000 * 1e18);
        _mintAndApproveCollateralTokens(poolAddresses_, _borrower, 12);

        // lender adds liquidity and borrower draws debt
        changePrank(_lender);
        uint16 bucketId = 1663;
        uint256 bucketPrice = _collectionPool.indexToPrice(bucketId);
        assertEq(bucketPrice, 251_183.992399245533703810 * 1e18);
        _collectionPool.addQuoteToken(200_000 * 1e18, bucketId);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _collectionPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _collectionPool.borrow(175_000 * 1e18, bucketId);

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
                auctionPrice:               0
            })
        );

        // ensure cannot take when no auction was started
        vm.expectRevert(IScaledPool.NoAuction.selector);
        _collectionPool.takeReserves(555 * 1e18);
        assertEq(_collectionPool.reserves(), 168.26923076923085 * 1e18);
    }

    function testUnclaimableReserves() external {
        // borrower repays partial debt, ensure cannot kick when there are no claimable reserves
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 50_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);
        changePrank(_bidder);
        assertEq(_collectionPool.claimableReserves(), 0);
        vm.expectRevert(IScaledPool.KickNoReserves.selector);
        _collectionPool.startClaimableReserveAuction();
    }

    function testReserveAuctionPricing() external {
        // borrower repays all debt (auction for full reserves)
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 205_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);

        // kick off a new auction
        changePrank(_bidder);
        uint256 expectedReserves = 604.374905327857838090 * 1e18;
        _collectionPool.startClaimableReserveAuction();
        _assertReserveAuctionPrice(1_000_000_000 * 1e18);

        // check prices
        skip(37 minutes);
        _assertReserveAuctionPrice(652176034.882778815 * 1e18);
        skip(23 hours);     // 23 hours 37 minutes
        _assertReserveAuctionPrice(77.745441781 * 1e18);
        skip(1400);         // 24 hours 0 minutes 20 seconds
        _assertReserveAuctionPrice(59.604644775 * 1e18);
        skip(100);          // 24 hours 2 minutes
        _assertReserveAuctionPrice(58.243272807 * 1e18);
        skip(58 minutes);   // 25 hours
        _assertReserveAuctionPrice(29.802322388 * 1e18);
        skip(5 hours);      // 30 hours
        _assertReserveAuctionPrice(0.931322575 * 1e18);
        skip(121 minutes);  // 32 hours 1 minute
        _assertReserveAuctionPrice(0.230156356 * 1e18);
        skip(7700 seconds); // 34 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.052459681 * 1e18);
        skip(8 hours);      // 42 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.000204921 * 1e18);
        skip(6 hours);      // 42 hours 9 minutes 20 seconds
        _assertReserveAuctionPrice(0.000003202 * 1e18);
        skip(3100 seconds); // 43 hours
        _assertReserveAuctionPrice(0.000001756 * 1e18);
        skip(5 hours);      // 48 hours
        _assertReserveAuctionPrice(0.000000055 * 1e18);
        skip(12 hours);     // 60 hours
        _assertReserveAuctionPrice(0);
    }

    function testClaimableReserveAuction() external {
        // borrower repays all debt (auction for full reserves)
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 205_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 expectedReserves = _collectionPool.claimableReserves();
        assertEq(expectedReserves, _collectionPool.reserves());
        assertEq(expectedReserves, 610.479702351371553626 * 1e18);
        uint256 kickAward = Maths.wmul(expectedReserves, 0.01 * 1e18);
        uint256 expectedQuoteBalance = _quote.balanceOf(_bidder) + kickAward;
        expectedReserves -= kickAward;
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _collectionPool.startClaimableReserveAuction();
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        assertEq(_collectionPool.reserves(), 0);
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);

        // bid once the price becomes attractive
        skip(24 hours);
        expectedPrice = 59.604644775 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(304.374905327857838090 * 1e18, expectedPrice);
        _collectionPool.takeReserves(300 * 1e18);
        expectedQuoteBalance += 300 * 1e18;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 22_118.6065675 * 1e18);
        expectedReserves -= 300 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // bid max amount
        skip(5 minutes);
        expectedPrice = 56.25929312 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(0, expectedPrice);
        _collectionPool.takeReserves(400 * 1e18);
        expectedQuoteBalance += expectedReserves;
        assertEq(_quote.balanceOf(_bidder), expectedQuoteBalance);
        assertEq(_ajna.balanceOf(_bidder), 4_994.689550287796185205 * 1e18);
        expectedReserves = 0;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // ensure take reverts after auction ends
        skip(72 hours);
        vm.expectRevert(IScaledPool.NoAuction.selector);
        _collectionPool.takeReserves(777 * 1e18);
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0
            })
        );
        assertEq(_collectionPool.reserves(), 0);
    }

    function testReserveAuctionPartiallyTaken() external {
        // borrower repays partial debt (auction for full reserves)
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 100_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);
        uint256 expectedReserves = _collectionPool.claimableReserves();
        assertEq(expectedReserves, 212.527832618418361858 * 1e18);

        // kick off a new auction
        uint256 expectedPrice = 1_000_000_000 * 1e18;
        uint256 kickAward = Maths.wmul(expectedReserves, 0.01 * 1e18);
        expectedReserves -= kickAward;
        changePrank(_bidder);
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _collectionPool.startClaimableReserveAuction();
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18 - 212.527832618418361858 * 1e18);

        // partial take
        skip(1 days);
        changePrank(_bidder);
        expectedPrice = 59.604644775 * 1e18;
        _collectionPool.takeReserves(100 * 1e18);
        expectedReserves -= 100 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // wait until auction ends
        skip(3 days);
        expectedPrice = 0;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );

        // after more interest accumulates, borrower repays remaining debt
        skip(4 weeks);
        changePrank(_borrower);
        _collectionPool.repay(_borrower, 105_000 * 1e18);

        // start an auction, confirm old claimable reserves are included alongside new claimable reserves
        skip(1 days);
        changePrank(_bidder);
        assertEq(_collectionPool.reserves(), 432.917381525917306905 * 1e18);
        uint256 newClaimableReserves = _collectionPool.claimableReserves();
        assertEq(newClaimableReserves, 432.917381525917306905 * 1e18);
        expectedPrice = 1_000_000_000 * 1e18;
        kickAward = Maths.wmul(newClaimableReserves, 0.01 * 1e18);
        expectedReserves += newClaimableReserves - kickAward;
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _collectionPool.startClaimableReserveAuction();

        // take everything
        skip(28 hours);
        assertEq(expectedReserves, 538.990762002892312075 * 1e18);
        expectedPrice = 3.725290298 * 1e18;
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
        expectedReserves = 0;
        vm.expectEmit(true, true, true, true);
        emit ReserveAuction(expectedReserves, expectedPrice);
        _collectionPool.takeReserves(600 * 1e18);
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: expectedReserves,
                auctionPrice:               expectedPrice
            })
        );
    }
}