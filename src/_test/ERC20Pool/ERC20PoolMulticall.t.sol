// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";

import { ERC20DSTestPlus }             from "./ERC20DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

// TODO: implement ERC20HelperContract similar to ERC721HelperContract
contract ERC20PoolMulticallTest is ERC20DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        deal(address(_collateral), _borrower,  100 * 1e18);
        deal(address(_collateral), _borrower2, 100 * 1e18);

        deal(address(_quote), _lender,  200_000 * 1e18);
        deal(address(_quote), _lender2, 200_000 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 200 * 1e18);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_pool), 200_000 * 1e18);

        changePrank(_lender2);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    function testMulticallDepostQuoteToken() external {
        assertEq(_pool.poolSize(), 0);

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
        emit AddQuoteToken(_lender, _pool.indexToPrice(2550), 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(_lender, _pool.indexToPrice(2551), 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit AddQuoteToken(_lender, _pool.indexToPrice(2552), 10_000 * 1e18, BucketMath.MAX_PRICE);
        vm.expectEmit(true, true, false, true);
        emit Transfer(_lender, address(_pool), 10_000 * 1e18);                
        _pool.multicall(callsToExecute);

        assertEq(_pool.htp(), 0);
        assertEq(_pool.lup(), BucketMath.MAX_PRICE);
        assertEq(_pool.hpb(), _pool.indexToPrice(2550));

        // check balances
        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);
        assertEq(_pool.poolSize(),                 30_000 * 1e18);

        // check buckets
        (uint256 lpBalance, ) = _pool.bucketLenders(2550, _lender);
        assertEq(lpBalance,                10_000 * 1e27);
        assertEq(_pool.exchangeRate(2550), 1 * 1e27);

        (lpBalance, ) = _pool.bucketLenders(2551, _lender);
        assertEq(lpBalance,                10_000 * 1e27);
        assertEq(_pool.exchangeRate(2551), 1 * 1e27);

        (lpBalance, ) = _pool.bucketLenders(2552, _lender);
        assertEq(lpBalance,                10_000 * 1e27);
        assertEq(_pool.exchangeRate(2552), 1 * 1e27);
    }


}
