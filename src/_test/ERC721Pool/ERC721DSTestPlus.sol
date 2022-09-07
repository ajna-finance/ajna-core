// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { DSTestPlus }                from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, Token } from "../utils/Tokens.sol";

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
}

abstract contract ERC721HelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    ERC721Pool         internal _collectionPool;
    ERC721Pool         internal _subsetPool;

    // TODO: bool for pool type
    constructor() {
        _collateral = new NFTCollateralToken();
        _quote      = new Token("Quote", "Q");
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        return ERC721Pool(new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        return ERC721Pool(new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
    }

    function _getPoolAddresses() internal view returns (address[] memory poolAddresses_) {
        poolAddresses_ = new address[](2);
        poolAddresses_[0] = address(_collectionPool);
        poolAddresses_[1] = address(_subsetPool);
    }

    // TODO: finish implementing
    function _approveQuoteMultipleUserMultiplePool() internal {

    }

    function _mintAndApproveQuoteTokens(address[] memory pools_, address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        for (uint i; i < pools_.length;) {
            vm.prank(operator_);
            _quote.approve(address(pools_[i]), type(uint256).max);
            unchecked {
                ++i;
            }
        }
    }

    function _mintAndApproveCollateralTokens(address[] memory pools_, address operator_, uint256 mintAmount_) internal {
        _collateral.mint(operator_, mintAmount_);

        for (uint i; i < pools_.length;) {
            vm.prank(operator_);
            _collateral.setApprovalForAll(address(pools_[i]), true);
            unchecked {
                ++i;
            }
        }
    }

    // TODO: implement this
    function _assertBalances() internal {}

    // TODO: check oldPrev and newPrev
    function _pledgeCollateral(address pledger_, address borrower_, ERC721Pool pool_, uint256[] memory tokenIdsToAdd_) internal {
        vm.prank(pledger_);
        for (uint i; i < tokenIdsToAdd_.length;) {
            emit Transfer(address(borrower_), address(pool_), tokenIdsToAdd_[i]);
            vm.expectEmit(true, true, false, true);
            unchecked {
                ++i;
            }
        }
        emit PledgeCollateralNFT(address(borrower_), tokenIdsToAdd_);
        pool_.pledgeCollateral(borrower_, tokenIdsToAdd_);
    }

    // TODO: implement _pullCollateral()

}
