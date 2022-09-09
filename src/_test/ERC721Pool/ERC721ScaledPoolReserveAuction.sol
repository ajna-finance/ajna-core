// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }           from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory }    from "../../erc721/ERC721PoolFactory.sol";
import { IERC721Pool }          from "../../erc721/interfaces/IERC721Pool.sol";
import { IScaledPool }          from "../../base/interfaces/IScaledPool.sol";

import { BucketMath }           from "../../libraries/BucketMath.sol";
import { Maths }                from "../../libraries/Maths.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

contract ERC721ScaledReserveAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _bidder;
    address internal _lender;

    function setUp() external {
        // TODO: consider moving this into helper contract deployPool methods
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        _borrower  = makeAddr("borrower");
        _bidder    = makeAddr("bidder");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _collectionPool = _deployCollectionPool();
        address[] memory poolAddresses_ = new address[](1);
        poolAddresses_[0] = address(_collectionPool);
        _mintAndApproveQuoteTokens(poolAddresses_, _lender, 250_000 * 1e18);
        _mintAndApproveQuoteTokens(poolAddresses_, _borrower, 5_000 * 1e18);
        _mintAndApproveCollateralTokens(poolAddresses_, _borrower, 12);

        // lender adds liquidity and borrower draws debt
        changePrank(_lender);
        uint16 bucketId = 1663;
        uint256 bucketPrice = _collectionPool.indexToPrice(bucketId);
        assertEq(bucketPrice, 251_183.992399245533703810 * 1e18);
        _collectionPool.addQuoteToken(200_000 * 1e18, bucketId);

        // borrower draws debt
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _collectionPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _collectionPool.borrow(175_000 * 1e18, bucketId);

        _assertPool(
            PoolState({
                htp:                  175_168.269230769230850000 * 1e18,
                lup:                  bucketPrice,
                poolSize:             200_000 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 0.697370352137516918 * 1e18,
                borrowerDebt:         175_168.269230769230850000 * 1e18,
                actualUtilization:    0.875841346153846154 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        17_516.826923076923085000 * 1e18,
                loans:                1,
                maxBorrower:          _borrower
            })
        );
        skip(26 weeks);

        // borrower repays debt
        _collectionPool.repay(_borrower, 205_000 * 1e18);
        assertEq(_collectionPool.reserves(), 610.479702351371553626 * 1e18);
    }

    function testClaimableReserveAuction() external {
        _assertReserveAuction(
            ReserveAuctionState({
                claimableReservesRemaining: 0,
                auctionPrice:               0
            })
        );
//        _collectionPool.startClaimableReserveAuction();
    }

}