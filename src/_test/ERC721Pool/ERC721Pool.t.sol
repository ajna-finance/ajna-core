// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC721Pool }        from "../../ERC721Pool.sol";
import { ERC721PoolFactory } from "../../ERC721PoolFactory.sol";

import { IPool } from "../../interfaces/IPool.sol";

import { DSTestPlus }                                from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC721PoolTest is DSTestPlus {

    address               internal _poolAddress;
    ERC721Pool            internal _pool;
    NFTCollateralToken    internal _collateral;
    QuoteToken            internal _quote;
    UserWithNFTCollateral internal _borrower;
    UserWithQuoteToken    internal _lender;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC721Pool(_poolAddress);

        _lender     = new UserWithQuoteToken();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 200);

        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 1);
    }

    // @notice:Tests pool factory inputs match the pool created
    function testDeploy() external {
        assertEq(address(_collateral), address(_pool.collateral()));
        assertEq(address(_quote),      address(_pool.quoteToken()));
    }

    function testEmptyBucket() external {
        (
            ,
            ,
            ,
            uint256 deposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = _pool.bucketAt(_p1004);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);

        (, , , deposit, debt, bucketInflator, lpOutstanding, bucketCollateral) = _pool.bucketAt(_p2793);

        assertEq(deposit,          0);
        assertEq(debt,             0);
        assertEq(bucketInflator,   0);
        assertEq(lpOutstanding,    0);
        assertEq(bucketCollateral, 0);
    }

}
