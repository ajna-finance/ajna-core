// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract PoolHelperTest is DSTestPlus {

    /**
     *  @notice Tests fenwick index calculation from varying bucket prices
     */
    function testPriceToIndex() external {
        _assertBucketPriceOutOfBoundsRevert(2_000_000_000 * 10**18);
        _assertBucketPriceOutOfBoundsRevert(1_004_968_987.606512354182109772 * 10**18);
        assertEq(_indexOf(1_004_968_987.606512354182109771 * 10**18), 0);
        assertEq(_indexOf(4_669_863.090889329544038534 * 1e18),       1077);
        assertEq(_indexOf(49_910.043670274810022205 * 1e18),          1987);
        assertEq(_indexOf(21_699.795273870723549803 * 1e18),          2154);
        assertEq(_indexOf(2_000.221618840727700609 * 1e18),           2632);
        assertEq(_indexOf(146.575625611106531706 * 1e18),             3156);
        assertEq(_indexOf(145.846393642892072537 * 1e18),             3157);
        assertEq(_indexOf(100.332368143282009890 * 1e18),             3232);
        assertEq(_indexOf(5.263790124045347667 * 1e18),               3823);
        assertEq(_indexOf(1.646668492116543299 * 1e18),               4056);
        assertEq(_indexOf(1.315628874808846999 * 1e18),               4101);
        assertEq(_indexOf(1.051140132040790557 * 1e18),               4146);
        assertEq(_indexOf(1 * 1e18),                                  4156);
        assertEq(_indexOf(0.951347940696068854 * 1e18),               4166);
        assertEq(_indexOf(0.463902261297398000 * 1e18),               4310);
        assertEq(_indexOf(0.006856528811048429 * 1e18),               5155);
        assertEq(_indexOf(0.006822416727411372 * 1e18),               5156);
        assertEq(_indexOf(0.002144924036174487 * 1e18),               5388);
        assertEq(_indexOf(0.000046545370002462 * 1e18),               6156);
        assertEq(_indexOf(0.000009917388865689 * 1e18),               6466);
        assertEq(_indexOf(99_836_282_890),                            7388);
        _assertBucketPriceOutOfBoundsRevert(99_836_282_889);
        _assertBucketPriceOutOfBoundsRevert(1);
        _assertBucketPriceOutOfBoundsRevert(0);
    }

    /**
     *  @notice Tests bucket price calculation from varying fenwick index
     */
    function testIndexToPrice() external {
        assertEq(                  _priceAt(0),    1_004_968_987.606512354182109771 * 10**18);
        assertEq(                  _priceAt(1077), 4_669_863.090889329544038534 * 1e18);
        assertEq(                  _priceAt(1987), 49_910.043670274810022205 * 1e18);
        assertEq(                  _priceAt(2154), 21_699.795273870723549803 * 1e18);
        assertEq(                  _priceAt(2632), 2_000.221618840727700609 * 1e18);
        assertEq(                  _priceAt(3156), 146.575625611106531706 * 1e18);
        assertEq(                  _priceAt(3157), 145.846393642892072537 * 1e18);
        assertEq(                  _priceAt(3232), 100.332368143282009890 * 1e18);
        assertEq(                  _priceAt(3823), 5.263790124045347667 * 1e18);
        assertEq(                  _priceAt(4056), 1.646668492116543299 * 1e18);
        assertEq(                  _priceAt(4101), 1.315628874808846999 * 1e18);
        assertEq(                  _priceAt(4146), 1.051140132040790557 * 1e18);
        assertEq(                  _priceAt(4156), 1 * 1e18);
        assertEq(                  _priceAt(4166), 0.951347940696068854 * 1e18);
        assertEq(                  _priceAt(4310), 0.463902261297391185 * 1e18);
        assertEq(                  _priceAt(5155), 0.006856528811048429 * 1e18);
        assertEq(                  _priceAt(5156), 0.006822416727411372 * 1e18);
        assertEq(                  _priceAt(5388), 0.002144924036174487 * 1e18);
        assertEq(                  _priceAt(6156), 0.000046545370002462 * 1e18);
        assertEq(                  _priceAt(6466), 0.000009917388865689 * 1e18);
        assertEq(                  _priceAt(7388), 99_836_282_890);
        _assertBucketIndexOutOfBoundsRevert(7389);
        _assertBucketIndexOutOfBoundsRevert(8191);
        _assertBucketIndexOutOfBoundsRevert(9999);
    }

    /**
     *  @notice Tests collateral encumberance for varying values of debt and lup
     */
    function testEncumberance() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(_encumberance(debt, price),   10.98202093218880245 * 1e18);
        assertEq(_encumberance(0, price),      0);
        assertEq(_encumberance(debt, 0),       0);
        assertEq(_encumberance(0, 0),          0);
    }

    /**
     *  @notice Tests loan/pool collateralization for varying values of debt, collateral and lup
     */
    function testCollateralization() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;
        uint256 collateral = 10.98202093218880245 * 1e18;

        assertEq(_collateralization(debt, collateral, price),   1 * 1e18);
        assertEq(_collateralization(0, collateral, price),      Maths.WAD);
        assertEq(_collateralization(debt, collateral, 0),       Maths.WAD);
        assertEq(_collateralization(0, collateral, 0),          Maths.WAD);
        assertEq(_collateralization(debt, 0, price),            0);
    }

    /**
     *  @notice Tests pool target utilization based on varying values of debt and lup estimated moving averages
     */
    function testPoolTargetUtilization() external {
        uint256 debtEma  = 11_000.143012091382543917 * 1e18;
        uint256 lupColEma = 1_001.6501589292607751220 * 1e18;

        assertEq(_targetUtilization(debtEma, lupColEma), 10.98202093218880245 * 1e18);
        assertEq(_targetUtilization(0, lupColEma),       Maths.WAD);
        assertEq(_targetUtilization(debtEma, 0),         Maths.WAD);
        assertEq(_targetUtilization(0, 0),               Maths.WAD);
    }

    /**
     *  @notice Tests fee rate for early withdrawals
     */
    function testFeeRate() external {
        uint256 interestRate = 0.12 * 1e18;
        assertEq(_feeRate(interestRate),  0.002307692307692308 * 1e18);
        assertEq(_feeRate(0.52 * 1e18),     0.01 * 1e18);
        assertEq(_feeRate(0.26 * 1e18),     0.005 * 1e18);
    }

    /**
     *  @notice Tests the minimum debt amount calculations for varying parameters
     */
    function testMinDebtAmount() external {
        uint256 debt = 11_000 * 1e18;
        uint256 loansCount = 50;

        assertEq(_minDebtAmount(debt, loansCount), 22 * 1e18);
        assertEq(_minDebtAmount(debt, 10),         110 * 1e18);
        assertEq(_minDebtAmount(debt, 0),          0);
        assertEq(_minDebtAmount(0, loansCount),    0);
    }

    /**
     *  @notice Tests facilities used for rounding token amounts to decimal places supported by the token
     */
    function testRounding() external {
        uint256 decimals   = 6;
        uint256 tokenScale = 10 ** (18-decimals);

        uint256 one_third = Maths.wdiv(1 * 1e18, 3 * 1e18);
        assertEq(_roundToScale(one_third, tokenScale),   0.333333 * 1e18);
        assertEq(_roundUpToScale(one_third, tokenScale), 0.333334 * 1e18);

        uint256 nine_and_two_thirds = 9 * 1e18 + Maths.wdiv(2 * 1e18, 3 * 1e18);
        assertEq(_roundToScale(nine_and_two_thirds, tokenScale),   9.666666 * 1e18);
        assertEq(_roundUpToScale(nine_and_two_thirds, tokenScale), 9.666667 * 1e18);

        uint256 five = 5 * 1e18;
        assertEq(_roundToScale(five, tokenScale),   5 * 1e18);
        assertEq(_roundUpToScale(five, tokenScale), 5 * 1e18);
    }

    function _assertBucketIndexOutOfBoundsRevert(uint256 index) internal {
        vm.expectRevert(BucketIndexOutOfBounds.selector);
        _priceAt(index);
    }

    function _assertBucketPriceOutOfBoundsRevert(uint256 price) internal {
        vm.expectRevert(BucketPriceOutOfBounds.selector);
        _indexOf(price);
    }
}
