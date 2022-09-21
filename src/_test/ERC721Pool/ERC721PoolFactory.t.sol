// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { DSTestPlus }                from '../utils/DSTestPlus.sol';
import { NFTCollateralToken, Token } from '../utils/Tokens.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../base/PoolDeployer.sol';

contract ERC721PoolFactoryTest is DSTestPlus {
    address            internal _NFTCollectionPoolAddress;
    address            internal _NFTSubsetOnePoolAddress;
    address            internal _NFTSubsetTwoPoolAddress;
    ERC721Pool         internal _NFTCollectionPool;
    ERC721Pool         internal _NFTSubsetOnePool;
    ERC721Pool         internal _NFTSubsetTwoPool;
    ERC721PoolFactory  internal _factory;
    NFTCollateralToken internal _collateral;
    Token              internal _quote;
    uint256[]          internal _tokenIdsSubsetOne;
    uint256[]          internal _tokenIdsSubsetTwo;
    uint256            internal _startTime;

    function setUp() external {
        _startTime   = block.timestamp;
        _collateral  = new NFTCollateralToken();
        _quote       = new Token("Quote", "Q");

        // deploy factory
        _factory = new ERC721PoolFactory();

        // deploy NFT collection pool
        _NFTCollectionPoolAddress = _factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        // deploy NFT subset one pool
        _tokenIdsSubsetOne = new uint256[](4);
        _tokenIdsSubsetOne[0] = 1;
        _tokenIdsSubsetOne[1] = 5;
        _tokenIdsSubsetOne[2] = 50;
        _tokenIdsSubsetOne[3] = 61;

        _NFTSubsetOnePoolAddress = _factory.deploySubsetPool(address(_collateral), address(_quote), _tokenIdsSubsetOne, 0.05 * 10**18);
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

        _NFTSubsetTwoPoolAddress = _factory.deploySubsetPool(address(_collateral), address(_quote), _tokenIdsSubsetTwo, 0.05 * 10**18);
        _NFTSubsetTwoPool        = ERC721Pool(_NFTSubsetTwoPoolAddress);
    }

    /***************************/
    /*** ERC721 Common Tests ***/
    /***************************/

    function testGetNFTSubsetHash() external {
        assertTrue(_factory.getNFTSubsetHash(_tokenIdsSubsetOne) != _factory.getNFTSubsetHash(_tokenIdsSubsetTwo));
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    function testDeployERC721CollectionPoolWithZeroAddress() external {
        // should revert if trying to deploy with zero address as collateral
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _factory.deployPool(address(0), address(_quote), 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _factory.deployPool(address(_collateral), address(0), 0.05 * 10**18);
    }

    function testDeployERC721CollectionPoolWithInvalidRate() external {
        // should revert if trying to deploy with interest rate lower than accepted
        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _factory.deployPool(address(_quote), address(_quote), 10**18);

        // should revert if trying to deploy with interest rate higher than accepted
        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _factory.deployPool(address(_quote), address(_quote), 2 * 10**18);
    }

    function testDeployERC721PoolMultipleTimes() external {
        // should revert if trying to deploy same pool one more time
        vm.expectRevert(PoolDeployer.PoolAlreadyExists.selector);
        _factory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
    }

    function testDeployERC721CollectionPool() external {
        assertEq(address(_collateral), address(_NFTCollectionPool.collateral()));
        assertEq(address(_quote),      address(_NFTCollectionPool.quoteToken()));

        assert(_NFTCollectionPoolAddress != _NFTSubsetOnePoolAddress);

        assertEq(address(_NFTCollectionPool.collateral()),        address(_collateral));
        assertEq(address(_NFTCollectionPool.quoteToken()),        address(_quote));
        assertEq(_NFTCollectionPool.quoteTokenScale(),            1);
        assertEq(_NFTCollectionPool.inflatorSnapshot(),           10**18);
        assertEq(_NFTCollectionPool.lastInflatorSnapshotUpdate(), _startTime + 0);
        assertEq(_NFTCollectionPool.lenderInterestFactor(),       0.9 * 10**18);
        assertEq(_NFTCollectionPool.interestRate(),               0.05 * 10**18);
        assertEq(_NFTCollectionPool.interestRateUpdate(),         0);
        assertEq(_NFTCollectionPool.minFee(),                     0.0005 * 10**18);
        assertEq(_NFTCollectionPool.isSubset(),                   false);
    }

    /**************************************/
    /*** ERC721 Collection Subset Tests ***/
    /**************************************/

    function testDeployERC721SubsetPoolWithZeroAddress() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        // should revert if trying to deploy with zero address as collateral
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _factory.deploySubsetPool(address(0), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert(PoolDeployer.DeployWithZeroAddress.selector);
        _factory.deploySubsetPool(address(_collateral), address(0), tokenIdsTestSubset, 0.05 * 10**18);
    }

    function testDeployERC721SubsetPoolWithInvalidRate() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.11 * 10**18);

        vm.expectRevert(PoolDeployer.PoolInterestRateInvalid.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.009 * 10**18);
    }

    function testDeployERC721SubsetPoolMultipleTimes() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        vm.expectRevert(PoolDeployer.PoolAlreadyExists.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);
    }

    function testDeployERC721SubsetPool() external {
        assertEq(address(_collateral), address(_NFTSubsetOnePool.collateral()));
        assertEq(address(_quote),      address(_NFTSubsetOnePool.quoteToken()));

        assertEq(address(_NFTSubsetOnePool.collateral()), address(_NFTSubsetTwoPool.collateral()));
        assertEq(address(_NFTSubsetOnePool.quoteToken()), address(_NFTSubsetTwoPool.quoteToken()));

        assertTrue(_NFTSubsetOnePoolAddress != _NFTSubsetTwoPoolAddress);

        assertEq(address(_NFTSubsetOnePool.collateral()),        address(_collateral));
        assertEq(address(_NFTSubsetOnePool.quoteToken()),        address(_quote));
        assertEq(_NFTSubsetOnePool.quoteTokenScale(),            1);
        assertEq(_NFTSubsetOnePool.inflatorSnapshot(),           10**18);
        assertEq(_NFTSubsetOnePool.lastInflatorSnapshotUpdate(), _startTime);
        assertEq(_NFTSubsetOnePool.lenderInterestFactor(),       0.9 * 10**18);
        assertEq(_NFTSubsetOnePool.interestRate(),               0.05 * 10**18);
        assertEq(_NFTSubsetOnePool.interestRateUpdate(),         0);
        assertEq(_NFTSubsetOnePool.minFee(),                     0.0005 * 10**18);
        assertEq(_NFTSubsetOnePool.isSubset(),                   true);

        assertTrue(_NFTSubsetOnePool.isTokenIdAllowed(1));
        assertTrue(_NFTSubsetOnePool.isTokenIdAllowed(5));
        assertTrue(_NFTSubsetOnePool.isTokenIdAllowed(50));
        assertTrue(_NFTSubsetOnePool.isTokenIdAllowed(61));

        assertFalse(_NFTSubsetOnePool.isTokenIdAllowed(10));
    }

}
