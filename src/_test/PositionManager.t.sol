// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";


// https://w.mirror.xyz/mOUlpgkWA178HNUW7xR20TdbGRV6dMid7uChqxf9Z58




contract PositionManagerTest is DSTestPlus {
    PositionManager internal positionManager;
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    // UserWithQuoteToken internal alice;
    address alice;
    UserWithQuoteToken internal bob;

    // uint256 constant maxUint = 115792089237316195423570985008687907853269984665640564039457584007913129639935;
    uint256 constant approveBig = 50000000000 * 1e18;
    function setUp() public {
        // alice = new UserWithQuoteToken();
        alice = 0x02B9219F667d91fBe64F8f77F691dE3D1000F223;
        bob = new UserWithQuoteToken();

        collateral = new CollateralToken();
        quote = new QuoteToken();

        quote.mint(alice, 30000000000 * 1e18);
        quote.mint(address(bob), 10000000 * 1e18);

        pool = new ERC20Pool(collateral, quote);
        positionManager = new PositionManager();
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT() private {

    }

    function testMint() public {
        // execute calls from alice address
        vm.prank(alice);
        quote.approve(address(pool), approveBig);
        vm.prank(alice);
        quote.approve(address(positionManager), approveBig);

        emit log_uint(quote.balanceOf(alice));
        
        uint256 mintAmount = 50 * 1e18;
        uint256 mintPrice = 1000 * 10**18;

        // have alice execute mint to enable delegatecall
        vm.prank(alice);

        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(
                alice,
                address(pool),
                mintAmount,
                mintPrice
            );

        // test emitted Mint event
        vm.expectEmit(true,true,true,true);
        emit Mint(alice,mintAmount,mintPrice);

        // check tokenId has been incremented
        uint256 tokenId = positionManager.mint(mintParams);
        assert(tokenId != 0);

        // check position info
        // positionManager.getPosition(tokenId);

    }

    function testNFTTransfer() public {
        emit log("testing transfer");
    }

    function testGetPosition() public {}

    function testBurn() public {

    }

    function testRedeem() public {}
}
