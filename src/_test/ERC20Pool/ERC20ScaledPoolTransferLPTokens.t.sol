// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                  from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";
import { UserWithQuoteToken }          from "../utils/Users.sol";

contract ERC20ScaledPoolTransferLPTokensTest is DSTestPlus {

    address            internal _poolAddress;
    ERC20Pool          internal _pool;
    CollateralToken    internal _collateral;
    QuoteToken         internal _quote;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender1;
    UserWithQuoteToken internal _lender2;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);

        _lender  = new UserWithQuoteToken();
        _lender1 = new UserWithQuoteToken();
        _lender2 = new UserWithQuoteToken();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender1), 200_000 * 1e18);
        _quote.mint(address(_lender2), 200_000 * 1e18);

        _lender.approveToken(_quote,  address(_pool), 200_000 * 1e18);
        _lender1.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _lender2.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**********************************/
    /*** Approve new position Tests ***/
    /**********************************/

    function testApproveNewPositionOwner() external {
        // default 0x address if no new position owner approved
        assertEq(_pool.lpTokenOwnership(address(_lender)), address(0));

        _lender.approveNewPositionOwner(_pool, address(_lender1));
        assertEq(_pool.lpTokenOwnership(address(_lender)), address(_lender1));
    }

    /********************************/
    /*** Transfer LP Tokens Tests ***/
    /********************************/

    function testTransferLPTokensToZeroAddress() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is not set
        vm.expectRevert("S:TLT:NOT_OWNER");
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);

        // should fail if allowed owner is set to 0x
        _lender1.approveNewPositionOwner(_pool, address(0));
        vm.expectRevert("S:TLT:NOT_OWNER");
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);
    }

    function testTransferLPTokensToUnallowedAddress() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is set to lender2 address but trying to transfer to lender address
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        vm.expectRevert("S:TLT:NOT_OWNER");
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender), indexes);
    }

    function testTransferLPTokensToInvalidIndex() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 9999;
        indexes[2] = 2552;

        // should fail since 9999 is not a valid index
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        vm.expectRevert("S:TLT:INVALID_INDEX");
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);
    }

    function testTransferLPTokensWithEmptyIndexes() external {
        uint256[] memory indexes = new uint256[](0);

        // set allowed owner to lender2 address
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), indexes, 0);
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);

        // check that old token ownership was removed
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(0));
    }

    function testTransferLPTokensForAllIndexes() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        uint256[] memory prices = new uint256[](3);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;

        _lender1.addQuoteToken(_pool, 10_000 * 1e18, indexes[0]);
        _lender1.addQuoteToken(_pool, 20_000 * 1e18, indexes[1]);
        _lender1.addQuoteToken(_pool, 30_000 * 1e18, indexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 0);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 0);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 0);

        // set allowed owner to lender2 address
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for all indexes
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 60_000 * 1e27);
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);

        // check that old token ownership was removed
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(0));

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 0);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 0);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 0);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 30_000 * 1e27);
    }

    function testTransferLPTokensForTwoIndexes() external {
        uint256[] memory depositIndexes = new uint256[](3);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;

        uint256[] memory transferIndexes = new uint256[](2);
        transferIndexes[0] = 2550;
        transferIndexes[1] = 2552;

        uint256[] memory prices = new uint256[](2);
        prices[0] = _p3010;
        prices[1] = _p2981;

        _lender1.addQuoteToken(_pool, 10_000 * 1e18, depositIndexes[0]);
        _lender1.addQuoteToken(_pool, 20_000 * 1e18, depositIndexes[1]);
        _lender1.addQuoteToken(_pool, 30_000 * 1e18, depositIndexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender2)), 0);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender2)), 0);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender2)), 0);

        // set allowed owner to lender2 address
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for 2 indexes
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 40_000 * 1e27);
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), transferIndexes);

        // check that old token ownership was removed
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(0));

        // check lenders lp balance
        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender1)), 0);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender1)), 0);

        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender2)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender2)), 0);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender2)), 30_000 * 1e27);
    }

    function testTransferLPTokensToLenderWithLPTokens() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        uint256[] memory prices = new uint256[](3);
        prices[0] = _p3010;
        prices[1] = _p2995;
        prices[2] = _p2981;

        _lender1.addQuoteToken(_pool, 10_000 * 1e18, indexes[0]);
        _lender1.addQuoteToken(_pool, 20_000 * 1e18, indexes[1]);
        _lender1.addQuoteToken(_pool, 30_000 * 1e18, indexes[2]);

        _lender2.addQuoteToken(_pool, 5_000 * 1e18, indexes[0]);
        _lender2.addQuoteToken(_pool, 10_000 * 1e18, indexes[1]);
        _lender2.addQuoteToken(_pool, 15_000 * 1e18, indexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 5_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 15_000 * 1e27);

        // set allowed owner to lender2 address
        _lender1.approveNewPositionOwner(_pool, address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for all indexes
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 60_000 * 1e27);
        _lender.transferLPTokens(_pool, address(_lender1), address(_lender2), indexes);

        // check that old token ownership was removed
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(0));

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 0);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 0);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 0);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 15_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 30_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 45_000 * 1e27);
    }

}
