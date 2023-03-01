// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ReserveInvariants }            from "../invariants/ReserveInvariants.t.sol";

import '@std/console.sol';

contract RegressionTestReserve is ReserveInvariants { 

    function setUp() public override { 
        super.setUp();
    }   

    function test_regression_reserve_1() public {
        _reservePoolHandler.kickAuction(3833, 15167, 15812);
        _reservePoolHandler.removeQuoteToken(3841, 5339, 3672);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    // test was failing due to error in local fenwickAccureInterest method
    function test_regression_reserve_2() public {
        _reservePoolHandler.bucketTake(19730, 10740, false, 15745);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
        _reservePoolHandler.addCollateral(14982, 18415, 2079);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_3() public {
        _reservePoolHandler.repayDebt(404759030515771436961484, 115792089237316195423570985008687907853269984665640564039457584007913129639932);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
        _reservePoolHandler.removeQuoteToken(1, 48462143332689486187207611220503504, 3016379223696706064676286307759709760607418884028758142005949880337746);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_4() public {
        _reservePoolHandler.takeAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 1);  

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_5() public {
        _reservePoolHandler.addQuoteToken(16175599156223678030374425049208907710, 7790130564765920091364739351727, 3);
        _reservePoolHandler.takeReserves(5189, 15843);
        _reservePoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, false, 32141946615464);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_6() public {
        _reservePoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _reservePoolHandler.removeQuoteToken(3, 76598848420614737624527356706527, 0);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_7() public {
        _reservePoolHandler.addQuoteToken(3457, 669447918254181815570046125126321316, 999999999837564549363536522206516458546098684);
        _reservePoolHandler.takeReserves(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _reservePoolHandler.takeAuction(1340780, 50855928079819281347583122859151761721081932621621575848930363902528865907253, 1955849966715168052511460257792969975295827229642304100359774335664);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_8() public {
        _reservePoolHandler.addQuoteToken(0, 16517235514828622102184417372650002297563613398679232953, 3);
        _reservePoolHandler.takeReserves(1, 824651);
        _reservePoolHandler.kickAuction(353274873012743605831170677893, 0, 297442424590491337560428021161844134441441035247561757);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_9() public {
        _reservePoolHandler.addQuoteToken(8167, 13910, 6572);
        _reservePoolHandler.removeQuoteToken(450224344766393467188006446127940623592343232978, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 3);
        _reservePoolHandler.addQuoteToken(1338758958425242459263005073411197235389119160018038412507867175716953081924, 0, 3);
        _reservePoolHandler.removeQuoteToken(13684, 7152374202712184607581797, 37874588407625287908455929174);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_10() public {
        _reservePoolHandler.drawDebt(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _reservePoolHandler.takeAuction(57952503477150200455919212210202824, 59396836510148646246120666527, 253313800651499290076173012431766464943796699909751081638812681630219);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_reserve_11() public {
        _reservePoolHandler.drawDebt(121976811044722028186086534321386307, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _reservePoolHandler.removeQuoteToken(22099, 75368688232971077945057, 1089607217901154741924938851595);

        invariant_reserves_RE1_RE2_RE3_RE4_RE5_RE6_RE7_RE8_RE9_RE10();
    }

    function test_regression_fenwick_deposits_1() public {
        _reservePoolHandler.pledgeCollateral(2, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _reservePoolHandler.takeAuction(2, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 22181751645253101881254616597347234807617);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_incorrect_zero_deposit_buckets_1() public {
        _reservePoolHandler.addQuoteToken(26716, 792071517553389595371632366275, 1999999999999999449873579333598595527312558403);

        invariant_fenwick_prefixSumIndex_F4();
        _reservePoolHandler.takeAuction(3383098792294835418337099631478603398072656037191240558595006969488860, 23280466048203500609787983860018797249195596837096487660362732305, 999999999999999999999999012359);

        invariant_fenwick_prefixSumIndex_F4();
    }
}