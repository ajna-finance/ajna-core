// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';
import {
    FlashloanBorrower,
    SomeDefiStrategy,
    SomeDefiStrategyWithRepayment
} from '../../utils/FlashloanBorrower.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

import { IPoolErrors } from 'src/interfaces/pool/IPool.sol'; 

contract ERC20PoolFlashloanTest is ERC20HelperContract {
    address internal _borrower;
    address internal _lender;
    uint    internal _bucketId;
    uint    internal _bucketPrice;

    function setUp() external {
        _lender    = makeAddr("lender");
        _borrower  = makeAddr("borrower");

        _mintQuoteAndApproveTokens(_lender,        100_000 * 1e18);
        _mintQuoteAndApproveTokens(_borrower,      5_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 100 * 1e18);

        // lender adds liquidity
        _bucketPrice = 502.433988063349232760 * 1e18;
        _bucketId = _indexOf(_bucketPrice);
        assertEq(_bucketId, 2909);

        _addInitialLiquidity({
            from:   _lender,
            amount: 100_000 * 1e18,
            index:  _bucketId
        });

        // borrower draws debt
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     25_000 * 1e18,
            indexLimit: _bucketId,
            newLup:     _bucketPrice
        });

        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(poolDebt, 25_024.038461538461550000 * 1e18);
    }

    function testCollateralFlashloan() external tearDown {
        skip(1 days);
        uint256 loanAmount = 100 * 1e18;
        assertEq(_pool.maxFlashLoan(address(_collateral)), loanAmount);

        // Create an example defi strategy
        SomeDefiStrategy strategy = new SomeDefiStrategy(_collateral);
        deal(address(_collateral), address(strategy), 10 * 1e18);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run the token approvals
        changePrank(address(flasher));
        _collateral.approve(address(_pool),    loanAmount);
        _collateral.approve(address(strategy), loanAmount);

        // Use a flashloan to interact with the strategy
        assertEq(_collateral.balanceOf(address(flasher)), 0);
        assertTrue(!flasher.callbackInvoked());

        vm.expectEmit(true, true, false, true);
        emit Flashloan(address(flasher), address(_collateral), loanAmount);
        _pool.flashLoan(flasher, address(_collateral), loanAmount, new bytes(0));
        assertTrue(flasher.callbackInvoked());
        assertEq(_collateral.balanceOf(address(flasher)), 3.5 * 1e18);
    }

    function testFlashloanFee() external tearDown {
        uint256 loanAmount = 100 * 1e18;

        // Ensure there is no fee for quote token
        uint256 fee = _pool.flashFee(address(_quote), loanAmount);
        assertEq(fee, 0);

        // Ensure there is no fee for collateral
        fee = _pool.flashFee(address(_collateral), loanAmount);
        assertEq(fee, 0);

        // Ensure fee reverts for a random address which isn't a token
        _assertFlashloanFeeRevertsForToken(makeAddr("nobody"), loanAmount);
    }

    function testMaxFlashloan() external tearDown {
        assertEq(_pool.maxFlashLoan(_pool.quoteTokenAddress()), 75_000 * 1e18);
        assertEq(_pool.maxFlashLoan(_pool.collateralAddress()), 100 * 1e18);
        assertEq(_pool.maxFlashLoan(makeAddr("nobody")), 0);
    }

    function testCannotFlashloanMoreCollateralThanAvailable() external tearDown {
        FlashloanBorrower flasher = new FlashloanBorrower(address(0), new bytes(0));

        // Cannot flashloan less than pool size but more than available quote token
        _assertFlashloanTooLargeRevert(flasher, _pool.quoteTokenAddress(), 90_000 * 1e18);

        // Cannot flashloan more collateral than pledged
        _assertFlashloanTooLargeRevert(flasher, _pool.collateralAddress(), 150 * 1e18);
    }

    function testCannotFlashloanNonToken() external tearDown {
        FlashloanBorrower flasher = new FlashloanBorrower(address(0), new bytes(0));

        // Cannot flashloan a random address which isn't a token
        _assertFlashloanUnavailableForToken(flasher, makeAddr("nobody"), 1);
    }

    function testCallbackFailure() external tearDown {
        uint256 loanAmount = 100 * 1e18;

        // Create an example defi strategy
        SomeDefiStrategy strategy = new SomeDefiStrategy(_collateral);

        // Create a flashloan borrower contract which invokes a non-existant method on the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("missing()");
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run approvals
        changePrank(address(flasher));
        _quote.approve(address(_pool), loanAmount);

        // Make a failed attempt to interact with the strategy
        vm.expectRevert(IPoolErrors.FlashloanCallbackFailed.selector);
        _pool.flashLoan(flasher, address(_collateral), loanAmount, new bytes(0));
        assertFalse(flasher.callbackInvoked());
    }

    function testIncorrectBalanceAfterFlashloanFailure() external tearDown {
        skip(1 days);
        uint256 loanAmount = 100 * 1e18;
        assertEq(_pool.maxFlashLoan(address(_collateral)), loanAmount);

        // Create an example defi strategy that pays a fee to pool contract
        SomeDefiStrategyWithRepayment strategy = new SomeDefiStrategyWithRepayment(_collateral, address(_pool));
        deal(address(_collateral), address(strategy), 10 * 1e18);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run the token approvals
        changePrank(address(flasher));
        _collateral.approve(address(_pool),    loanAmount);
        _collateral.approve(address(strategy), loanAmount);

        // should revert as the pool balance after flashloan is different than the initial balance
        vm.expectRevert(IPoolErrors.FlashloanIncorrectBalance.selector);
        _pool.flashLoan(flasher, address(_collateral), loanAmount, new bytes(0));
    }
}

contract ERC20PoolFlashloanPrecisionTest is ERC20HelperContract {

    ERC20 WBTC = ERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    ERC20 USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _pool       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(WBTC), address(USDC), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");

        deal(address(WBTC), _borrower, 10 * 1e8);

        deal(address(USDC), _lender,   10_000 * 1e6);

        vm.startPrank(_borrower);
        WBTC.approve(address(_pool), 10 * 1e18);

        changePrank(_lender);
        USDC.approve(address(_pool), 10_000 * 1e18);

        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2500
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   10 * 1e18
        });
    }

    function testWbtcFlashloan() external tearDown {
        skip(1 days);
        uint256 loanAmount = 10 * 1e8;
        assertEq(_pool.maxFlashLoan(address(WBTC)), 10 * 1e8);

        // Create an example defi strategy
        SomeDefiStrategy strategy = new SomeDefiStrategy(WBTC);
        deal(address(WBTC), address(strategy), 10 * 1e8);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run the token approvals
        changePrank(address(flasher));
        WBTC.approve(address(_pool),    loanAmount);
        WBTC.approve(address(strategy), loanAmount);

        // cannot flashloan more than available in pool (by specifying pool instead collateral precision)
        vm.expectRevert('SafeERC20: low-level call failed');
        _pool.flashLoan(flasher, address(WBTC), 10 * 1e18, new bytes(0));

        // Use a flashloan to interact with the strategy
        assertEq(WBTC.balanceOf(address(flasher)), 0);
        assertTrue(!flasher.callbackInvoked());

        vm.expectEmit(true, true, false, true);
        emit Flashloan(address(flasher), address(WBTC), loanAmount);
        _pool.flashLoan(flasher, address(WBTC), loanAmount, new bytes(0));
        assertTrue(flasher.callbackInvoked());
        assertEq(WBTC.balanceOf(address(flasher)), 0.35 * 1e8);
    }

    function testUsdcFlashloan() external tearDown {
        skip(1 days);
        uint256 loanAmount = 10_000 * 1e6;
        assertEq(_pool.maxFlashLoan(address(USDC)), loanAmount);

        // Create an example defi strategy which produces enough yield to pay the fee
        SomeDefiStrategy strategy = new SomeDefiStrategy(USDC);
        deal(address(USDC), address(strategy), 10_000 * 1e6);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run approvals
        changePrank(address(flasher));
        USDC.approve(address(_pool),    loanAmount);
        USDC.approve(address(strategy), loanAmount);

        // cannot flashloan more than available in pool (by specifying pool instead quote token precision)
        vm.expectRevert('ERC20: transfer amount exceeds balance');
        _pool.flashLoan(flasher, address(USDC), 10_000 * 1e18, new bytes(0));

        // Use a flashloan to interact with the strategy
        assertEq(USDC.balanceOf(address(flasher)), 0);
        assertTrue(!flasher.callbackInvoked());

        vm.expectEmit(true, true, false, true);
        emit Flashloan(address(flasher), address(USDC), loanAmount);
        _pool.flashLoan(flasher, address(USDC), loanAmount, new bytes(0));
        assertTrue(flasher.callbackInvoked());
        assertEq(USDC.balanceOf(address(flasher)), 350 * 1e6);
    }

}