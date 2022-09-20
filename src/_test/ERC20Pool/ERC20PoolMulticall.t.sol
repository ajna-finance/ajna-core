// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20HelperContract } from "./ERC20DSTestPlus.sol";

contract ERC20PoolMulticallTest is ERC20HelperContract {

    address internal _lender;

    function setUp() external {
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
    }

    function testMulticallDepostQuoteToken() external {
        assertEq(_poolSize(), 0);

        bytes[] memory callsToExecute = new bytes[](3);

        callsToExecute[0] = abi.encodeWithSignature(
            "addQuoteToken(uint256,uint256)",
            10_000 * 1e18,
            2550
        );

        callsToExecute[1] = abi.encodeWithSignature(
            "addQuoteToken(uint256,uint256)",
            10_000 * 1e18,
            2551
        );

        callsToExecute[2] = abi.encodeWithSignature(
            "addQuoteToken(uint256,uint256)",
            10_000 * 1e18,
            2552
        );

        changePrank(_lender);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(_lender, 2550, 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(_lender, 2551, 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(_lender, 2552, 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);                
        _pool.multicall(callsToExecute);


        _assertPoolPrices(
            PoolPricesInfo({
                htp: 0,
                hpb: 3_010.892022197881557845 * 1e18,
                lup: BucketMath.MAX_PRICE,
                lupIndex: 0
            })
        );

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);
        assertEq(_poolSize(),                      30_000 * 1e18);

        // check buckets
        (uint256 lpBalance, ) = _pool.lenders(2550, _lender);
        assertEq(lpBalance,           10_000 * 1e27);
        assertEq(_exchangeRate(2550), 1 * 1e27);

        (lpBalance, ) = _pool.lenders(2551, _lender);
        assertEq(lpBalance,           10_000 * 1e27);
        assertEq(_exchangeRate(2551), 1 * 1e27);

        (lpBalance, ) = _pool.lenders(2552, _lender);
        assertEq(lpBalance,           10_000 * 1e27);
        assertEq(_exchangeRate(2552), 1 * 1e27);
    }

    function testMulticallRevertString() public {
        bytes[] memory callsToExecute = new bytes[](1);

        callsToExecute[0] = abi.encodeWithSignature(
            "borrow(uint256,uint256)",
            10_000 * 1e18,
            2550
        );

        changePrank(_lender);
        vm.expectRevert(IScaledPool.BorrowLimitIndexReached.selector);
        _pool.multicall(callsToExecute);
    }


}
