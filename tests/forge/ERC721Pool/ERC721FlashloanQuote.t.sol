// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract }                from './ERC721DSTestPlus.sol';
import { FlashloanBorrower, SomeDefiStrategy } from '../utils/FlashloanBorrower.sol';

import 'src/ERC721Pool.sol';
import 'src/libraries/internal/Maths.sol';

import { _indexOf } from 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolFlashloanTest is ERC721HelperContract {
    address internal _borrower;
    address internal _lender;
    uint    internal _bucketId;
    uint    internal _bucketPrice;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 5_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower, 1);

        // lender adds liquidity
        _bucketPrice = 251.186576139566121965 * 1e18;
        _bucketId = _indexOf(_bucketPrice);
        assertEq(_bucketId, 3048);
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 300 * 1e18,
                index:  _bucketId
            }
        );

        // borrower draws debt
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     200 * 1e18,
                indexLimit: _bucketId,
                newLup:     _bucketPrice
            }
        );
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, 200.192307692307692400 * 1e18);
    }

    function testQuoteTokenFlashloan() external tearDown {        
        skip(1 days);
        uint256 loanAmount = 100 * 1e18;
        assertEq(_pool.maxFlashLoan(address(_quote)), loanAmount);

        // Create an example defi strategy which produces enough yield to pay the fee
        SomeDefiStrategy strategy = new SomeDefiStrategy(_quote);
        deal(address(_quote), address(strategy), 10 * 1e18);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run approvals
        changePrank(address(flasher));
        _quote.approve(address(_pool),    loanAmount);
        _quote.approve(address(strategy), loanAmount);

        // Use a flashloan to interact with the strategy
        assertEq(_quote.balanceOf(address(flasher)), 0);
        assertTrue(!flasher.callbackInvoked());
        _pool.flashLoan(flasher, address(_quote), loanAmount, new bytes(0));
        assertTrue(flasher.callbackInvoked());
        assertEq(_quote.balanceOf(address(flasher)), 3.5 * 1e18);
    }

    function testFlashloanFee() external tearDown {
        uint256 loanAmount = 100 * 1e18;

        // Ensure there is no fee for quote token
        uint256 fee = _pool.flashFee(address(_quote), loanAmount);
        assertEq(fee, 0);

        // Ensure fee reverts for nonfungible collateral
        _assertFlashloanFeeRevertsForToken(address(_collateral), loanAmount);

        // Ensure fee reverts for a random address which isn't a token
        _assertFlashloanFeeRevertsForToken(makeAddr("nobody"), loanAmount);
    }

    function testCannotFlashloanMoreThanAvailable() external tearDown {
        FlashloanBorrower flasher = new FlashloanBorrower(address(0), new bytes(0));

        // Cannot flashloan more than the pool size
        _assertFlashloanTooLargeRevert(flasher, _pool.quoteTokenAddress(), 350 * 1e18);

        // Cannot flashloan less than pool size but more than available quote token
        _assertFlashloanTooLargeRevert(flasher, _pool.quoteTokenAddress(), 150 * 1e18);
    }

    function testCannotFlashloanWrongToken() external tearDown {
        FlashloanBorrower flasher = new FlashloanBorrower(address(0), new bytes(0));

        // Cannot flashloan the collateral
        _assertFlashloanUnavailableForToken(flasher, address(_collateral), 1);

        // Cannot flashloan a random address which isn't a token
        _assertFlashloanUnavailableForToken(flasher, makeAddr("nobody"), 1);
    }

    function testCallbackFailure() external {
        uint256 loanAmount = 100 * 1e18;

        // Create an example defi strategy
        SomeDefiStrategy strategy = new SomeDefiStrategy(_quote);

        // Create a flashloan borrower contract which invokes a non-existant method on the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("missing()");
        FlashloanBorrower flasher = new FlashloanBorrower(address(strategy), strategyCalldata);

        // Run approvals
        changePrank(address(flasher));
        _quote.approve(address(_pool),    loanAmount);

        // Make a failed attempt to interact with the strategy
        vm.expectRevert(IPoolErrors.FlashloanCallbackFailed.selector);
        _pool.flashLoan(flasher, address(_quote), loanAmount, new bytes(0));
        assertFalse(flasher.callbackInvoked());
    }
}