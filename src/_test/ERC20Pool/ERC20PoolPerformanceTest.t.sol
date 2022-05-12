// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../../ERC20Pool.sol";
import { ERC20PoolFactory } from "../../ERC20PoolFactory.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolPerformanceTest is DSTestPlus {

    uint8 internal constant MAX_USERS = type(uint8).max;

    address              internal _poolAddress;
    CollateralToken      internal _collateral;
    ERC20Pool            internal _pool;
    QuoteToken           internal _quote;
    UserWithCollateral[] internal _borrowers;
    UserWithQuoteToken[] internal _lenders;

    uint256 internal _count = 7000;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);  

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
