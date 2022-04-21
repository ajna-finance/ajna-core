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

    function mintAndApproveQuoteTokens(
        address operator,
        uint256 mintAmount
    ) private {
        quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        quote.approve(address(pool), type(uint256).max);
        vm.prank(operator);
        quote.approve(address(positionManager), type(uint256).max);
    }

    function testMulticallMintIncreaseLiquidity() public {
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
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(testAddress, address(pool));
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
        uint256 newPriceToAddQuoteTokensTo = 10000 * 1e18;
        IPositionManager.IncreaseLiquidityParams memory increaseLiquidityParams = IPositionManager
            .IncreaseLiquidityParams(tokenId, testAddress, address(pool), additionalAmount, newPriceToAddQuoteTokensTo);

        bytes[] memory callsToExecute = new bytes[](2);

        // TODO: seriealize structs for passing to multicall: https://github.com/pouladzade/Seriality
        callsToExecute[0] = memorializeParams;
        callsToExecute[1] = increaseLiquidityParams;

        positionManager.multicall(callsToExecute);



    }

}