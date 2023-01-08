// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract }                 from './ERC20DSTestPlus.sol';
import { FlashloanBorrower, SomeDefiStrategy } from '../utils/FlashloanBorrower.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/ERC20Pool.sol';

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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 100_000 * 1e18,
                index:  _bucketId
            }
        );

        // borrower draws debt
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   100 * 1e18
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     25_000 * 1e18,
                indexLimit: _bucketId,
                newLup:     _bucketPrice
            }
        );
        (uint256 poolDebt,,) = _pool.debtInfo();
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
}