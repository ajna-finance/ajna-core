// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { Pool }             from 'src/base/Pool.sol';
import { ERC721Pool }        from 'src/ERC721Pool.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { Maths }            from 'src/libraries/internal/Maths.sol';

import { NFTCollateralToken } from '../../utils/Tokens.sol';

import { BasicERC721PoolHandler } from './handlers/BasicERC721PoolHandler.sol';
import { BasicInvariants }       from '../base/BasicInvariants.t.sol';
import { IBaseHandler }          from '../interfaces/IBaseHandler.sol';

// contains invariants for the test
contract BasicERC721PoolInvariants is BasicInvariants {

    uint256               internal constant NUM_ACTORS = 10;

    NFTCollateralToken     internal _collateral;
    ERC721Pool             internal _erc721pool;
    ERC721Pool             internal _impl;
    ERC721PoolFactory      internal _erc721poolFactory;
    BasicERC721PoolHandler internal _basicERC721PoolHandler;

    function setUp() public override virtual{

        super.setUp();

        uint256[] memory tokenIds;
        _collateral        = new NFTCollateralToken();
        _erc721poolFactory = new ERC721PoolFactory(address(_ajna));
        _impl              = _erc721poolFactory.implementation();
        _erc721pool        = ERC721Pool(_erc721poolFactory.deployPool(address(_collateral), address(_quote), tokenIds, 0.05 * 10**18));
        _pool              = Pool(address(_erc721pool));

        _basicERC721PoolHandler = new BasicERC721PoolHandler(
            address(_erc721pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            NUM_ACTORS,
            address(this)
        );

        _handler = address(_basicERC721PoolHandler);

        excludeContract(address(_ajna));
        excludeContract(address(_collateral));
        excludeContract(address(_quote));
        excludeContract(address(_erc721poolFactory));
        excludeContract(address(_erc721pool));
        excludeContract(address(_poolInfo));
        excludeContract(address(_impl));

        LENDER_MIN_BUCKET_INDEX = IBaseHandler(_handler).LENDER_MIN_BUCKET_INDEX();
        LENDER_MAX_BUCKET_INDEX = IBaseHandler(_handler).LENDER_MAX_BUCKET_INDEX();

        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            ( , , , , ,uint256 exchangeRate) = _poolInfo.bucketInfo(address(_erc721pool), bucketIndex);
            previousBucketExchangeRate[bucketIndex] = exchangeRate;
        }

        (, previousInterestRateUpdate) = _erc721pool.interestRateInfo();

        // TODO: Change once this issue is resolved -> https://github.com/foundry-rs/foundry/issues/2963
        targetSender(address(0x1234));
    }

    function invariant_CT2() public useCurrentTimestamp {
        uint256 collateralBalance = _collateral.balanceOf(address(_erc721pool)) * 1e18;
        uint256 bucketCollateral;
        uint256 collateral;

        uint256[] memory collateralBuckets = IBaseHandler(_handler).getCollateralBuckets();
        for (uint256 i = 0; i < collateralBuckets.length; i++) {
            uint256 bucketIndex = collateralBuckets[i];
            (, collateral, , , ) = _erc721pool.bucketInfo(bucketIndex);
            bucketCollateral += collateral;
        }

        assertEq(collateralBalance, bucketCollateral + _erc721pool.pledgedCollateral(), "Collateral Invariant CT2");
    }

    function invariant_CT3() public useCurrentTimestamp {
        uint256 collateralBalance = _collateral.balanceOf(address(_erc721pool));

        uint256 actorCount = IBaseHandler(_handler).getActorsCount();
        uint256 borrowerTokens;

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);
            borrowerTokens   += _erc721pool.totalBorrowerTokens(borrower);
        }

        uint256 bucketTokens = _erc721pool.totalBucketTokens();
        assertEq(collateralBalance, borrowerTokens + bucketTokens, "Collateral Invariant CT3");
    }

    function invariant_CT4() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower       = IBaseHandler(_handler).actors(i);
            uint256 borrowerTokens = _erc721pool.totalBorrowerTokens(borrower);

            (, uint256 borrowerCollateral, ) = _erc721pool.borrowerInfo(borrower);

            assertGe(borrowerTokens * 1e18, borrowerCollateral, "Collateral Invariant CT4");
        }
    }

    function invariant_CT5() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        for (uint256 i = 0; i < actorCount; i++) {
            address borrower       = IBaseHandler(_handler).actors(i);
            uint256 borrowerTokens = _erc721pool.totalBorrowerTokens(borrower);

            for (uint256 tokenIndex = 0; tokenIndex < borrowerTokens; tokenIndex++) {
                uint256 borrowerTokenId = _erc721pool.borrowerTokenIds(borrower, tokenIndex);

                assertEq(_collateral.ownerOf(borrowerTokenId), address(_erc721pool), "Collateral Invariant CT5");
            }
        }

        uint256 bucketTokens = _erc721pool.totalBucketTokens();
        for (uint256 tokenIndex = 0; tokenIndex < bucketTokens; tokenIndex++) {
            uint256 bucketTokenId = _erc721pool.bucketTokenIds(tokenIndex);

            assertEq(_collateral.ownerOf(bucketTokenId), address(_erc721pool), "Collateral Invariant CT5");
        }
    }

    function invariant_CT6() public useCurrentTimestamp {
        if (_erc721pool.isSubset()) {
            uint256 actorCount = IBaseHandler(_handler).getActorsCount();
            for (uint256 i = 0; i < actorCount; i++) {
                address borrower       = IBaseHandler(_handler).actors(i);
                uint256 borrowerTokens = _erc721pool.totalBorrowerTokens(borrower);

                for (uint256 tokenIndex = 0; tokenIndex < borrowerTokens; tokenIndex++) {
                    uint256 borrowerTokenId = _erc721pool.borrowerTokenIds(borrower, tokenIndex);

                    assertTrue(_erc721pool.tokenIdsAllowed(borrowerTokenId), "Collateral Invariant CT6");
                }
            }

            uint256 bucketTokens = _erc721pool.totalBucketTokens();
            for (uint256 tokenIndex = 0; tokenIndex < bucketTokens; tokenIndex++) {
                uint256 bucketTokenId = _erc721pool.bucketTokenIds(tokenIndex);

                assertTrue(_erc721pool.tokenIdsAllowed(bucketTokenId), "Collateral Invariant CT6");
            }
        }    
    }

    function invariant_CT7() public useCurrentTimestamp {
        uint256 actorCount = IBaseHandler(_handler).getActorsCount();

        uint256 totalCollateralPledged;
        for (uint256 i = 0; i < actorCount; i++) {
            address borrower = IBaseHandler(_handler).actors(i);

            (, uint256 borrowerCollateral, ) = _erc721pool.borrowerInfo(borrower);

            totalCollateralPledged += borrowerCollateral;
        }

        assertEq(_erc721pool.pledgedCollateral(), totalCollateralPledged, "Collateral Invariant CT7");
    }

}
