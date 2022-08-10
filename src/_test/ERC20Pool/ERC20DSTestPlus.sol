// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 }  from "@solmate/tokens/ERC20.sol";
import { DSTestPlus }                             from "../utils/DSTestPlus.sol";

abstract contract ERC20DSTestPlus is DSTestPlus {

    // ERC20 events
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    // Pool events
    event AddCollateral(address indexed borrower_, uint256 amount_);
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);
    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);
    event RemoveCollateral(address indexed borrower_, uint256 amount_);

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

}
