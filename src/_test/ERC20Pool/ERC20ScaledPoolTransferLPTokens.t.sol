// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { DSTestPlus }                  from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC20ScaledPoolTransferLPTokensTest is DSTestPlus {

    address internal _lender;
    address internal _lender1;
    address internal _lender2;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _lender  = makeAddr("lender");
        _lender1 = makeAddr("lender1");
        _lender2 = makeAddr("lender2");

        deal(address(_quote), _lender,  200_000 * 1e18);
        deal(address(_quote), _lender1, 200_000 * 1e18);
        deal(address(_quote), _lender2, 200_000 * 1e18);

        vm.startPrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);
        changePrank(_lender1);
        _quote.approve(address(_pool), 200_000 * 1e18);
        changePrank(_lender2);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    /**********************************/
    /*** Approve new position Tests ***/
    /**********************************/

    function testApproveNewPositionOwner() external {
        // default 0x address if no new position owner approved
        assertEq(_pool.lpTokenOwnership(address(_lender)), address(0));

        changePrank(_lender);
        _pool.approveNewPositionOwner(address(_lender1));
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
        changePrank(_lender);
        vm.expectRevert("S:TLT:NOT_OWNER");
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);

        // should fail if allowed owner is set to 0x
        changePrank(_lender1);
        _pool.approveNewPositionOwner(address(0));

        changePrank(_lender);
        vm.expectRevert("S:TLT:NOT_OWNER");
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);
    }

    function testTransferLPTokensToUnallowedAddress() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is set to lender2 address but trying to transfer to lender address
        changePrank(_lender1);
        _pool.approveNewPositionOwner(address(_lender2));

        changePrank(_lender);
        vm.expectRevert("S:TLT:NOT_OWNER");
        _pool.transferLPTokens(address(_lender1), address(_lender), indexes);
    }

    function testTransferLPTokensToInvalidIndex() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 9999;
        indexes[2] = 2552;

        // should fail since 9999 is not a valid index
        changePrank(_lender1);
        _pool.approveNewPositionOwner(address(_lender2));

        changePrank(_lender);
        vm.expectRevert("S:TLT:INVALID_INDEX");
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);
    }

    function testTransferLPTokensWithEmptyIndexes() external {
        uint256[] memory indexes = new uint256[](0);

        // set allowed owner to lender2 address
        changePrank(_lender1);
        _pool.approveNewPositionOwner(address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), indexes, 0);
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);

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

        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, indexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 0);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 0);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 0);

        // set allowed owner to lender2 address
        _pool.approveNewPositionOwner(address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for all indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 60_000 * 1e27);
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);

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

        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, depositIndexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, depositIndexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(depositIndexes[0], address(_lender2)), 0);
        assertEq(_pool.lpBalance(depositIndexes[1], address(_lender2)), 0);
        assertEq(_pool.lpBalance(depositIndexes[2], address(_lender2)), 0);

        // set allowed owner to lender2 address
        _pool.approveNewPositionOwner(address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for 2 indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 40_000 * 1e27);
        _pool.transferLPTokens(address(_lender1), address(_lender2), transferIndexes);

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

        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, indexes[2]);

        changePrank(_lender2);
        _pool.addQuoteToken(5_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(10_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(15_000 * 1e18, indexes[2]);

        // check lenders lp balance
        assertEq(_pool.lpBalance(indexes[0], address(_lender1)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender1)), 20_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender1)), 30_000 * 1e27);

        assertEq(_pool.lpBalance(indexes[0], address(_lender2)), 5_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[1], address(_lender2)), 10_000 * 1e27);
        assertEq(_pool.lpBalance(indexes[2], address(_lender2)), 15_000 * 1e27);

        // set allowed owner to lender2 address
        changePrank(_lender1);
        _pool.approveNewPositionOwner(address(_lender2));
        assertEq(_pool.lpTokenOwnership(address(_lender1)), address(_lender2));

        // transfer LP tokens for all indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(address(_lender1), address(_lender2), prices, 60_000 * 1e27);
        _pool.transferLPTokens(address(_lender1), address(_lender2), indexes);

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
