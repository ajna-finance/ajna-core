// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { CollateralToken, QuoteToken }              from "./utils/Tokens.sol";
import { DSTestPlus }                               from "./utils/DSTestPlus.sol";
import { UserWithCollateral, UserWithQuoteToken }   from "./utils/Users.sol";

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

contract ERC20PoolPerformanceTest is DSTestPlus {
    ERC20Pool               internal _pool;
    CollateralToken         internal _collateral;
    QuoteToken              internal _quote;
    uint256                 internal _count = 7000;
    UserWithCollateral[]    internal _borrowers;
    UserWithQuoteToken[]    internal _lenders;
    uint8                   internal constant MAX_USERS = type(uint8).max;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithCollateral user = new UserWithCollateral();
            _collateral.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(_collateral, address(_pool), type(uint256).max);

            _borrowers.push(user);
        }

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithQuoteToken user = new UserWithQuoteToken();
            _quote.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(_quote, address(_pool), type(uint256).max);

            _lenders.push(user);
        }
    }
}
