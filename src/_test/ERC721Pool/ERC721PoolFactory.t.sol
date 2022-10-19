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
        _assertDeployWith0xAddressRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(0),
                quote:        address(_quote),
                interestRate: 0.05 * 10**18
            }
        );

        // should revert if trying to deploy with zero address as quote token
        _assertDeployWith0xAddressRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(_collateral),
                quote:        address(0),
                interestRate: 0.05 * 10**18
            }
        );
    }

    function testDeployERC721CollectionPoolWithInvalidRate() external {
        // should revert if trying to deploy with interest rate lower than accepted
        _assertDeployWithInvalidRateRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(_quote),
                quote:        address(_quote),
                interestRate: 10**18
            }
        );

        // should revert if trying to deploy with interest rate higher than accepted
        _assertDeployWithInvalidRateRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(_quote),
                quote:        address(_quote),
                interestRate: 2 * 10**18
            }
        );
    }

    function testDeployERC721PoolMultipleTimes() external {
        // should revert if trying to deploy same pool one more time
        _assertDeployMultipleTimesRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(_collateral),
                quote:        address(_quote),
                interestRate: 0.05 * 10**18
            }
        );
    }

    function testDeployERC721CollectionPool() external {
        assertEq(address(_collateral), _NFTCollectionPool.collateralAddress());
        assertEq(address(_quote),      _NFTCollectionPool.quoteTokenAddress());

        assert(_NFTCollectionPoolAddress != _NFTSubsetOnePoolAddress);

        assertEq(_NFTCollectionPool.collateralAddress(),  address(_collateral));
        assertEq(_NFTCollectionPool.quoteTokenAddress(),  address(_quote));
        assertEq(_NFTCollectionPool.quoteTokenScale(),    1);
        assertEq(_NFTCollectionPool.interestRate(),       0.05 * 10**18);
        assertEq(_NFTCollectionPool.interestRateUpdate(), _startTime);
        assertEq(_NFTCollectionPool.minFee(),             0.0005 * 10**18);
        assertEq(_NFTCollectionPool.isSubset(),           false);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = _NFTCollectionPool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime);
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
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        _factory.deploySubsetPool(address(0), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        _factory.deploySubsetPool(address(_collateral), address(0), tokenIdsTestSubset, 0.05 * 10**18);
    }

    function testDeployERC721SubsetPoolWithInvalidRate() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.11 * 10**18);

        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.009 * 10**18);
    }

    function testDeployERC721SubsetPoolMultipleTimes() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        _factory.deploySubsetPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);
    }

    function testDeployERC721SubsetPool() external {
        assertEq(address(_collateral), _NFTCollectionPool.collateralAddress());
        assertEq(address(_quote),      _NFTCollectionPool.quoteTokenAddress());

        assertEq(_NFTSubsetOnePool.collateralAddress(), _NFTSubsetTwoPool.collateralAddress());
        assertEq(_NFTSubsetOnePool.quoteTokenAddress(), _NFTSubsetTwoPool.quoteTokenAddress());

        assertTrue(_NFTSubsetOnePoolAddress != _NFTSubsetTwoPoolAddress);

        assertEq(_NFTSubsetOnePool.collateralAddress(),  address(_collateral));
        assertEq(_NFTSubsetOnePool.quoteTokenAddress(),  address(_quote));
        assertEq(_NFTSubsetOnePool.quoteTokenScale(),    1);
        assertEq(_NFTSubsetOnePool.interestRate(),       0.05 * 10**18);
        assertEq(_NFTSubsetOnePool.interestRateUpdate(), _startTime);
        assertEq(_NFTSubsetOnePool.minFee(),             0.0005 * 10**18);
        assertEq(_NFTSubsetOnePool.isSubset(),           true);

        (uint256 poolInflatorSnapshot, uint256 lastInflatorUpdate) = _NFTSubsetOnePool.inflatorInfo();
        assertEq(poolInflatorSnapshot, 10**18);
        assertEq(lastInflatorUpdate,   _startTime);

        assertTrue(_NFTSubsetOnePool.tokenIdsAllowed(1));
        assertTrue(_NFTSubsetOnePool.tokenIdsAllowed(5));
        assertTrue(_NFTSubsetOnePool.tokenIdsAllowed(50));
        assertTrue(_NFTSubsetOnePool.tokenIdsAllowed(61));

        assertFalse(_NFTSubsetOnePool.tokenIdsAllowed(10));
    }

}
