// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import {DSTest} from "@ds-test/test.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";

import {Test} from "@std/Test.sol";
import {Vm} from "@std/Vm.sol";

contract DSTestPlus is DSTest, Test {
    // PositionManager events
    event Mint(address lender, address pool, uint256 tokenId);
    event MemorializePosition(address lender, uint256 tokenId);
    event Burn(address lender, uint256 price);
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);
    event DecreaseLiquidity(
        address lender,
        uint256 collateral,
        uint256 quote,
        uint256 price
    );

    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event AddQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event AddCollateral(address indexed borrower, uint256 amount);
    event RemoveCollateral(address indexed borrower, uint256 amount);
    event ClaimCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lps
    );
    event Borrow(address indexed borrower, uint256 lup, uint256 amount);
    event Repay(address indexed borrower, uint256 lup, uint256 amount);
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);
    event Purchase(
        address indexed bidder,
        uint256 indexed price,
        uint256 amount,
        uint256 collateral
    );
    event Liquidate(address indexed borrower, uint256 debt, uint256 collateral);

    function assertERC20Eq(ERC20 erc1, ERC20 erc2) internal {
        assertEq(address(erc1), address(erc2));
    }
}
