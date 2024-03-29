// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@std/Test.sol";
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { ERC20HelperContract }                 from './ERC20DSTestPlus.sol';
import { FlashloanBorrower, SomeDefiStrategy } from '../../utils/FlashloanBorrower.sol';
import { Token }                               from '../../utils/Tokens.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';
import 'src/PoolInfoUtils.sol';

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

    function testStartAndTakeUsdcReserveAuction() external tearDown {
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
            reserves:                   1.471236800259713756 * 1e18,
            claimableReserves :         1.471235793861737556 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 1.471235793861737556 * 1e18,
            price:             679_700_700.711729067726118823 * 1e18,
            epoch:             1
        });

        skip(60 hours);

        _assertReserveAuction({
            reserves:                   0.000001006397976200 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 1.471235793861737556 * 1e18,
            auctionPrice:               0.000000000589546380 * 1e18,
            timeRemaining:              43200
        });

        // taking 0 amount forbidden
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.takeReserves(0);

        // take all reserves
        assertEq(USDC.balanceOf(address(_pool)),   1_007.869213 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);
        _pool.takeReserves(10 * 1e18);
        assertEq(USDC.balanceOf(address(_pool)),   1_006.397978 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 1.471235 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999132638263 * 1e18);
    }

    function testZeroBid() external tearDown {
        // mint into the pool to simulate reserves
        deal(address(USDC), address(_pool), 1_000_000 * 1e6);
        _assertReserveAuction({
            reserves:                   999_300.334123638918159600 * 1e18,
            claimableReserves :         999_300.334122638963821700 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 999_300.334122638963821700 * 1e18,
            price:             1_000.700155752449863388 * 1e18,
            epoch:             1
        });

        // wait for price to be reasonably small
        skip(64 hours);
        _assertReserveAuction({
            reserves:                   0.000000999954337900 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 999_300.334122638963821700 * 1e18,
            auctionPrice:               0.000000000000000054 * 1e18,
            timeRemaining:              72 hours - 64 hours
        });

        // try to take the smallest amount of USDC possible
        assertEq(USDC.balanceOf(address(_bidder)), 0);
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);
        _pool.takeReserves(1e12);
        // bidder got a quantum of USDC and burned 1wei of AJNA
        assertEq(USDC.balanceOf(address(_bidder)), 1);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999999999 * 1e18);

        // try to take a smaller-than-possible amount of USDC
        // should revert, because no quote token would be purchased
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.takeReserves(1e11);
        // bidder balances unchanged
        assertEq(USDC.balanceOf(address(_bidder)), 1);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999999999 * 1e18);

        // take a reasonable amount of USDC
        assertEq(USDC.balanceOf(address(_bidder)), 1);
        _pool.takeReserves(100 * 1e18);
        // bidder burned some AJNA
        assertEq(USDC.balanceOf(address(_bidder)), 100.000001 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999994599 * 1e18);

        // wait for price to be 0
        skip(7 hours);
        _assertReserveAuction({
            reserves:                   0.000000999954337900 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 999_200.334121638963821700 * 1e18,
            auctionPrice:               0,
            timeRemaining:              1 hours
        });

        // take 1 USDC should revert, because no AJNA would be burned
        assertEq(USDC.balanceOf(address(_bidder)), 100.000001 * 1e6);
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.takeReserves(1 * 1e18);
        // bidder balances unchanged
        assertEq(USDC.balanceOf(address(_bidder)), 100.000001 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999999999994599 * 1e18);
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
        pool.drawDebt(_actor3, 98903, 7388, 40);
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
        pool.drawDebt(_actor7, 98000, 7388, 999234524847);
        // pool balance decreased by new debt
        assertEq(_quote.balanceOf(address(pool)), 903);
        // available quote token decreased with new debt
        assertEq(_availableQuoteToken(), 903);

        vm.warp(block.timestamp + 86400);
        changePrank(_actor3);

        // repay debt to have enough balance to kick new reserves auction
        ERC20Pool(address(_pool)).repayDebt(_actor3, type(uint256).max, 0, _actor3, MAX_FENWICK_INDEX);
        ERC20Pool(address(_pool)).repayDebt(_actor7, type(uint256).max, 0, _actor7, MAX_FENWICK_INDEX);

        uint256 initialPoolBalance     = 200763;
        uint256 initialAvailableAmount = 200763;

        assertEq(_quote.balanceOf(address(pool)), initialPoolBalance);
        assertEq(_availableQuoteToken(), initialAvailableAmount);

        pool.kickReserveAuction();

        uint256 claimableTokens = 599;

        ( , , uint256 claimable, , ) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(claimable, claimableTokens);

        skip(24 hours);

        // mint and approve ajna tokens for taker
        deal(address(_ajna), _actor3, 1e45);
        ERC20(address(_ajna)).approve(address(_pool), type(uint256).max);

        assertEq(_quote.balanceOf(address(pool)), 200763);

        pool.takeReserves(claimableTokens);

        // quote token balance diminished by quote token taken from reserve auction
        assertEq(_quote.balanceOf(address(pool)), initialPoolBalance - claimableTokens);
        // available quote token (available to remove / draw debt from) is not modified
        assertEq(_availableQuoteToken(), initialAvailableAmount - claimableTokens);
    }

    function testReserveAuctionUnsettledLiquidation() external {
        // add reserves to the pool
        changePrank(_actor2);
        _quote.transfer(address(_pool), 1_000 * 1e18);
        _assertReserveAuction({
            reserves:                   1_000 * 1e18,
            claimableReserves :         1_000 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });
        skip(2 hours);

        // create an unsettled liquidation
        _addInitialLiquidity({
            from:   _actor2,
            amount: 12_000 * 1e18,
            index:  _i100_33
        });
        _drawDebt({
            from:               _actor3,
            borrower:           _actor3,
            amountToBorrow:     8_000 * 1e18,
            limitIndex:         _i100_33,
            collateralToPledge: 100 * 1e18,
            newLup:             _p100_33
        });
        _lenderKick({
            from:       _actor2,
            index:      _i100_33,
            borrower:   _actor3,
            debt:       8_007.692307692307696000 * 1e18,
            collateral: 100 * 1e18,
            bond:       89.528721714510806718 * 1e18
        });
        skip(73 hours);

        // confirm reserve auction may not be kicked
        _assertReserveAuctionUnsettledLiquidation();
    }

}

contract L2ERC20PoolReserveAuctionTest is Test {
    ERC20PoolFactory internal _poolFactory;
    ERC20Pool        internal _pool;
    ERC20            internal _ajna;
    Token            internal _collateral;
    Token            internal _quote;
    PoolInfoUtils    internal _poolInfo;
    address          internal _borrower;
    address          internal _lender;
    address          internal _bidder;

    function setUp() public {
        vm.createSelectFork(vm.envString("L2_ETH_RPC_URL"));

        // L2 bwAJNA token address (example is for Base)
        _ajna        = ERC20(0xf0f326af3b1Ed943ab95C29470730CC8Cf66ae47);
        _collateral  = new Token("Collateral", "C");
        _quote       = new Token("Quote", "Q");
        _poolFactory = new ERC20PoolFactory(address(_ajna));
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 1e18));
        _poolInfo    = new PoolInfoUtils();

        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");
        _bidder    = makeAddr("bidder");

        // mint tokens
        deal(address(_collateral), _borrower, 10 * 1e18);
        deal(address(_quote),      _borrower, 100 * 1e18);
        deal(address(_quote),      _lender,   10_000 * 1e18);
        deal(address(_ajna),       _bidder,   10 * 1e18);

        // add liquidity
        changePrank(_lender);
        _quote.approve(address(_pool), type(uint256).max);
        _pool.addQuoteToken(1_000 * 1e18, 2500, block.timestamp);

        // draw debt
        changePrank(_borrower);
        _collateral.approve(address(_pool), type(uint256).max);
        _pool.drawDebt(address(_borrower), 300 * 1e18, 7000, 1 * 1e18);
    }

    function testStartAndTakeL2ReserveAuction() external {
        // skip time to accumulate interest
        skip(26 weeks);

        // repay debt
        changePrank(_borrower);
        _quote.approve(address(_pool), type(uint256).max);
        _pool.repayDebt(address(_borrower), 400 * 1e18, 1 * 1e18, address(_borrower), 7000);

        // check token balances and confirm reserves are claimable
        assertEq(_quote.balanceOf(address(_bidder)), 0);
        assertEq(_ajna.balanceOf(address(_bidder)),  10 * 1e18);
        assertEq(_ajna.balanceOf(address(_pool)),    0);
        (, uint256 claimableReserves, , ,) = _poolInfo.poolReservesInfo(address(_pool));
        assertEq(claimableReserves, 1.471235273731403306 * 1e18);

        // kick reserve auction
        changePrank(_bidder);
        _pool.kickReserveAuction();
        (, , uint256 remaining, ,) = _poolInfo.poolReservesInfo(address(_pool));
        assertEq(remaining, 1.471235273731403306 * 1e18);

        // take all at reasonable price
        skip(32 hours);
        (, , , uint256 auctionPrice,) = _poolInfo.poolReservesInfo(address(_pool));
        assertEq(auctionPrice, 0.158255207587128891 * 1e18);
        _ajna.approve(address(_pool), type(uint256).max);
        _pool.takeReserves(2 * 1e18);

        // check token balances ensuring AJNA was burned
        assertEq(_quote.balanceOf(address(_bidder)), 1.471235273731403306 * 1e18);
        assertEq(_ajna.balanceOf(address(_bidder)),  9.767169356346130372 * 1e18);
        assertEq(_ajna.balanceOf(address(_pool)),    0);
    }
}