// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

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

        assertEq(USDC.balanceOf(address(_borrower)), 92.130788 * 1e6);
        assertEq(USDC.balanceOf(address(_pool)),     1_007.869212 * 1e6);

        _assertReserveAuction({
            reserves:                   1.425573699803092 * 1e18,
            claimableReserves :         1.425573699803092 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick off a new auction
        _kickReserveAuction({
            from:              _bidder,
            remainingReserves: 1.411317962805061080 * 1e18,
            price:             1000000000 * 1e18,
            epoch:             1
        });

        skip(60 hours);

        _assertReserveAuction({
            reserves:                   0.000000736998030920 * 1e18,
            claimableReserves :         0.000000736998030920 * 1e18,
            claimableReservesRemaining: 1.411317962805061080 * 1e18,
            auctionPrice:               0.000000000867361737 * 1e18,
            timeRemaining:              43200
        });

        assertEq(USDC.balanceOf(address(_pool)),   1_007.854957 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 0.014255 * 1e6); // kicker reward
        assertEq(AJNA.balanceOf(address(_bidder)), 10 * 1e18);

        _pool.takeReserves(10 * 1e18);

        assertEq(USDC.balanceOf(address(_pool)),   1_006.443640 * 1e6);
        assertEq(USDC.balanceOf(address(_bidder)), 1.425572 * 1e6);
        assertEq(AJNA.balanceOf(address(_bidder)), 9.999999998775876800 * 1e18);
    }
}