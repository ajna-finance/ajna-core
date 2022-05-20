// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import { ERC20Pool }        from "../ERC20Pool.sol";
import { ERC20PoolFactory } from "../ERC20PoolFactory.sol";

import { IPool } from "../interfaces/IPool.sol";

import { Buckets } from "../base/Buckets.sol";

import { Maths } from "../libraries/Maths.sol";

import { DSTestPlus }                             from "./utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "./utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "./utils/Users.sol";

// TODO implement negative tests / reverts and bucket cleanup logic
contract ERC20PoolBorrowTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithQuoteToken internal _lender;
    UserWithQuoteToken internal _lender2;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote));
        _pool        = ERC20Pool(_poolAddress);  

        _borrower  = new UserWithCollateral();
        _borrower2 = new UserWithCollateral();
        _lender    = new UserWithQuoteToken();
        _lender2   = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_lender2), 200_000 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
        _lender2.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice Tests move quote token from a higher unutilized bucket to a lower unutilized bucket.
     */
    function testMoveUnutilizedToUnutilizedDown() external {

        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);

        // lender moves 10_000 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p2503, 10_000 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514, _p2503);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    0);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 0);

        (, , ,deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 40_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 40_000 * 1e27);

        assertEq(_pool.lup(), 0);
    }

    /**
     *  @notice Tests move quote token from a lower unutilized bucket to a higher unutilized bucket.
     */
    function testMoveUnutilizedToUnutilizedUp() external {

        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);

        // lender moves 10_000 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 10_000 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p2503, _p3514);
         
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , ,deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 20_000 * 1e27);

        assertEq(_pool.lup(), 0);
    }

    function testMoveUnutilizedToUnutilizedUpHpb() external {
        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);

        // borrower deposit 10 MKR collateral, borrows 15_000 DAI
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18);

        // lender moves 10_000 DAI up to new HUP
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p5007, 10_000 * 1e18, _p3514);
        _lender.moveQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p2503, _p5007);
         
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p5007);
        assertEq(debt,    10_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p5007), 10_000 * 1e27);

        assertEq(_pool.lup(), _p3514);
    }

    /**
     *  @notice Tests move quote token from a lower unutilized bucket to a higher unutilized bucket.
     *          from_bucket [unutilized] < to_bucket [utilized] - amount < lup.debt
     *          LUP stays
     */
    function testMoveLupStaysUnutilizedToUtilizedUp() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposit 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);

        // lender moves 100 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p502, _p3514, 100 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 100 * 1e18, _p502, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 49_900 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 49_900 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_100 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_100 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a lower unutilized bucket to a higher utilized bucket (LUP).
     *          Deposit should just move.
     */
    function testMoveToLupStaysUnutilizedToUtilizedUp() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);

        // lender moves 5_000 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p502, _p2503, 5_000 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p502, _p2503);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 45_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 45_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_000 * 1e18);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 25_000 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a higher unutilized bucket to a lower utilized bucket.
     *          LUP should move up.
     */
    function testMoveLupUpUnutilizedToUtilizedUp() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 5_000 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p502, _p3514, 5_000 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p502, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 45_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 45_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    15_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 15_000 * 1e27);

        assertEq(_pool.lup(), _p3010);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket to a lower unutilized bucket.
     *          from_bucket [utilized] > to_bucket [unutilized] - amount < lup.deposit
     *          LUP should remain the same.
     */
    function testMoveLupStaysUtilizedToUnutilizedDown() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 100 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p502, 100 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 100 * 1e18, _p3514, _p502);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 50_100 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 50_100 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_100 * 1e18);
        assertEq(deposit, 14_900 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_900 * 1e18);
        assertEq(deposit, 0 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_900 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket (LUP) to a lower unutilized bucket.
     *          from_bucket [utilized] (LUP) > to_bucket [unutilized] - from_bucket.deposit >= amount -> HUP moves
     */
    function testMoveFromLupStaysUtilizedToUnutilizedDown() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 15_000 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p502, 15_000 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 15_000 * 1e18, _p2503, _p502);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 65_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 65_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 5_000 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket (LUP) to a lower unutilized bucket.
     *          from_bucket [utilized] (LUP) > to_bucket [unutilized] - from_bucket.deposit < amount
     *          LUP should move down.
     */
    function testMoveFromLupMovesUtilizedToUnutilizedAllDepositPartialDebt() external {

        // lender deposits 52_500 DAI accross 5 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 500 * 1e18, _p2000);
        _lender.addQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 19_500 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p502, 19_500 * 1e18, _p502);
        _lender.moveQuoteToken(_pool, address(_lender), 19_500 * 1e18, _p2503, _p502);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 21_500 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 21_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2000);
        assertEq(debt,    500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2000), 500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 500 * 1e27);

        assertEq(_pool.lup(), _p502);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket to a lower unutilized bucket.
     *          LUP should move.
     */
    function testMoveLupMovesUtilizedToUntilized() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 8_000 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p502, 8_000 * 1e18, _p502);
        _lender.moveQuoteToken(_pool, address(_lender), 8_000 * 1e18, _p3514, _p502);

        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    4_000 * 1e18);
        assertEq(deposit, 54_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 58_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    20_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    2_000 * 1e18);
        assertEq(deposit, 0 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 2_000 * 1e27);

        assertEq(_pool.lup(), _p502);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket to a lower unutilized bucket.
     *          from_bucket [utilized] (LUP) < to_bucket [unutilized] (HPB) - from_bucket.debt < amount
     *          LUP should move up.
     */
    function testMoveFromLupMovesUtilizedToUntilizedPartialDepositAllDebt() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 5_000 DAI up to new HPB
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p9020, 5_000 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p2503, _p9020);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 15_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 15_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p9020);
        assertEq(debt,    5_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p9020), 5_000 * 1e27);

        assertEq(_pool.lup(), _p3010);
    }

    /**
     *  @notice Tests move quote token from a higher utilized bucket to a lower utilized bucket.
     *          from_bucket [utilized] > to_bucket [utilized] (LUP) - just move debt
     *          LUP should remain the same.
     */
    function testMoveToLupStaysUtilizedToUtilized() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 500 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p2503, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3514, _p2503);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    16_500 * 1e18);
        assertEq(deposit, 4_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_500 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a lower utilized bucket to a higher utilized bucket.
     *          from_bucket [utilized] (LUP) < to_bucket [utilized] - from_bucket.debt > amount
     */
    function testMoveFromLupStaysUtilizedToUtilizedPartialDebt() external {
        
        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 500 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p2503, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    15_500 * 1e18);
        assertEq(deposit, 4_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 19_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_500 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a higher bucket to a lower bucket.
     *          Debt should be reallocated.
     */
    function testMoveUtilizedToUtilizedDown() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 500 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p3010, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3514, _p3010);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    20_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_500 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }

    /**
     *  @notice Tests move quote token from a lower bucket to a higher bucket.
     *          Debt should be reallocated.
     */
    function testMoveUtilizedToUtilizedUp() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 500 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3010, _p3514, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3010, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    19_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 19_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_500 * 1e27);

        assertEq(_pool.lup(), _p2503);
    }   

    /**
     *  @notice Tests move quote token from a lower utilized bucket (LUP) to a higher utilized bucket.
     *          from_bucket [utilized] (LUP) < to_bucket [utilized] - from_bucket.debt <= amount
     *          LUP should move up, HUP remains the same.
     */
    function testMoveFromLupMovesUtilizedToUtilizedWholeBucket() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposit 100 MKR, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 20_000 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 20_000 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 0 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    30_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 30_000 * 1e27);

        assertEq(_pool.lup(), _p3010);
    }  

    function testMoveFromLupMovesUtilizedToUtilizedAllDebtPartialDeposit() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);

        // borrower deposits 100 MKR, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 18_000 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 18_000 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 18_000 * 1e18, _p2503, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 2_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 2_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    28_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 28_000 * 1e27);

        assertEq(_pool.lup(), _p3010);
    }

    function testMoveFromLupMovesUtilizedToUtilizedAllDebtPartialDepositTwoLenders() external {
        // lender & lender2 each deposit 50_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 25_000 * 1e18, _p502);

        _lender2.addQuoteToken(_pool, address(_lender2), 5_000 * 1e18, _p3514);
        _lender2.addQuoteToken(_pool, address(_lender2), 10_000 * 1e18, _p3010);
        _lender2.addQuoteToken(_pool, address(_lender2), 10_000 * 1e18, _p2503);
        _lender2.addQuoteToken(_pool, address(_lender2), 25_000 * 1e18, _p502);

        // borrower deposits 100 MKR, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        assertEq(_pool.lup(), _p2503);

        // lender moves 1_100 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 1_100 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 1_100 * 1e18, _p2503, _p3514);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 18_900 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503),  8_900 * 1e27);
        assertEq(_pool.lpBalance(address(_lender2), _p2503), 10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    11_100 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514),  6_100 * 1e27);
        assertEq(_pool.lpBalance(address(_lender2), _p3514), 5_000 * 1e27);

        assertEq(_pool.lup(), _p3010);
    }

    function testMoveQuoteTestUpUnutilizedBook() external {
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3010);
        assertEq(_pool.lup(), 0);
        assertEq(_pool.hpb(), _p3010);

        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3010, _p3514, 2_000 * 1e18, 0);
        _lender.moveQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p3010, _p3514);

        assertEq(_pool.lup(), 0);
        assertEq(_pool.hpb(), _p3514);

        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    0);
        assertEq(deposit, 8_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    0);
        assertEq(deposit, 2_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 8_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p3514), 2_000 * 1e27);
    }

    function testMoveQuoteTestFromLupUpToUnutilizedBucketBetweenHupAndUtilizedBucket() external {
        // lender deposits 10_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2793);
        _lender.addQuoteToken(_pool, address(_lender), 8_000 * 1e18, _p2779);
        _lender.addQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2503);

        // borrower deposit 10 MKR collateral, borrows 2_000 DAI
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_000 * 1e18, 2_000 * 1e18);

        assertEq(_pool.lup(), _p2779);
        assertEq(_pool.hpb(), _p2793);

        // lender moves 1000 DAI to upper bucket
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2779, _p2821, 1_000 * 1e18, _p2779);
        _lender.moveQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2779, _p2821);

        assertEq(_pool.lup(), _p2779);
        assertEq(_pool.hpb(), _p2821);

        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2793);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(debt,    0);
        assertEq(deposit, 7_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 1_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2821), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2793), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2779), 7_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2503), 1_000 * 1e27);

        // lender moves 1000 DAI to unutilized bucket between HUP and LUP
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2779, _p2807, 1_000 * 1e18, _p2793);
        _lender.moveQuoteToken(_pool, address(_lender), 1_000 * 1e18, _p2779, _p2807);

        assertEq(_pool.lup(), _p2793);
        assertEq(_pool.hpb(), _p2821);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2793);
        assertEq(debt,    0);
        assertEq(deposit, 1_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(debt,    0);
        assertEq(deposit, 6_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 1_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2821), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2807), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2793), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2779), 6_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2503), 1_000 * 1e27);
    }
}
