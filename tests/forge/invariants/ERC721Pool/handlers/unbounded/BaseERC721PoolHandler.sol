// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC721Pool } from 'src/ERC721Pool.sol';

import { NFTCollateralToken } from '../../../../utils/Tokens.sol';

import { BaseHandler } from '../../../base/handlers/unbounded/BaseHandler.sol';

abstract contract BaseERC721PoolHandler is BaseHandler {

    using EnumerableSet for EnumerableSet.UintSet;

    // Token
    NFTCollateralToken internal _collateral;

    // ERC721Pool
    ERC721Pool internal _erc721Pool;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) BaseHandler(pool_, ajna_, poolInfo_, testContract_) {

        LENDER_MIN_BUCKET_INDEX = vm.envOr("BUCKET_INDEX_ERC721", uint256(850));
        LENDER_MAX_BUCKET_INDEX = LENDER_MIN_BUCKET_INDEX + vm.envOr("NO_OF_BUCKETS", uint256(3)) - 1;

        MIN_QUOTE_AMOUNT = vm.envOr("MIN_QUOTE_AMOUNT_ERC721", uint256(1e3));
        /* 
            Lower the bucket price, higher number of NFT mints and transfers.
            So this formulae is used to avoid out of gas error and also run the invariants in a reasonable time

            BUCKET_INDEX        MAX_QUOTE_AMOUNT
            1                   1e31
            500                 1e30
            1500                1e26
            2500                1e22
            3500                1e18
            4500                1e14
            5500                1e10
            6500                1e6
            7368                1e3                
        */
        MAX_QUOTE_AMOUNT = vm.envOr("MAX_QUOTE_AMOUNT_ERC721", uint256(10 ** (31 - (LENDER_MIN_BUCKET_INDEX / 260))));

        MIN_DEBT_AMOUNT = vm.envOr("MIN_DEBT_AMOUNT", uint256(0));
        MAX_DEBT_AMOUNT = vm.envOr("MAX_DEBT_AMOUNT", uint256(1e28));

        MIN_COLLATERAL_AMOUNT = vm.envOr("MIN_COLLATERAL_AMOUNT_ERC721", uint256(1));
        MAX_COLLATERAL_AMOUNT = vm.envOr("MAX_COLLATERAL_AMOUNT_ERC721", uint256(100));

        for (uint256 bucket = LENDER_MIN_BUCKET_INDEX; bucket <= LENDER_MAX_BUCKET_INDEX; bucket++) {
            buckets.add(bucket);
        }

        // ERC721Pool
        _erc721Pool = ERC721Pool(pool_);

        // Tokens
        _collateral = NFTCollateralToken(_erc721Pool.collateralAddress());

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

            _ensureQuoteAmount(actor, 1e45);

            vm.stopPrank();
        }

        return actorsAddress;
    }

    function _repayBorrowerDebt(
        address borrower_,
        uint256 amount_
    ) updateLocalStateAndPoolInterest internal override {

        (
            uint256 kickTimeBefore,
            uint256 borrowerCollateralBefore, , ,
            uint256 auctionPrice,
        ) = _poolInfo.auctionStatus(address(_erc721Pool), borrower_);

        try _erc721Pool.repayDebt(borrower_, amount_, 0, borrower_, 7388) {

            _recordSettleBucket(
                borrower_,
                borrowerCollateralBefore,
                kickTimeBefore,
                auctionPrice
            );

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

}