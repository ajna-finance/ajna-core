// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 }             from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
    event ReserveAuction(uint256 claimableReservesRemaining_, uint256 auctionPrice_);

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
        uint256 timeRemaining;
    }
}

abstract contract ERC721HelperContract is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    ERC20              internal _ajna;
    ERC721Pool         internal _collectionPool;
    ERC721Pool         internal _subsetPool;

    // TODO: bool for pool type
    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _collateral = new NFTCollateralToken();
        vm.makePersistent(address(_collateral));
        _quote      = new Token("Quote", "Q");
        vm.makePersistent(address(_quote));
        _ajna       = ERC20(address(0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079));
        vm.makePersistent(address(_ajna));
    }

    function _deployCollectionPool() internal returns (ERC721Pool) {
        address contractAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        vm.makePersistent(contractAddress);
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

    function _mintAndApproveAjnaTokens(address[] memory pools_, address operator_, uint256 mintAmount_) internal {
        deal(address(_ajna), operator_, mintAmount_);

        for (uint i; i < pools_.length;) {
            vm.prank(operator_);
            _ajna.approve(address(pools_[i]), type(uint256).max);
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
        ( , uint256 htp, uint256 lup, ) = pool.poolPricesInfo();
        (uint256 poolSize, uint256 loansCount, address maxBorrower, ) = pool.poolLoansInfo();
        (uint256 poolMinDebtAmount, , uint256 poolActualUtilization, uint256 poolTargetUtilization) = pool.poolUtilizationInfo();
        assertEq(htp, state_.htp);
        assertEq(lup, state_.lup);

        assertEq(poolSize,                 state_.poolSize);
        assertEq(pool.pledgedCollateral(), state_.pledgedCollateral);
        assertEq(pool.borrowerDebt(),      state_.borrowerDebt);
        assertEq(poolActualUtilization,    state_.actualUtilization);
        assertEq(poolTargetUtilization,    state_.targetUtilization);
        assertEq(poolMinDebtAmount,        state_.minDebtAmount);

        assertEq(loansCount,  state_.loans);
        assertEq(maxBorrower, state_.maxBorrower);

        assertEq(pool.encumberedCollateral(state_.borrowerDebt, state_.lup), state_.encumberedCollateral);
    }

    function _assertReserveAuction(ReserveAuctionState memory state_) internal {
        ERC721Pool pool = address(_collectionPool) == address(0) ? _subsetPool : _collectionPool;

        ( , , uint256 claimableReservesRemaining, uint256 auctionPrice, uint256 timeRemaining) = pool.poolReservesInfo();
        assertEq(claimableReservesRemaining, state_.claimableReservesRemaining);
        assertEq(auctionPrice, state_.auctionPrice);
        assertEq(timeRemaining, state_.timeRemaining);
    }

    function _assertReserveAuctionPrice(uint256 expectedPrice) internal {
        ERC721Pool pool = address(_collectionPool) == address(0) ? _subsetPool : _collectionPool;
        ( , , , uint256 auctionPrice, ) = pool.poolReservesInfo();
        assertEq(auctionPrice, expectedPrice);
    }

    function _indexToPrice(uint256 index_) internal view returns (uint256 price_) {
        ERC721Pool pool = address(_collectionPool) == address(0) ? _subsetPool : _collectionPool;
        ( price_, , , , , , ) = pool.bucketAt(index_);
    }

    function _htp() internal view returns (uint256 htp_) {
        (, htp_, , ) = _subsetPool.poolPricesInfo();
    }

    function _exchangeRate(uint256 index_) internal view returns (uint256 exchangeRate_) {
        ( , , , , , exchangeRate_, ) = _subsetPool.bucketAt(index_);
    }

    function _lup() internal view returns (uint256 lup_) {
        (, , lup_, ) = _subsetPool.poolPricesInfo();
    }

    function _poolSize() internal view returns (uint256 poolSize_) {
        (poolSize_, , , ) = _subsetPool.poolLoansInfo();
    }

    function _poolTargetUtilization() internal view returns (uint256 utilization_) {
        ( , , , utilization_) = _subsetPool.poolUtilizationInfo();
    }

    function _poolActualUtilization() internal view returns (uint256 utilization_) {
        ( , , utilization_, ) = _subsetPool.poolUtilizationInfo();
    }

    function _poolMinDebtAmount() internal view returns (uint256 minDebt_) {
        ( minDebt_, , , ) = _subsetPool.poolUtilizationInfo();
    }

    function _loansCount() internal view returns (uint256 loansCount_) {
        ( , loansCount_, , ) = _subsetPool.poolLoansInfo();
    }

    function _maxBorrower() internal view returns (address maxBorrower_) {
        ( , , maxBorrower_, ) = _subsetPool.poolLoansInfo();
    }
}
