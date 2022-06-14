// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";

contract ERC721PoolFactoryTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetOnePoolAddress;
    address                     internal _NFTSubsetTwoPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetOnePool;
    ERC721Pool                  internal _NFTSubsetTwoPool;
    ERC721PoolFactory           internal _factory;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    uint256[]                   internal _tokenIdsSubsetOne;
    uint256[]                   internal _tokenIdsSubsetTwo;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        // deploy factory
        _factory = new ERC721PoolFactory();

        // deploy NFT collection pool
        _NFTCollectionPoolAddress = _factory.deployNFTCollectionPool(address(_collateral), address(_quote));
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        // deploy NFT subset one pool
        _tokenIdsSubsetOne = new uint256[](4);
        _tokenIdsSubsetOne[0] = 1;
        _tokenIdsSubsetOne[1] = 5;
        _tokenIdsSubsetOne[2] = 50;
        _tokenIdsSubsetOne[3] = 61;

        _NFTSubsetOnePoolAddress = _factory.deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIdsSubsetOne);
        _NFTSubsetOnePool        = ERC721Pool(_NFTSubsetOnePoolAddress);

        // deploy NFT subset two pool
        _tokenIdsSubsetTwo = new uint256[](7);
        _tokenIdsSubsetTwo[0] = 1;
        _tokenIdsSubsetTwo[1] = 5;
        _tokenIdsSubsetTwo[2] = 12;
        _tokenIdsSubsetTwo[3] = 25;
        _tokenIdsSubsetTwo[4] = 50;
        _tokenIdsSubsetTwo[5] = 61;
        _tokenIdsSubsetTwo[6] = 180;

        _NFTSubsetTwoPoolAddress = _factory.deployNFTSubsetPool(address(_collateral), address(_quote), _tokenIdsSubsetTwo);
        _NFTSubsetTwoPool        = ERC721Pool(_NFTSubsetTwoPoolAddress);
    }

    function testGetNFTSubsetHash() external {
        assertTrue(_factory.getNFTSubsetHash(_tokenIdsSubsetOne) != _factory.getNFTSubsetHash(_tokenIdsSubsetTwo));
    }

    /**
     *  @notice Check that initialize can only be called once.
     */
    function testDeployNFTCollectionPool() external {
        assertEq(address(_collateral), address(_NFTCollectionPool.collateral()));
        assertEq(address(_quote),      address(_NFTCollectionPool.quoteToken()));

        assert(_NFTCollectionPoolAddress != _NFTSubsetOnePoolAddress);
    }

    function testDeployNFTSubsetPool() external {
        assertEq(address(_collateral), address(_NFTSubsetOnePool.collateral()));
        assertEq(address(_quote),      address(_NFTSubsetOnePool.quoteToken()));

        assertEq(address(_NFTSubsetOnePool.collateral()), address(_NFTSubsetTwoPool.collateral()));
        assertEq(address(_NFTSubsetOnePool.quoteToken()), address(_NFTSubsetTwoPool.quoteToken()));

        assertTrue(_NFTSubsetOnePoolAddress != _NFTSubsetTwoPoolAddress);
    }

    /**
     *  @notice Tests revert if actor attempts to deploy ETH pool.
     */
    function testDeployPoolEther() external {
        vm.expectRevert("PF:DP:ZERO_ADDR");
        _factory.deployNFTCollectionPool(address(_collateral), address(0));

        vm.expectRevert("PF:DP:ZERO_ADDR");
        _factory.deployNFTCollectionPool(address(0), address(_collateral));
    }

    /**
     *  @notice Tests revert if actor attempts to deploy the same pair with the same subset of NFT tokenIds.
     */
    function testDeploySubsetPoolTwice() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        _factory.deployNFTSubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset);
        vm.expectRevert("PF:DP:POOL_EXISTS");
        _factory.deployNFTSubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset);
    }

}
