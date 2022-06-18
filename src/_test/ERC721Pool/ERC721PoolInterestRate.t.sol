// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolInterestRateTriggerTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower2;
    UserWithNFTCollateral       internal _borrower;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _lender     = new UserWithQuoteTokenInNFTPool();
        _borrower2  = new UserWithNFTCollateral();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_borrower2), 5);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployNFTCollectionPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](5);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 10;
        _tokenIds[3] = 50;
        _tokenIds[4] = 61;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIds, 0.05 * 10**18);
        _NFTSubsetPool        = ERC721Pool(_NFTSubsetPoolAddress);

        // run token approvals for NFT Collection Pool
        _lender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTCollectionPoolAddress, 1);

        // run token approvals for NFT Subset Pool
        _lender.approveToken(_quote, _NFTSubsetPoolAddress, 200_000 * 1e18);

        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 10);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 50);

        _borrower2.approveToken(_collateral, _NFTSubsetPoolAddress, 61);

        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p3010);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p2503);

        skip(864000);

        vm.prank((address(_borrower)));
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 1;
        _NFTSubsetPool.addCollateral(_tokenIds);
        vm.prank((address(_borrower)));
        _tokenIds = new uint256[](1);
        _tokenIds[0] = 5;
        _NFTSubsetPool.addCollateral(_tokenIds);
        _borrower.borrow(_NFTSubsetPool, 6_000 * 1e18, _p2503);
    }

    /**
     *  @notice Test interest rate updates on add collateral action.
     */
    function testUpdateInterestRateOnAddCollateral() external {
    }

    /**
     *  @notice Test interest rate updates on borrow action.
     */
    function testUpdateInterestRateOnBorrow() external {
    }

    /**
     *  @notice Test interest rate updates on remove collateral action.
     */
    function testUpdateInterestRateOnRemoveCollateral() external {
    }

    /**
     *  @notice Test interest rate updates on repay action.
     */
    function testUpdateInterestRateOnRepay() external {
    }

    /**
     *  @notice Test interest rate updates on add quote token action.
     */
    function testUpdateInterestRateOnAddQuoteToken() external {
    }

    /**
     *  @notice Test interest rate updates on move quote token action.
     */
    function testUpdateInterestRateOnMoveQuoteToken() external {
    }

    /**
     *  @notice Test interest rate updates on remove quote token action.
     */
    function testUpdateInterestRateOnRemoveQuoteToken() external {
    }

    /**
     *  @notice Test interest rate updates on liquidate action.
     */
    function testUpdateInterestRateOnLiquidate() external {
    }

    /**
     *  @notice Test interest rate updates on purchase bid action.
     */
    function testUpdateInterestRateOnPurchaseBid() external {
    }

    /**
     *  @notice Test interest rate updates on claim collateral bid action.
     */
    function testUpdateInterestRateOnClaimCollateral() external {
    }
}
