// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@std/console.sol";

import { Pool }              from 'src/base/Pool.sol';
import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';

import { PositionsInvariants }         from './PositionsInvariants.sol';

import { NFTCollateralToken } from '../../utils/Tokens.sol';
import { TokenWithNDecimals } from '../../utils/Tokens.sol';

import { MultiplePoolPositionHandler } from "./handlers/MultiplePoolPositionHandler.sol";
import { MultiplePoolHandler } from "./handlers/MultiplePoolHandler.sol";

contract MultiplePoolPositionsInvariants is PositionsInvariants {

    TokenWithNDecimals          internal _collateral;
    MultiplePoolPositionHandler internal _multiplePoolPositionHandler;

    // randomness counter used in randomSeed()
    uint256 internal counter = 1;

    // TODO: paramterize the number of pools to create via environment variables
    function setUp() public override virtual {
        super.setUp();

        // deploy factories
        _erc20poolFactory  = new ERC20PoolFactory(address(_ajna));
        _erc20impl         = _erc20poolFactory.implementation();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _erc721impl        = _erc721poolFactory.implementation();

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc20poolFactory));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_poolInfo));
        excludeContract(address(_erc20impl));
        excludeContract(address(_erc721impl));
        excludeContract(address(_positionManager));

        // create pools
        MultiplePoolHandler.PoolInfo[] memory pools = createRandomPools(5);

        // instantiate handler
        _handler = address(new MultiplePoolPositionHandler(
            address(_positionManager),
            pools,
            address(_ajna),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        ));
    }

    function createRandomPools(uint256 numPools_) internal returns (MultiplePoolHandler.PoolInfo[] memory pools_) {
        pools_ = new MultiplePoolHandler.PoolInfo[](numPools_);
        for (uint256 i = 0; i < numPools_; i++) {
            // flip a coin to create ERC721 pool
            if (_randomSeed() % 2 == 0) {
                pools_[i] = _createERC721Pool();
            } else {
                pools_[i] = _createERC20Pool();
            }
        }
    }

    function _createERC20Pool() internal returns (MultiplePoolHandler.PoolInfo memory) {
        address collateral = address(new TokenWithNDecimals("Collateral", "C", uint8(vm.envOr("COLLATERAL_PRECISION", uint256(18)))));
        address quote      = address(new TokenWithNDecimals("Quote", "Q", uint8(vm.envOr("QUOTE_PRECISION", uint256(18)))));
        address pool       = _erc20poolFactory.deployPool(address(collateral), address(quote), 0.05 * 10**18);

        // exclude newly deployed contracts
        excludeContract(collateral);
        excludeContract(quote);
        excludeContract(pool);

        return MultiplePoolHandler.PoolInfo({
            pool: pool,
            collateral: collateral,
            quote: quote,
            is721: false,
            numActors: NUM_ACTORS
        });
    }

    function _createERC721Pool() internal returns (MultiplePoolHandler.PoolInfo memory) {
        address collateral = address(new NFTCollateralToken());
        address quote      = address(new TokenWithNDecimals("Quote", "Q", uint8(vm.envOr("QUOTE_PRECISION", uint256(18)))));
        address pool       = _erc721poolFactory.deployPool(address(collateral), address(quote), 0.05 * 10**18);

        // exclude newly deployed contracts
        excludeContract(collateral);
        excludeContract(quote);
        excludeContract(pool);

        return MultiplePoolHandler.PoolInfo({
            pool: pool,
            collateral: collateral,
            quote: quote,
            is721: true,
            numActors: NUM_ACTORS
        });
    }

    function _randomSeed() internal returns (uint256) {
        counter++;
        return uint256(keccak256(abi.encodePacked(block.number, block.prevrandao, counter)));
    }

}
