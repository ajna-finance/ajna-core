// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract }      from './ERC721DSTestPlus.sol';
import { NFTCollateralToken, Token } from '../utils/Tokens.sol';

import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { IPoolErrors }       from 'src/interfaces/pool/commons/IPoolErrors.sol';
import { IPoolFactory }      from 'src/interfaces/pool/IPoolFactory.sol';

contract ERC721PoolFactoryTest is ERC721HelperContract {
    address            internal _NFTCollectionPoolAddress;
    address            internal _NFTSubsetOnePoolAddress;
    address            internal _NFTSubsetTwoPoolAddress;
    ERC721Pool         internal _NFTCollectionPool;
    ERC721Pool         internal _NFTSubsetOnePool;
    ERC721Pool         internal _NFTSubsetTwoPool;
    ERC721PoolFactory  internal _factory;
    uint256[]          internal _tokenIdsSubsetOne;
    uint256[]          internal _tokenIdsSubsetTwo;

    function setUp() external {
        _startTime   = block.timestamp;
        _collateral  = new NFTCollateralToken();
        _quote       = new Token("Quote", "Q");

        // deploy factory
        _factory = new ERC721PoolFactory(_ajna);

        // deploy NFT collection pool
        uint256[] memory tokenIds;
        _NFTCollectionPoolAddress = _factory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18);
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        // deploy NFT subset one pool
        _tokenIdsSubsetOne = new uint256[](4);
        _tokenIdsSubsetOne[0] = 1;
        _tokenIdsSubsetOne[1] = 5;
        _tokenIdsSubsetOne[2] = 50;
        _tokenIdsSubsetOne[3] = 61;

        _NFTSubsetOnePoolAddress = _factory.deployPool(address(_collateral), address(_quote), _tokenIdsSubsetOne, 0.05 * 10**18);
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

        _NFTSubsetTwoPoolAddress = _factory.deployPool(address(_collateral), address(_quote), _tokenIdsSubsetTwo, 0.05 * 10**18);
        _NFTSubsetTwoPool        = ERC721Pool(_NFTSubsetTwoPoolAddress);

        assertEq(_factory.getDeployedPoolsList().length,  3);
        assertEq(_factory.getNumberOfDeployedPools(),     3);
    }

    function testInstantiateERC721FactoryWithZeroAddress() external {
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        new ERC721PoolFactory(address(0));
    }

    /***************************/
    /*** ERC721 Common Tests ***/
    /***************************/

    function testGetNFTSubsetHash() external {
        assertTrue(_factory.getNFTSubsetHash(_tokenIdsSubsetOne) != _factory.getNFTSubsetHash(_tokenIdsSubsetTwo));
    }

    function testPoolAlreadyInitialized() external {
        // check can't call reiinitalize with a different token subset
        _tokenIdsSubsetOne = new uint256[](2);
        _tokenIdsSubsetOne[0] = 2;
        _tokenIdsSubsetOne[1] = 3;

        vm.expectRevert(IPoolErrors.AlreadyInitialized.selector);
        _NFTSubsetOnePool.initialize(_tokenIdsSubsetOne, 0.05 * 10**18);
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
        
        // check tracking of deployed pools
        assertEq(_factory.getDeployedPoolsList().length,  3);
        assertEq(_factory.getNumberOfDeployedPools(), 3);
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

        // check tracking of deployed pools
        assertEq(_factory.getDeployedPoolsList().length,  3);
        assertEq(_factory.getNumberOfDeployedPools(), 3);
    }

    function testDeployERC721CollectionPoolWithNonNFTAddress() external {
        // should revert if trying to deploy with non NFT
        _assertDeployWithNonNFTRevert(
            {
                poolFactory:  address(_factory),
                collateral:   address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                quote:        address(_quote),
                interestRate: 0.05 * 10**18
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

        assertEq(_NFTCollectionPool.poolType(),           1);
        assertEq(_NFTCollectionPool.collateralAddress(),  address(_collateral));
        assertEq(_NFTCollectionPool.quoteTokenAddress(),  address(_quote));
        assertEq(_NFTCollectionPool.quoteTokenScale(),    1);
        assertEq(_NFTCollectionPool.isSubset(),           false);

        (uint256 interestRate, uint256 interestRateUpdate) = _NFTCollectionPool.interestRateInfo();
        assertEq(interestRate,       0.05 * 10**18);
        assertEq(interestRateUpdate, _startTime);

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
        _factory.deployPool(address(0), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        // should revert if trying to deploy with zero address as quote token
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        _factory.deployPool(address(_collateral), address(0), tokenIdsTestSubset, 0.05 * 10**18);

        // check tracking of deployed pools
        assertEq(_factory.getDeployedPoolsList().length, 3);
    }

    function testDeployERC721SubsetPoolWithInvalidRate() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        _factory.deployPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.11 * 10**18);

        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        _factory.deployPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.009 * 10**18);

        // check tracking of deployed pools
        assertEq(_factory.getDeployedPoolsList().length,  3);
        assertEq(_factory.getNumberOfDeployedPools(), 3);
    }

    function testDeployERC721SubsetPoolMultipleTimes() external {
        uint256[] memory tokenIdsTestSubset = new uint256[](3);
        tokenIdsTestSubset[0] = 1;
        tokenIdsTestSubset[1] = 2;
        tokenIdsTestSubset[2] = 3;

        address poolAddress = _factory.deployPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        // check tracking of deployed pools
        assertEq(_factory.getDeployedPoolsList().length,  4);
        assertEq(_factory.getNumberOfDeployedPools(), 4);
        assertEq(_factory.getDeployedPoolsList()[3],     poolAddress);
        assertEq(_factory.deployedPoolsList(3),          poolAddress);

        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        _factory.deployPool(address(_collateral), address(_quote), tokenIdsTestSubset, 0.05 * 10**18);

        assertEq(_factory.getDeployedPoolsList().length,  4);
        assertEq(_factory.getNumberOfDeployedPools(), 4);
    }

    function testDeployERC721SubsetPool() external {
        assertEq(address(_collateral), _NFTCollectionPool.collateralAddress());
        assertEq(address(_quote),      _NFTCollectionPool.quoteTokenAddress());

        assertEq(_NFTSubsetOnePool.collateralAddress(), _NFTSubsetTwoPool.collateralAddress());
        assertEq(_NFTSubsetOnePool.quoteTokenAddress(), _NFTSubsetTwoPool.quoteTokenAddress());

        assertTrue(_NFTSubsetOnePoolAddress != _NFTSubsetTwoPoolAddress);

        assertEq(_NFTCollectionPool.poolType(),          1);
        assertEq(_NFTSubsetOnePool.collateralAddress(),  address(_collateral));
        assertEq(_NFTSubsetOnePool.quoteTokenAddress(),  address(_quote));
        assertEq(_NFTSubsetOnePool.quoteTokenScale(),    1);
        assertEq(_NFTSubsetOnePool.isSubset(),           true);

        (uint256 interestRate, uint256 interestRateUpdate) = _NFTCollectionPool.interestRateInfo();
        assertEq(interestRate,       0.05 * 10**18);
        assertEq(interestRateUpdate, _startTime);

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
