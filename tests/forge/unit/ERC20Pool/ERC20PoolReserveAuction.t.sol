// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { ERC20HelperContract }                 from './ERC20DSTestPlus.sol';
import { FlashloanBorrower, SomeDefiStrategy } from '../../utils/FlashloanBorrower.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

import { IPoolErrors } from 'src/interfaces/pool/IPool.sol'; 

contract ERC20PoolReserveAuctionTest is ERC20HelperContract {

    ERC20 WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 AJNA = ERC20(_ajna);

    address internal _borrower;
    address internal _lender;
    address internal _bidder;

    function setUp() external {
        _pool      = ERC20Pool(new ERC20PoolFactory(address(AJNA)).deployPool(address(WBTC), address(USDC), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        deal(address(WBTC), _borrower, 10 * 1e8);
        deal(address(USDC), _borrower, 100 * 1e6);

        deal(address(USDC), _lender,   10_000 * 1e6);

        deal(address(AJNA), _bidder,   10 * 1e18);

        vm.startPrank(_borrower);
        WBTC.approve(address(_pool), 10 * 1e18);
        USDC.approve(address(_pool), 1_000 * 1e18);

        changePrank(_bidder);
        AJNA.approve(address(_pool), 10 * 1e18);

        changePrank(_lender);
        USDC.approve(address(_pool), 1_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  2500
        });

        _drawDebtNoLupCheck({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     300 * 1e18,
            limitIndex:         7000,
            collateralToPledge: 1 * 1e18
        });
    }

    function testStartAndTakeUsdcReserveAuction() external {
        // skip time to accumulate interest
        skip(26 weeks);

        // repay entire debt
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    400 * 1e18,
            amountRepaid:     307.869212479869665749 * 1e18,
            collateralToPull: 0
        });

        assertEq(USDC.balanceOf(address(_borrower)), 92.130787 * 1e6);
        assertEq(USDC.balanceOf(address(_pool)),     1_007.869213 * 1e6);

        _assertReserveAuction({
            reserves:                   1.425574699803092 * 1e18,
            claimableReserves :         1.425573693359453700 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 1.411317956425859163 * 1e18,
            price:             1000000000 * 1e18,
            epoch:             1
        });

        skip(60 hours);

        _assertReserveAuction({
            reserves:                   0.000001743377232837 * 1e18,
            claimableReserves :         0.000000736933594537 * 1e18,
            claimableReservesRemaining: 1.411317956425859163 * 1e18,
            auctionPrice:               0.000000000867361737 * 1e18,
            timeRemaining:              43200
        });

        assertEq(USDC.balanceOf(address(_pool)),   1_007.854958 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 0.014255 * 1e6); // kicker reward
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);

        _pool.takeReserves(10 * 1e18);

        assertEq(USDC.balanceOf(address(_pool)),   1_006.443641 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 1.425572 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999998775876805 * 1e18);
    }
}

contract ERC20PoolReserveAuctionNoFundsTest is ERC20HelperContract {

    address internal _actor2;
    address internal _actor3;
    address internal _actor7;
    address internal _actor9;

    function setUp() external {
        _startTest();

        _actor2  = makeAddr("actor2");
        _actor3  = makeAddr("actor3");
        _actor7  = makeAddr("actor7");
        _actor9  = makeAddr("actor9");

        _mintCollateralAndApproveTokens(_actor2,  1e45);
        _mintCollateralAndApproveTokens(_actor3,  1e45);
        _mintCollateralAndApproveTokens(_actor7,  1e45);
        _mintCollateralAndApproveTokens(_actor9,  1e45);

        _mintQuoteAndApproveTokens(_actor2,  1e45);
        _mintQuoteAndApproveTokens(_actor3,  1e45);
        _mintQuoteAndApproveTokens(_actor7,  1e45);
        _mintQuoteAndApproveTokens(_actor9,  1e45);
    }

    function testReserveAuctionNoFunds() external {
        ERC20Pool pool = ERC20Pool(address(_pool));

        changePrank(_actor3);
        pool.addQuoteToken(197806, 2572, block.timestamp + 1);
        pool.drawDebt(_actor3, 98903, 7388, 37);
        // pool balance is amount added minus new debt
        assertEq(_quote.balanceOf(address(pool)), 98903);

        vm.warp(block.timestamp + 17280000);

        changePrank(_actor9);
        pool.updateInterest();
        pool.kick(_actor3, 7388);
        // pool balance increased by kick bond
        assertEq(_quote.balanceOf(address(pool)), 99920);
        // available quote token does not account the kick bond
        assertEq(_availableQuoteToken(), 98903);

        vm.warp(block.timestamp + 86400);

        changePrank(_actor7);
        pool.updateInterest();
        // should revert if trying to borrow more than available quote token
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        pool.drawDebt(_actor7, 99266, 7388, 999234524847);

        pool.drawDebt(_actor7, 98903, 7388, 999234524847);
        // pool balance decreased by new debt
        assertEq(_quote.balanceOf(address(pool)), 1017);
        // available quote token decreased with new debt
        assertEq(_availableQuoteToken(), 0);

        vm.warp(block.timestamp + 86400);

        changePrank(_actor2);
        pool.updateInterest();
        pool.take(_actor3, 506252187686489913395361995, _actor2, new bytes(0));
        // pool balance remains the same
        assertEq(_quote.balanceOf(address(pool)), 1017);

        vm.warp(block.timestamp + 86400);

        changePrank(_actor3);
        pool.updateInterest();
        // not enough balance to start new auction
        vm.expectRevert(IPoolErrors.NoReserves.selector);
        pool.kickReserveAuction();

        pool.settle(_actor3, 10);
        
        // add tokens to have enough balance to kick new reserves auction
        pool.addQuoteToken(100, 2572, block.timestamp + 1);

        pool.kickReserveAuction();
        return;
        // pool balance diminished by reward given to reserves kicker
        assertEq(_quote.balanceOf(address(pool)), 1116);
        assertEq(_availableQuoteToken(), 0);
        skip(24 hours);

        // mint and approve ajna tokens for taker
        deal(address(_ajna), _actor3, 1e45);
        ERC20(address(_ajna)).approve(address(_pool), type(uint256).max);

        pool.takeReserves(787);

        assertEq(_quote.balanceOf(address(pool)), 1017);
        assertEq(_availableQuoteToken(), 0);
    }

}
