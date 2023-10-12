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
            remainingReserves: 1.425573693359453700 * 1e18,
            price:             1000000000 * 1e18,
            epoch:             1
        });

        skip(60 hours);

        _assertReserveAuction({
            reserves:                   0.000001006443638300 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 1.425573693359453700 * 1e18,
            auctionPrice:               0.000000000867361737 * 1e18,
            timeRemaining:              43200
        });

        // taking 0 amount forbidden
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.takeReserves(0);

        // take all reserves
        assertEq(USDC.balanceOf(address(_pool)),   1_007.869213 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);
        _pool.takeReserves(10 * 1e18);
        assertEq(USDC.balanceOf(address(_pool)),   1_006.443640 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 1.425573 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999998763511925 * 1e18);
    }

    function testZeroBid() external {
        // mint into the pool to simulate reserves
        deal(address(USDC), address(_pool), 1_000_000 * 1e6);
        _assertReserveAuction({
            reserves:                   999_300.2884615384615386 * 1e18,
            claimableReserves :         999_298.787018230769230907 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 999_298.787018230769230907 * 1e18,
            price:             1_000_000_000 * 1e18,
            epoch:             1
        });

        // price cannot hit zero, but wait for it to be reasonably small
        skip(71 hours);
        _assertReserveAuction({
            reserves:                   1.501443307692307693 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 999_298.787018230769230907 * 1e18,
            auctionPrice:               0.000000000000423516 * 1e18,
            timeRemaining:              1 hours
        });

        // try to take the smallest amount of USDC possible
        assertEq(USDC.balanceOf(address(_bidder)), 0);
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);
        _pool.takeReserves(1 * 1e6);
        // bidder got nothing, but burned 1wei of AJNA
        assertEq(USDC.balanceOf(address(_bidder)), 0);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999999999 * 1e18);

        // try to take a smaller-than-possible amount of USDC
        _pool.takeReserves(1);
        // bidder got nothing, but burned another 1wei of AJNA
        assertEq(USDC.balanceOf(address(_bidder)), 0);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999999998 * 1e18);

        // take a reasonable amount of USDC
        assertEq(USDC.balanceOf(address(_bidder)), 0);
        _pool.takeReserves(100 * 1e18);
        // bidder burned some AJNA
        assertEq(USDC.balanceOf(address(_bidder)), 100 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999957648398 * 1e18);
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
        pool.addQuoteToken(197806, 2572, block.timestamp + 1, false);
        pool.drawDebt(_actor3, 98903, 7388, 37);
        // pool balance is amount added minus new debt
        assertEq(_quote.balanceOf(address(pool)), 98903);

        vm.warp(block.timestamp + 17_280_000);

        changePrank(_actor9);
        pool.updateInterest();
        assertEq(_availableQuoteToken(), 98903);

        vm.warp(block.timestamp + 86400);

        changePrank(_actor7);
        pool.updateInterest();
        // should revert if trying to borrow more than available quote token
        vm.expectRevert(IPoolErrors.InsufficientLiquidity.selector);
        pool.drawDebt(_actor7, 99266, 7388, 999234524847);

        // actor 7 draws almost all available quote token
        pool.drawDebt(_actor7, 98703, 7388, 999234524847);
        // pool balance decreased by new debt
        assertEq(_quote.balanceOf(address(pool)), 200);
        // available quote token decreased with new debt
        assertEq(_availableQuoteToken(), 200);

        vm.warp(block.timestamp + 86400);

        // attempt to kick reserves and verify pool balance is unchanged
        changePrank(_actor2);
        pool.updateInterest();
        vm.expectRevert(IPoolErrors.NoReserves.selector);
        pool.kickReserveAuction();
        assertEq(_quote.balanceOf(address(pool)), 200);

        vm.warp(block.timestamp + 86400);

        changePrank(_actor3);
        pool.updateInterest();
        // not enough balance to start new auction
        vm.expectRevert(IPoolErrors.NoReserves.selector);
        pool.kickReserveAuction();
        
        // repay debt to have enough balance to kick new reserves auction
        ERC20Pool(address(_pool)).repayDebt(_actor3, type(uint256).max, 0, _actor3, MAX_FENWICK_INDEX);
        ERC20Pool(address(_pool)).repayDebt(_actor7, type(uint256).max, 0, _actor7, MAX_FENWICK_INDEX);

        uint256 initialPoolBalance     = 200784;
        uint256 initialAvailableAmount = 200784;

        assertEq(_quote.balanceOf(address(pool)), initialPoolBalance);
        assertEq(_availableQuoteToken(), initialAvailableAmount);

        pool.kickReserveAuction();

        uint256 claimableTokens = 591;

        ( , , uint256 claimable, , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(claimable, claimableTokens);

        skip(24 hours);

        // mint and approve ajna tokens for taker
        deal(address(_ajna), _actor3, 1e45);
        ERC20(address(_ajna)).approve(address(_pool), type(uint256).max);

        pool.takeReserves(claimableTokens);

        // quote token balance diminished by quote token taken from reserve auction
        assertEq(_quote.balanceOf(address(pool)), initialPoolBalance - claimableTokens);
        // available quote token (available to remove / draw debt from) is not modified
        assertEq(_availableQuoteToken(), initialAvailableAmount - claimableTokens);
    }

}
