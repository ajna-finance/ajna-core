
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../erc20/ERC20PoolFactory.sol";

import { ERC20BorrowerManager } from "../erc20/ERC20BorrowerManager.sol";

import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

import { DSTestPlus } from "./utils/DSTestPlus.sol";

contract BorrowQueueTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _quote.mint(address(_lender), 300_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 300_000 * 1e18);
    }



    function testGetHighestThresholdPrice () public {}

    function testAddLoanToQueue() public {
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p12_66);

        // borrow max possible from hdp
        _borrower.addCollateral(_pool, 51 * 1e18);
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18);

        (uint256 thresholdPrice ,address next) = _pool.loans(address(_borrower));

        _pool.updateLoanQueue(address(_borrower), thresholdPrice, address(0), address(0));

        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.head()));
    }


}