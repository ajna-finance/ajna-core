

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';
import './utils/Tokens.sol';

import 'src/libraries/SafeTokenNamer.sol';

// https://github.com/Uniswap/solidity-lib/blob/master/test/SafeERC20Namer.spec.ts


contract SafeTokenNamerTest is DSTestPlus {

    Token           internal _ercCollateralOne;
    Token           internal _ercQuoteOne;

    Token           internal _ercCollateralTwo;
    Token           internal _ercQuoteTwo;

    Token           internal _tokenLong;

    NFTCollateralToken internal _nftCollateralOne;

    function setUp() external {
        _ercCollateralOne = new Token("Collateral 1", "C1");
        _ercQuoteOne      = new Token("Quote 1", "Q1");

        _ercCollateralTwo = new Token("Collateral 2", "C2");
        _ercQuoteTwo      = new Token("Quote 2", "Q2");

        _tokenLong      = new Token("TOKEN <TESTING LOTS OF CHARACTERS!!> 3", "TESTING_LONG_TOKEN_SYMBOL");

        _nftCollateralOne = new NFTCollateralToken();
    }


    function testERC20Name() external {
        assertEq(SafeTokenNamer.tokenName(address(_ercCollateralOne)), "Collateral 1");
        assertEq(SafeTokenNamer.tokenName(address(_ercCollateralTwo)), "Collateral 2");

        assertEq(SafeTokenNamer.tokenName(address(_tokenLong)), "TOKEN <TESTING LOTS OF CHARACTERS!!> 3");
    }

    function testERC20Symbol() external {
        assertEq(SafeTokenNamer.tokenSymbol(address(_ercCollateralOne)), "C1");
        assertEq(SafeTokenNamer.tokenSymbol(address(_ercCollateralTwo)), "C2");
        
        assertEq(SafeTokenNamer.tokenSymbol(address(_tokenLong)), "TESTING_LONG_TOKEN_SYMBOL");
    }

    function testERC721Name() external {
        assertEq(SafeTokenNamer.tokenName(address(_nftCollateralOne)), "NFTCollateral");
    }

    function testERC721Symbol() external {
        assertEq(SafeTokenNamer.tokenSymbol(address(_nftCollateralOne)), "NFTC");
    }
}
