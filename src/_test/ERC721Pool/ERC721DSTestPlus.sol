// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

import { DSTestPlus }                from '../utils/DSTestPlus.sol';
import { NFTCollateralToken, Token } from '../utils/Tokens.sol';

import { ERC721Pool }        from '../../erc721/ERC721Pool.sol';
import { ERC721PoolFactory } from '../../erc721/ERC721PoolFactory.sol';

import '../../erc721/interfaces/IERC721Pool.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

abstract contract ERC721DSTestPlus is DSTestPlus {

    // Pool events
    event AddCollateralNFT(address indexed actor_, uint256 indexed price_, uint256[] tokenIds_);
    event PledgeCollateralNFT(address indexed borrower_, uint256[] tokenIds_);
    event PullCollateralNFT(address indexed borrower_, uint256[] tokenIds_);
    event RemoveCollateralNFT(address indexed claimer_, uint256 indexed price_, uint256[] tokenIds_);

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /*****************/
    /*** Utilities ***/
    /*****************/

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _addCollateral(
        address from,
        uint256[] memory tokenIds,
        uint256 index
    ) internal returns (uint256){
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AddCollateralNFT(from, index, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), i);
        }
        return ERC721Pool(address(_pool)).addCollateral(tokenIds, index);
    }

    function _pledgeCollateral(
        address from,
        address borrower,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateralNFT(borrower, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), i);
        }
        ERC721Pool(address(_pool)).pledgeCollateral(borrower, tokenIds);
    }

    function _pullCollateral(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit PullCollateralNFT(from, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit Transfer(address(_pool), from, i);
        }
        ERC721Pool(address(_pool)).pullCollateral(tokenIds);
    }

    function _removeCollateral(
        address from,
        uint256[] memory tokenIds,
        uint256 index,
        uint256 lpRedeem
    ) internal returns (uint256 lpRedeemed_) {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RemoveCollateralNFT(from, index, tokenIds);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            vm.expectEmit(true, true, false, true);
            emit Transfer(address(_pool), from, i);
        }
        lpRedeemed_ = ERC721Pool(address(_pool)).removeCollateral(tokenIds, index);
        assertEq(lpRedeem, lpRedeemed_);
    }


    /**********************/
    /*** Revert asserts ***/
    /**********************/

    function _assertPledgeCollateralNotInSubsetRevert(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectRevert(IERC721PoolErrors.OnlySubset.selector);
        ERC721Pool(address(_pool)).pledgeCollateral(from, tokenIds);
    }

    function _assertPullInsufficientCollateralRevert(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC721Pool(address(_pool)).pullCollateral(tokenIds);
    }

    function _assertPullNotDepositedCollateralRevert(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectRevert(IERC721PoolErrors.TokenNotDeposited.selector);
        ERC721Pool(address(_pool)).pullCollateral(tokenIds);
    }

    function _assertPullTokenRevert(
        address from,
        uint256[] memory tokenIds
    ) internal {
        changePrank(from);
        vm.expectRevert(IERC721PoolErrors.RemoveTokenFailed.selector);
        ERC721Pool(address(_pool)).pullCollateral(tokenIds);
    }

    function _assertRemoveCollateralInsufficientLPsRevert(
        address from,
        uint256[] memory tokenIds,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLPs.selector);
        ERC721Pool(address(_pool)).removeCollateral(tokenIds, index);
    }

    function _assertRemoveInsufficientCollateralRevert(
        address from,
        uint256[] memory tokenIds,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC721Pool(address(_pool)).removeCollateral(tokenIds, index);
    }

    function _assertRemoveNotDepositedTokenRevert(
        address from,
        uint256[] memory tokenIds,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IERC721PoolErrors.TokenNotDeposited.selector);
        ERC721Pool(address(_pool)).removeCollateral(tokenIds, index);
    }

}

abstract contract ERC721HelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    ERC20              internal _ajna;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _collateral = new NFTCollateralToken();
        vm.makePersistent(address(_collateral));
        _quote      = new Token("Quote", "Q");
        vm.makePersistent(address(_quote));
        _ajna       = ERC20(address(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079));
        vm.makePersistent(address(_ajna));
        _poolUtils  = new PoolInfoUtils();
        vm.makePersistent(address(_poolUtils));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        address contractAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        return ERC721Pool(contractAddress);
    }

    function _deploySubsetPool(uint256[] memory subsetTokenIds_) internal returns (ERC721Pool) {
        _startTime = block.timestamp;
        return ERC721Pool(new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds_, 0.05 * 10**18));
    }

    // TODO: finish implementing
    function _approveQuoteMultipleUserMultiplePool() internal {

    }

    function _mintAndApproveQuoteTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
    }

    function _mintAndApproveCollateralTokens(address operator_, uint256 mintAmount_) internal {
        _collateral.mint(operator_, mintAmount_);
        vm.prank(operator_);
        _collateral.setApprovalForAll(address(_pool), true);
    }

    function _mintAndApproveAjnaTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_ajna), operator_, mintAmount_);
        vm.prank(operator_);
        _ajna.approve(address(_pool), type(uint256).max);
    }
}
