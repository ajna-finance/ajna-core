// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { ERC721Pool }        from 'src/ERC721Pool.sol';

import { NFTCollateralToken } from '../../../../utils/Tokens.sol';

import { BaseHandler } from '../../../base/handlers/unbounded/BaseHandler.sol';

abstract contract BaseERC721PoolHandler is BaseHandler {

    // Token
    NFTCollateralToken internal _collateral;

    // ERC721Pool
    ERC721Pool     internal _erc721Pool;

    constructor(
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, ajna_, quote_, poolInfo_, testContract_) {
        // Tokens
        _collateral = NFTCollateralToken(collateral_);

        // ERC721Pool
        _erc721Pool  = ERC721Pool(pool_);

        // Actors
        actors = _buildActors(numOfActors_);
    }

    /*****************************/
    /*** Pool Helper Functions ***/
    /*****************************/

    function _buildActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actorsAddress = new address[](noOfActors_);

        for (uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actorsAddress[i] = actor;

            vm.startPrank(actor);

            _quote.mint(actor, 1e45);
            _quote.approve(address(_pool), 1e45);

            _collateral.mint(actor, 100);
            _collateral.setApprovalForAll(address(_pool), true);

            vm.stopPrank();
        }

        return actorsAddress;
    }

}