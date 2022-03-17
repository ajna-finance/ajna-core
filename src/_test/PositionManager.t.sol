// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

contract PositionManagerTest is DSTestPlus {

    PositionManager internal positionManager;
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithQuoteToken internal alice;
    UserWithQuoteToken internal bob;

    function setUp() public {
        alice = new UserWithQuoteToken();
        bob = new UserWithQuoteToken();

        collateral = new CollateralToken();
        quote = new QuoteToken();

        quote.mint(address(alice), 100 * 1e18);
        quote.mint(address(bob), 100 * 1e18);

        pool = new ERC20Pool(collateral, quote);

        positionManager = new PositionManager();
    }

    function testMint() public {
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(
            address(alice),
            address(pool),
            50 * 1e18,
            1000 * 10 ** 18
        );

        uint256 tokenId = positionManager.mint(mintParams);
        assert(tokenId != 0);

    }

    function testNFTTransfer() public {}

}
