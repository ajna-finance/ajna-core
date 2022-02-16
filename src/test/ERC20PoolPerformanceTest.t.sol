// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.10;

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pool} from "../ERC20Pool.sol";

contract ERC20PoolPerformanceTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;
    uint256 internal count = 7000;

    UserWithCollateral[] internal borrowers;
    UserWithQuoteToken[] internal lenders;

    uint8 internal constant MAX_USERS = type(uint8).max;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        pool = new ERC20Pool(collateral, quote);

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithCollateral user = new UserWithCollateral();
            collateral.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(collateral, address(pool), type(uint256).max);

            borrowers.push(user);
        }

        for (uint256 i; i < MAX_USERS; ++i) {
            UserWithQuoteToken user = new UserWithQuoteToken();
            quote.mint(address(user), 1_000_000 * 1e18);
            user.approveToken(quote, address(pool), type(uint256).max);

            lenders.push(user);
        }
    }
}
