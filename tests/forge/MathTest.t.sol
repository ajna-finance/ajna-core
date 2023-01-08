// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import './utils/DSTestPlus.sol';

import '@prb-math/contracts/PRBMathSD59x18.sol';
import '@prb-math/contracts/PRBMathUD60x18.sol';

import 'src/libraries/internal/Maths.sol';

contract MathTest is DSTestPlus {

    function testRayToWadRounded() external {
        uint256 amount = 5_000.00076103507940381999999950 * 1e27;
        assertEq(Maths.rayToWad(amount), 5_000.000761035079403820 * 1e18);

        assertEq(Maths.rayToWad(4 * 1e27), 4 * 1e18);
        assertEq(Maths.rayToWad(0.0000000000000000006 * 1e27), 1);
        assertEq(Maths.rayToWad(0.0000000000000000004 * 1e27), 0);
    }

    function testZeroStaysZero() external {
        assertEq(Maths.rayToWad(0), 0);
        assertEq(Maths.wadToRay(0), 0);
    }

    function testMultiplication() external {
        uint256 debt     = 10_000.44444444444443999 * 1e18;
        uint256 inflator = 1.02132007 * 1e27;

        assertEq(debt * inflator,                         10_213.6546200311111065616975993 * 1e45);
    }

    function testDivision() external {
        uint256 debt  = 11_000.143012091382543917 * 1e18;
        uint256 price = 1_001.6501589292607751220 * 1e18;

        assertEq(Maths.wdiv(debt, price),   10.98202093218880245 * 1e18);
        assertEq(debt * 1e18 / price,       10.98202093218880245 * 1e18);
        assertEq(Maths.wwdivr(debt, price), 10.982020932188802450191601163 * 1e27);

        uint256 exchangeRate = 1.09232010 * 1e27;
        assertEq(Maths.rdiv(Maths.wadToRay(debt), exchangeRate), Maths.wrdivr(debt, exchangeRate));

        uint256 lpBalance = 36_900.58124 * 1e27;
        uint256 lpRedemption = Maths.rdiv(lpBalance, exchangeRate);
        assertEq(Maths.rayToWad(lpRedemption), Maths.rrdivw(lpBalance, exchangeRate));
        assertEq(Maths.rayToWad(Maths.rdiv(lpRedemption, Maths.wadToRay(price))), Maths.rwdivw(lpRedemption, price));

        uint256 claimableCollateral1 = Maths.rwdivw(Maths.rdiv(lpBalance, exchangeRate), price); // rounds
        uint256 claimableCollateral2 = lpBalance * 1e36 / exchangeRate / price;                  // truncates
        assertEq(claimableCollateral1, 33.726184963566645999 * 1e18);
        assertEq(claimableCollateral2, 33.726184963566645998 * 1e18);

        assertEq(Maths.wdiv(1 * 1e18, 60 * 1e18), 0.016666666666666667 * 1e18);
        assertEq(Maths.rdiv(1 * 1e27, 3 * 1e27),  0.333333333333333333333333333 * 1e27);
    }

    function testScaleConversions() external {
        assertEq(Maths.wad(153), 153 * 1e18);
    } 

    function testExp() external {
        assertEq(PRBMathUD60x18.exp(1.53 * 1e18), 4.618176822299780807 * 1e18);

        int256 testPower = PRBMathSD59x18.mul(-1 * 1e18, int256(Maths.wdiv(12180 * 1e18, 3600 * 1e18)));
        assertEq(PRBMathSD59x18.exp2(testPower), 0.095833021541850035 * 1e18);
    }

    function testPow() external {
        assertEq(Maths.rpow(0.5 * 1e27, 60), 0.000000000000000000867361738 * 1e27);
        assertEq(Maths.rpow(0.5 * 1e27, 80), 0.000000000000000000000000827 * 1e27);
    }

    function testMaxMin() external {
        uint256 smallerWad = 0.002144924036174740 * 1e18;
        uint256 largerWad  = 0.951347940696070000 * 1e18;

        assertEq(Maths.max(0, 9), 9);
        assertEq(Maths.max(3, 0), 3);
        assertEq(Maths.max(smallerWad, largerWad), largerWad);

        assertEq(Maths.min(2, 4), 2);
        assertEq(Maths.min(0, 9), 0);
        assertEq(Maths.min(smallerWad, largerWad), smallerWad);
    }
}
