// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/erc721/ERC721Pool.sol';

import 'src/libraries/BucketMath.sol';
import 'src/libraries/Maths.sol';

contract ERC721PoolFlashloanTest is ERC721HelperContract {
    address internal _borrower;
    address internal _lender;
    uint    internal _bucketId;
    uint    internal _bucketPrice;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");

        // deploy collection pool, mint, and approve tokens
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender,   250_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 5_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower, 1);

        // lender adds liquidity and borrower draws debt
        _bucketPrice = 0.499939458928274853 * 1e18;
        _bucketId = PoolUtils.priceToIndex(_bucketPrice);
        assertEq(_bucketId, 4295);
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
                newLup:     _bucketPrice
            }
        );
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(poolDebt, 0.250240384615384616 * 1e18);
    }

    function testQuoteTokenFlashloan() external tearDown {
    }
}
