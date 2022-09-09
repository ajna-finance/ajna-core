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

    /*****************/
    /*** Utilities ***/
    /*****************/

    struct PoolState {
        uint256 htp;
        uint256 lup;
        uint256 poolSize;
        uint256 pledgedCollateral;
        uint256 encumberedCollateral;
        uint256 borrowerDebt;
        uint256 actualUtilization;
        uint256 targetUtilization;
        uint256 minDebtAmount;
        uint256 loans;
        address maxBorrower;
    }

    struct ReserveAuctionState {
        uint256 claimableReservesRemaining;
        uint256 auctionPrice;
    }
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
        vm.makePersistent(address(_collateral));
        _quote      = new Token("Quote", "Q");
        vm.makePersistent(address(_quote));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        address contractAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        vm.makePersistent(contractAddress);
        vm.makePersistent(address(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079)); // HACK: doesn't help; will remove
        return ERC721Pool(contractAddress);
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
    
    function _assertPool(PoolState memory state_) internal {
        ERC721Pool pool = address(_collectionPool) == address(0) ? _subsetPool : _collectionPool;
        
        assertEq(pool.htp(), state_.htp);
        assertEq(pool.lup(), state_.lup);

        assertEq(pool.poolSize(),              state_.poolSize);
        assertEq(pool.pledgedCollateral(),     state_.pledgedCollateral);
        assertEq(pool.borrowerDebt(),          state_.borrowerDebt);
        assertEq(pool.poolActualUtilization(), state_.actualUtilization);
        assertEq(pool.poolTargetUtilization(), state_.targetUtilization);
        assertEq(pool.poolMinDebtAmount(),     state_.minDebtAmount);

        assertEq(pool.loansCount(),  state_.loans);
        assertEq(pool.maxBorrower(), state_.maxBorrower);

        assertEq(pool.encumberedCollateral(state_.borrowerDebt, state_.lup), state_.encumberedCollateral);
    }

    function _assertReserveAuction(ReserveAuctionState memory state_) internal {
        ERC721Pool pool = address(_collectionPool) == address(0) ? _subsetPool : _collectionPool;

        (uint256 claimableReservesRemaining, uint256 auctionPrice) = pool.reserveAuction();
        assertEq(claimableReservesRemaining, state_.claimableReservesRemaining);
        assertEq(auctionPrice, state_.auctionPrice);
    }
}
