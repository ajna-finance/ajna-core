// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { DSTestPlus } from "../utils/DSTestPlus.sol";

abstract contract ERC721DSTestPlus is DSTestPlus {

    // ERC721 events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    // Pool events
    event AddCollateralNFT(address indexed actor_, uint256 indexed price_, uint256[] tokenIds_);
    event PledgeCollateralNFT(address indexed borrower_, uint256[] tokenIds_);
    event PurchaseWithNFTs(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256[] tokenIds_);
    event PullCollateralNFT(address indexed borrower_, uint256[] tokenIds_);
    event RemoveCollateralNFT(address indexed claimer_, uint256 indexed price_, uint256[] tokenIds_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    // TODO: implement this for simplifying construction and maintenance of tests
    function assertPoolState() internal {

        // assertEq();
        // assertEq(_pool.htp(), 0);
        // assertEq(_pool.lup(), BucketMath.MAX_PRICE);

        // assertEq(_pool.treeSum(),      110_162.490615980593600000 * 1e18);
        // assertEq(_pool.borrowerDebt(), 0);
        // assertEq(_pool.lenderDebt(),   0);
    }

    function assertPoolCollateralBalance() internal {

    }

    function assertPoolQuoteBalance() internal {

    }

}
