// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc721/ERC721Pool.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';

contract ERC721PoolFlashloanTest is ERC721HelperContract {
    address internal _borrower;
    address internal _lender;
    uint16  internal _bucketId;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 5_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower, 1);

        // lender adds liquidity and borrower draws debt
        _bucketId = PoolUtils.priceToIndex(0.50 * 1e18);
        assertEq(_bucketId, 4444);
        _addLiquidity(
            {
                from:   _lender,
                amount: 2 * 1e18,
                index:  _bucketId,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // borrower draws debt
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     0.25 * 1e18,
                indexLimit: _bucketId,
                newLup:     _bucketId
            }
        );
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, 0.2555 * 1e18);
    }

    // TODO: write tests
}
