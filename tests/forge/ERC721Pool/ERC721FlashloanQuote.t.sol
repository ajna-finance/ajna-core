// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';
import { Token }                from '../utils/Tokens.sol';

import 'src/erc721/ERC721Pool.sol';
import "src/base/interfaces/IERC3156FlashBorrower.sol";

import 'src/libraries/BucketMath.sol';
import 'src/libraries/Maths.sol';

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

        // lender adds liquidity and borrower draws debt
        _bucketPrice = 251.186576139566121965 * 1e18;
        _bucketId = PoolUtils.priceToIndex(_bucketPrice);
        assertEq(_bucketId, 3048);
        _addLiquidity(
            {
                from:   _lender,
                amount: 300 * 1e18,
                index:  _bucketId,
                newLup: BucketMath.MAX_PRICE
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
        // Ensure only quote token in the contract may be flashloaned
        skip(1 days);
        uint256 loanAmount = 100 * 1e18;
        assertEq(_pool.maxFlashLoan(address(_quote)), loanAmount);

        // TODO: check reserves before and after flashloan

        // Create an example defi strategy which produces enough yield to pay the fee
        SomeDefiStrategy strategy = new SomeDefiStrategy(_quote);
        deal(address(_quote), address(strategy), 10 * 1e18);

        // Create a flashloan borrower contract which interacts with the strategy
        bytes memory strategyCalldata = abi.encodeWithSignature("makeMoney(uint256)", loanAmount);
        FlashLoanBorrower flasher = new FlashLoanBorrower(address(strategy), strategyCalldata);

        // Check the fee and run approvals
        uint256 fee = _pool.flashFee(address(_quote), loanAmount);
        assertEq(fee, 0.096153846153846200 * 1e18);
        changePrank(address(flasher));
        _quote.approve(address(_pool),    loanAmount + fee);
        _quote.approve(address(strategy), loanAmount);

        // Use a flashloan to interact with the strategy
        assertEq(_quote.balanceOf(address(flasher)), 0);
        assertTrue(!flasher.callbackInvoked());
        _pool.flashLoan(flasher, address(_quote), loanAmount, new bytes(0));
        assertTrue(flasher.callbackInvoked());
        assertEq(_quote.balanceOf(address(flasher)), 3.403846153846153800 * 1e18);
    }

    function testCannotFlashloanMoreThanAvailable() external tearDown {
        FlashLoanBorrower flasher = new FlashLoanBorrower(address(0), new bytes(0));

        // Cannot flashloan more than the pool size
        _assertFlashloanTooLargeRevert(flasher, 350 * 1e18);

        // Cannot flashloan less than pool size but more than available quote token
        _assertFlashloanTooLargeRevert(flasher, 150 * 1e18);
    }

    function testCannotFlashloanWrongToken() external tearDown {
        FlashLoanBorrower flasher = new FlashLoanBorrower(address(0), new bytes(0));

        // Cannot flashloan the collateral
        _assertFlashloanUnavailableForToken(flasher, address(_collateral), 1);

        // Cannot flashloan a random address which isn't a token
        _assertFlashloanUnavailableForToken(flasher, makeAddr("nobody"), 1);
    }
}

contract FlashLoanBorrower is IERC3156FlashBorrower {
    bool    public   callbackInvoked = false;
    address internal strategy;
    bytes   internal strategyCallData;
    bytes32 public constant CALLBACK_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    constructor(address strategy_, bytes memory strategyCallData_) {
        strategy         = strategy_;
        strategyCallData = strategyCallData_;
    }

    function onFlashLoan(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external returns (bytes32 result_) {
        callbackInvoked = true;
        (bool success, ) = strategy.call(strategyCallData);
        if (success) result_ = CALLBACK_SUCCESS;
    }
}

// Example of some defi strategy which produces a fixed return
contract SomeDefiStrategy {
    Token public token;

    constructor(Token token_) {
        token = token_;
    }

    function makeMoney(uint256 amount_) external {
        // step 1: take deposit from caller
        token.transferFrom(msg.sender, address(this), amount_);
        // step 2: earn tree fiddy per 100 tokens
        uint256 reward = Maths.wmul(0.035 * 1e18, amount_);
        // step 3: profit
        token.transfer(msg.sender, amount_ + reward);
    }
}