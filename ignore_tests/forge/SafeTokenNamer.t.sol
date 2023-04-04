// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';
import './utils/Tokens.sol';

import 'src/libraries/helpers/SafeTokenNamer.sol';

contract SafeTokenNamerTest is DSTestPlus {

    Token internal _ercCollateralOne;
    Token internal _ercQuoteOne;

    Token internal _ercCollateralTwo;
    Token internal _ercQuoteTwo;

    Token internal _tokenLong;

    NFTCollateralToken internal _nftCollateralOne;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _ercCollateralOne = new Token("Collateral 1", "C1");
        _ercQuoteOne      = new Token("Quote 1", "Q1");

        _ercCollateralTwo = new Token("Collateral 2", "C2");
        _ercQuoteTwo      = new Token("Quote 2", "Q2");

        _tokenLong        = new Token("TOKEN <TESTING LOTS OF CHARACTERS!!> 3", "TESTING_LONG_TOKEN_SYMBOL");

        _nftCollateralOne = new NFTCollateralToken();
    }

    function testERC20Name() external {
        assertEq(tokenName(address(_ercCollateralOne)), "Collateral 1");
        assertEq(tokenName(address(_ercCollateralTwo)), "Collateral 2");

        assertEq(tokenName(address(_tokenLong)), "TOKEN <TESTING LOTS OF CHARACTERS!!> 3");
    }

    function testERC20Symbol() external {
        assertEq(tokenSymbol(address(_ercCollateralOne)), "C1");
        assertEq(tokenSymbol(address(_ercCollateralTwo)), "C2");
        
        assertEq(tokenSymbol(address(_tokenLong)), "TESTING_LONG_TOKEN_SYMBOL");
    }

    function testERC721Name() external {
        assertEq(tokenName(address(_nftCollateralOne)), "NFTCollateral");
    }

    function testERC721Symbol() external {
        assertEq(tokenSymbol(address(_nftCollateralOne)), "NFTC");
    }

    function testMoonCatsMetadata() external {
        assertEq(tokenName(0x7C40c393DC0f283F318791d746d894DdD3693572), "Wrapped MoonCatsRescue");
        assertEq(tokenSymbol(0x7C40c393DC0f283F318791d746d894DdD3693572), "WMCR");
    }

    function testWETHMetadata() external {
        assertEq(tokenName(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), "Wrapped Ether");
        assertEq(tokenSymbol(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), "WETH");
    }
}
