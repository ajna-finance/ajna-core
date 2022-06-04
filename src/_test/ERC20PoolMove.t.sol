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

contract ERC20PoolMoveQuoteTokenTest is DSTestPlus {

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

    function assertMoveQuoteToken(address lender_, uint256 fromPrice_, uint256 toPrice_, uint256 amount_, uint256 lup_) public virtual {
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(lender_, fromPrice_, toPrice_, amount_, lup_);
        _lender.moveQuoteToken(_pool, lender_, amount_, fromPrice_, toPrice_);
    }

    /**
     *  @notice Tests move quote token from a higher unutilized bucket to a lower unutilized bucket.
     */
    function testMoveUnutilizedToUnutilizedDown() external {

        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_466_756.126702504695020000 * 1e18);

        // lender moves 10_000 DAI down
        assertMoveQuoteToken(address(_lender), _p3514, _p2503, 10_000 * 1e18, 0);

        assertEq(_pool.hpb(), _p3010);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   160_358_601.415745437888700000 * 1e18);
        
        (, uint256 up, uint256 down, uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    0);
        assertEq(deposit, 0);
        // check that bucket was deactivated
        assertEq(up, 0);
        assertEq(down, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 0);

        (, up, down, deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);
        assertEq(up,      _p3010);
        assertEq(down,    _p2503);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, up, down, deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 40_000 * 1e18);
        assertEq(up,      _p3010);
        assertEq(down,    0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 40_000 * 1e27);
    }

    /**
     *  @notice Tests move quote token from a lower unutilized bucket to a higher unutilized bucket.
     */
    function testMoveUnutilizedToUnutilizedUp() external {

        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_466_756.126702504695020000 * 1e18);

        // lender moves 10_000 DAI up
        assertMoveQuoteToken(address(_lender), _p2503, _p3514, 10_000 * 1e18, 0);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   180_574_910.837659571501340000 * 1e18);
         
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , ,deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    0);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 20_000 * 1e27);
    }

    function testMoveUnutilizedToUnutilizedUpHpb() external {
        // lender deposits 60_000 DAI accross 3 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 30_000 * 1e18, _p2503);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 60_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_466_756.126702504695020000 * 1e18);

        // borrower deposit 10 MKR collateral, borrows 15_000 DAI
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       15_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 45_000 * 1e18);
        assertEq(_pool.totalCollateral(), 10 * 1e18);
        assertEq(_pool.pdAccumulator(),   120_268_951.061809078416525000 * 1e18);

        // lender moves 10_000 DAI up to new HUP
        assertMoveQuoteToken(address(_lender), _p2503, _p5007, 10_000 * 1e18, _p3514);

        assertEq(_pool.hpb(), _p5007);
        assertEq(_pool.lup(), _p3514);

        assertEq(_pool.totalDebt(),       15_020.562988409436006273 * 1e18);
        assertEq(_pool.totalQuoteToken(), 45_000 * 1e18);
        assertEq(_pool.totalCollateral(), 10 * 1e18);
        assertEq(_pool.pdAccumulator(),   127_856_442.323061266651880679 * 1e18);
         
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    0);
        assertEq(deposit, 20_006.854971374172068454 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p5007);
        assertEq(debt,    10_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p5007), 10_000 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposit 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   62_674_484.767587889162425000 * 1e18);

        // lender moves 100 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p502, _p3514, 100 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 100 * 1e18, _p502, _p3514);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_047.979022479963881910 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   62_874_593.271211023755978500 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 49_900 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 49_900 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_113.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_099.863107482144037592367261263 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   62_674_484.767587889162425000 * 1e18);

        // lender moves 5_000 DAI up
        assertMoveQuoteToken(address(_lender), _p502, _p2503, 5_000 * 1e18, _p2503);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_047.979022479963881910 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_679_909.948744618840100000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 45_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 45_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_006.854971374172068454 * 1e18);
        assertEq(deposit, 20_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 24_998.286844338108071385169126010 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       31_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_688_560.864766669835605000 * 1e18);

        // lender moves 5_000 DAI up
        assertMoveQuoteToken(address(_lender), _p502, _p3514, 5_000 * 1e18, _p3010);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       31_042.495815665858306783 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   84_722_782.041238886789161588 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 45_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 45_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 20_001.371764560066493326 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    15_013.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 14_993.155374107201879618363063127 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   62_674_484.767587889162425000 * 1e18);

        // lender moves 100 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p502, 100 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 100 * 1e18, _p3514, _p502);
    
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 50_100 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 50_100 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_106.854971374172068454 * 1e18);
        assertEq(deposit, 14_900 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_913.708017035263937818 * 1e18);
        assertEq(deposit, 0 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_900.136892517855962407632738737 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 35_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 35_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   62_674_484.767587889162425000 * 1e18);

        // lender moves 15_000 DAI down
        assertMoveQuoteToken(address(_lender), _p2503, _p502, 15_000 * 1e18, _p2503);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       35_047.979022479963881910 * 1e18);
        assertEq(_pool.totalQuoteToken(), 65_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   32_658_209.224117700129400000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 65_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 65_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    5_006.854971374172068454 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 5_005.139466985675785844492621969 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 52_500 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   147_436_544.669302615327894500 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       31_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 21_500 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   49_571_840.247146270513429500 * 1e18);

        // lender moves 19_500 DAI down
        assertMoveQuoteToken(address(_lender), _p2503, _p502, 19_500 * 1e18, _p502);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p502);

        assertEq(_pool.totalDebt(),       31_042.495815665858306783 * 1e18);
        assertEq(_pool.totalQuoteToken(), 21_500 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   10_802_330.743362008504340000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    0);
        assertEq(deposit, 21_500 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 21_500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2000);
        assertEq(debt,    500 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2000), 500 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    501.371764560066493326 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 501.337378717628419500856042803 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 8_000 DAI down
        assertMoveQuoteToken(address(_lender), _p3514, _p502, 8_000 * 1e18, _p502);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p502);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   27_131_435.355420858569040000 * 1e18);

        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p502);
        assertEq(debt,    4_000 * 1e18);
        assertEq(deposit, 54_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p502), 58_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    20_021.933790112962400055 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    20_027.416034070527875637 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    2_013.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 2_010.951401428476992610619098997 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       31_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_688_560.864766669835605000 * 1e18);

        // lender moves 5_000 DAI up to new HPB
        assertMoveQuoteToken(address(_lender), _p2503, _p9020, 5_000 * 1e18, _p3010);

        assertEq(_pool.hpb(), _p9020);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       31_042.495815665858306783 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   74_717_356.860082157111486588 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 15_001.371764560066493326 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 15_000.342917619904722948937446873 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    16_028.787798630594368963 * 1e18);
        assertEq(deposit, 3_998.628235439933506674 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p9020);
        assertEq(debt,    5_000 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p9020), 5_000 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 500 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p2503, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3514, _p2503);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    16_521.933790112962400055 * 1e18);
        assertEq(deposit, 4_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 20_499.452255952324806606741917020 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    20_027.416034070527875637 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_513.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_500.684462589279812038163693687 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 500 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p2503, _p3514);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    15_521.933790112962400055 * 1e18);
        assertEq(deposit, 4_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 19_500.547744047675193393258082980 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_513.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_499.315537410720187961836306313 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 500 DAI down
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3514, _p3010, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3514, _p3010);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    20_527.416034070527875637 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 20_499.315537410720187961811374712 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    9_513.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 9_500.684462589279812038163693687 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR collateral, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 500 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p3010, _p3514, 500 * 1e18, _p2503);
        _lender.moveQuoteToken(_pool, address(_lender), 500 * 1e18, _p3010, _p3514);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p3010);
        assertEq(debt,    19_527.416034070527875637 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3010), 19_500.684462589279812038188625288 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    10_513.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 10_499.315537410720187961836306313 * 1e27);
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
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposit 100 MKR, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 20_000 DAI up
        assertMoveQuoteToken(address(_lender), _p2503, _p3514, 20_000 * 1e18, _p3010);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   37_154_138.879113994867214508 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 21.933790112962400055 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 21.909761907007735730323319207 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    30_013.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 29_972.621496428807518473452252508 * 1e27);
    }  

    function testMoveFromLupMovesUtilizedToUtilizedAllDebtPartialDeposit() external {

        // lender deposits 100_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 20_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 50_000 * 1e18, _p502);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR, borrows 46_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 46_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       46_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   35_135_775.500346242311180000 * 1e18);

        // lender moves 18_000 DAI up
        assertMoveQuoteToken(address(_lender), _p2503, _p3514, 18_000 * 1e18, _p3010);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       46_063.057841218754213511 * 1e18);
        assertEq(_pool.totalQuoteToken(), 54_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   36_139_392.883307622088114508 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 2_021.933790112962400055 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503), 2_019.718785716306962157290987286 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    28_013.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514), 27_975.359346785926766626107027257 * 1e27);
    }

    function testMoveFromLupMovesUtilizedToUtilizedAllDebtPartialDepositTwoLenders() external {
        // lender & lender2 each deposit 50_000 DAI accross 4 buckets
        _lender.addQuoteToken(_pool, address(_lender), 5_000 * 1e18, _p3514);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3010);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p2503);
        _lender.addQuoteToken(_pool, address(_lender), 25_000 * 1e18, _p502);
        skip(864000);

        _lender2.addQuoteToken(_pool, address(_lender2), 5_000 * 1e18, _p3514);
        _lender2.addQuoteToken(_pool, address(_lender2), 10_000 * 1e18, _p3010);
        _lender2.addQuoteToken(_pool, address(_lender2), 10_000 * 1e18, _p2503);
        _lender2.addQuoteToken(_pool, address(_lender2), 25_000 * 1e18, _p502);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 100_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   170_553_265.286923014650070000 * 1e18);

        // borrower deposits 100 MKR, borrows 31_000 DAI
        _borrower.addCollateral(_pool, 100 * 1e18);
        _borrower.borrow(_pool, 31_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p2503);

        assertEq(_pool.totalDebt(),       31_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_688_560.864766669835605000 * 1e18);

        // lender moves 1_100 DAI up
        vm.expectEmit(true, true, true, true);
        emit MoveQuoteToken(address(_lender), _p2503, _p3514, 1_100 * 1e18, _p3010);
        _lender.moveQuoteToken(_pool, address(_lender), 1_100 * 1e18, _p2503, _p3514);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), _p3010);

        assertEq(_pool.totalDebt(),       31_042.495815665858306783 * 1e18);
        assertEq(_pool.totalQuoteToken(), 69_000 * 1e18);
        assertEq(_pool.totalCollateral(), 100 * 1e18);
        assertEq(_pool.pdAccumulator(),   72_738_602.168259730192241588 * 1e18);
        
        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 18_901.371764560066493326 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2503),  8_900.075441876379039048766238312 * 1e27);
        assertEq(_pool.lpBalance(address(_lender2), _p2503), 10_000 * 1e27);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p3514);
        assertEq(debt,    11_113.708017035263937818 * 1e18);
        assertEq(deposit, 0);

        assertEq(_pool.lpBalance(address(_lender), _p3514),  6_098.494182303584413516039873888 * 1e27);
        assertEq(_pool.lpBalance(address(_lender2), _p3514), 5_000 * 1e27);
    }

    function testMoveQuoteTestUpUnutilizedBook() external {
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p3010);
        skip(864000);

        assertEq(_pool.hpb(), _p3010);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   30_108_920.221978815578450000 * 1e18);

        // should revert if moving to an invalid price bucket
        vm.expectRevert("P:MQT:INVALID_TO_PRICE");
        _lender.moveQuoteToken(_pool, address(_lender), 2_000 * 1e18, _p3010, 3_000 * 1e18);

        // should revert if trying to move more than entitled
        vm.expectRevert("B:MQT:AMT_GT_CLAIM");
        _lender.moveQuoteToken(_pool, address(_lender), 10_001 * 1e18, _p3010, _p3514);

        assertMoveQuoteToken(address(_lender), _p3010, _p3514, 2_000 * 1e18, 0);

        assertEq(_pool.hpb(), _p3514);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   31_115_805.168363856160614000 * 1e18);

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
        skip(864000);

        assertEq(_pool.hpb(), _p2793);
        assertEq(_pool.lup(), 0);

        assertEq(_pool.totalDebt(),       0);
        assertEq(_pool.totalQuoteToken(), 10_000 * 1e18);
        assertEq(_pool.totalCollateral(), 0);
        assertEq(_pool.pdAccumulator(),   27_537_038.408453861794539000 * 1e18);

        // borrower deposit 10 MKR collateral, borrows 2_000 DAI
        _borrower.addCollateral(_pool, 10 * 1e18);
        _borrower.borrow(_pool, 2_000 * 1e18, 2_000 * 1e18);
        skip(864000);

        assertEq(_pool.hpb(), _p2793);
        assertEq(_pool.lup(), _p2779);

        assertEq(_pool.totalDebt(),       2_000.000961538461538462 * 1e18);
        assertEq(_pool.totalQuoteToken(), 8_000 * 1e18);
        assertEq(_pool.totalCollateral(), 10 * 1e18);
        assertEq(_pool.pdAccumulator(),   21_963_223.154124141758234000 * 1e18);

        // should revert if moving leaves pool undercollateralized
        vm.expectRevert("P:MQT:POOL_UNDER_COLLAT");
        _lender.moveQuoteToken(_pool, address(_lender), 8_000 * 1e18, _p2779, _p1);

        // lender moves 1000 DAI to upper bucket
        assertMoveQuoteToken(address(_lender), _p2779, _p2821, 1_000 * 1e18, _p2779);

        assertEq(_pool.hpb(), _p2821);
        assertEq(_pool.lup(), _p2779);

        assertEq(_pool.totalDebt(),       2_002.742566263592887108 * 1e18);
        assertEq(_pool.totalQuoteToken(), 8_000 * 1e18);
        assertEq(_pool.totalCollateral(), 10 * 1e18);
        assertEq(_pool.pdAccumulator(),   21_963_223.154124141758234000 * 1e18);

        (, , , uint256 deposit, uint256 debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2793);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(debt,    1.371764560066493326 * 1e18);
        assertEq(deposit, 7_000 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 1_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2821), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2793), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2779), 7_000.171441172892672865623183188 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2503), 1_000 * 1e27);

        // lender moves 1000 DAI to unutilized bucket between HUP and LUP
        assertMoveQuoteToken(address(_lender), _p2779, _p2807, 1_000 * 1e18, _p2793);

        assertEq(_pool.hpb(), _p2821);
        assertEq(_pool.lup(), _p2793);

        assertEq(_pool.totalDebt(),       2_002.742566263592887108 * 1e18);
        assertEq(_pool.totalQuoteToken(), 8_000 * 1e18);
        assertEq(_pool.totalCollateral(), 10 * 1e18);
        assertEq(_pool.pdAccumulator(),   21_977_103.875550823712006007 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2821);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2807);
        assertEq(debt,    1_000 * 1e18);
        assertEq(deposit, 0);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2793);
        assertEq(debt,    2.742566263592887107 * 1e18);
        assertEq(deposit, 998.628235439933506674 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2779);
        assertEq(debt,    0);
        assertEq(deposit, 6_001.371764560066493326 * 1e18);

        (, , , deposit, debt, , , ) = _pool.bucketAt(_p2503);
        assertEq(debt,    0);
        assertEq(deposit, 1_000 * 1e18);

        assertEq(_pool.lpBalance(address(_lender), _p2821), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2807), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2793), 1_000 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2779), 6_000.342882345785345731246366376 * 1e27);
        assertEq(_pool.lpBalance(address(_lender), _p2503), 1_000 * 1e27);
    }
}

contract ERC20PoolMoveQuoteTokenByRemoveAddTest is ERC20PoolMoveQuoteTokenTest {
    function assertMoveQuoteToken(address lender_, uint256 fromPrice_, uint256 toPrice_, uint256 amount_, uint256 lup_) public override {
        _lender.removeQuoteToken(_pool, lender_, amount_, fromPrice_);
        _lender.addQuoteToken(_pool, lender_, amount_, toPrice_);
        assertEq(_pool.lup(), lup_);
    }
}
