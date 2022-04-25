// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

contract MulticallTest is DSTestPlus {
    PositionManager internal positionManager;
    ERC20Pool internal pool;
    ERC20PoolFactory internal factory;

    CollateralToken internal collateral;
    QuoteToken internal quote;

    // nonce for generating random addresses
    uint16 nonce = 0;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));

        positionManager = new PositionManager();
    }

    // TODO: move this to _test/utils/...
    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(
            uint160(uint256(keccak256(abi.encodePacked(nonce, blockhash(block.number)))))
        );
        nonce++;
    }

    function mintAndApproveQuoteTokens(address operator, uint256 mintAmount) private {
        quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        quote.approve(address(pool), type(uint256).max);
        vm.prank(operator);
        quote.approve(address(positionManager), type(uint256).max);
    }

    /// @notice Use multicall to aggregate memorializePosition and increaseLiquidity method calls into one tx
    function testMulticallMemorializeIncreaseLiquidity() public {
        address testAddress = generateAddress();
        uint256 mintAmount = 10000 * 1e18;

        mintAndApproveQuoteTokens(testAddress, mintAmount);

        // add quote tokens to several buckets
        uint256 priceOne = 4_000.927678580567537368 * 1e18;
        uint256 priceTwo = 3_010.892022197881557845 * 1e18;
        uint256 priceThree = 1_004.989662429170775094 * 1e18;
        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceOne);
        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceTwo);
        pool.addQuoteToken(address(testAddress), 3_000 * 1e18, priceThree);

        // mint an NFT capable of representing the positions
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(
            testAddress,
            address(pool)
        );
        uint256 tokenId = positionManager.mint(mintParams);

        // Prepare to memorialize the extant positions with the just minted NFT
        uint256[] memory pricesToMemorialize = new uint256[](3);
        pricesToMemorialize[0] = priceOne;
        pricesToMemorialize[1] = priceTwo;
        pricesToMemorialize[2] = priceThree;

        IPositionManager.MemorializePositionsParams memory memorializeParams = IPositionManager
            .MemorializePositionsParams(tokenId, testAddress, address(pool), pricesToMemorialize);

        // Prepare to add quotte tokens to a new price bucket and associate with NFT
        uint256 additionalAmount = 1000 * 1e18;
        uint256 newPriceToAddQuoteTokensTo = 5_007.644384905151472283 * 1e18;
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(
                tokenId,
                testAddress,
                address(pool),
                additionalAmount,
                newPriceToAddQuoteTokensTo
            );

        bytes[] memory callsToExecute = new bytes[](2);

        // https://ethereum.stackexchange.com/questions/65980/passing-struct-as-an-argument-in-call
        callsToExecute[0] = abi.encodeWithSignature(
            "memorializePositions((uint256,address,address,uint256[]))",
            memorializeParams
        );
        callsToExecute[1] = abi.encodeWithSignature(
            "increaseLiquidity((uint256,address,address,uint256,uint256))",
            increaseLiquidityParams
        );

        uint256 lpTokensAtNewPrice = positionManager.getLPTokens(
            tokenId,
            newPriceToAddQuoteTokensTo
        );
        assertEq(lpTokensAtNewPrice, 0);

        vm.expectEmit(true, true, true, true);
        emit MemorializePosition(testAddress, tokenId);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(testAddress, additionalAmount, newPriceToAddQuoteTokensTo);

        vm.prank(testAddress);
        bytes[] memory results = positionManager.multicall(callsToExecute);

        lpTokensAtNewPrice = positionManager.getLPTokens(tokenId, newPriceToAddQuoteTokensTo);
        assertGt(lpTokensAtNewPrice, 0);
    }

    /// @notice Attempt two different multicalls that should revert and verify the revert reason is captured and returned properly
    function testMulticallRevertString() public {
        address recipient = generateAddress();
        address externalCaller = generateAddress();

        // mint an NFT
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(
            recipient,
            address(pool)
        );
        uint256 tokenId = positionManager.mint(mintParams);

        uint256 mintAmount = 10000 * 1e18;
        uint256 mintPrice = 5_007.644384905151472283 * 1e18;
        mintAndApproveQuoteTokens(recipient, mintAmount);

        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(tokenId, recipient, address(pool), mintAmount, mintPrice);

        // construct BurnParams
        IPositionManager.BurnParams memory burnParams = IPositionManager.BurnParams(
            tokenId,
            recipient,
            mintPrice
        );

        bytes[] memory callsToExecute = new bytes[](2);

        // https://ethereum.stackexchange.com/questions/65980/passing-struct-as-an-argument-in-call
        callsToExecute[0] = abi.encodeWithSignature(
            "increaseLiquidity((uint256,address,address,uint256,uint256))",
            increaseLiquidityParams
        );
        callsToExecute[1] = abi.encodeWithSignature("burn((uint256,address,uint256))", burnParams);

        // attempt to modify the NFT from an unapproved EOA
        vm.prank(externalCaller);
        vm.expectRevert("ajna/not-approved");
        positionManager.multicall(callsToExecute);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(recipient, mintAmount, mintPrice);

        // attempt to increase liquidity and then burn the NFT without decreasing liquidity
        vm.prank(recipient);
        vm.expectRevert("ajna/liquidity-not-removed");
        positionManager.multicall(callsToExecute);
    }
}
