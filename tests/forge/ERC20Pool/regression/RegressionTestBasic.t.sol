// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BasicInvariants } from "../invariants/BasicInvariants.t.sol";
import { IBaseHandler } from '../invariants/handlers/IBaseHandler.sol';
import "src/libraries/internal/Maths.sol";

import '@std/console.sol';

contract RegressionTestBasic is BasicInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_regression_invariantUnderflow_1() external {
        _basicPoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000);
        // check invariants hold true
        invariant_Lps_B1();
        invariant_quoteTokenBalance_QT1();
    }

    function test_regression_exchange_rate_bug_1() external {
        // Action sequence
        // 1. addQuoteToken(6879, 2570)
        // 2. addCollateral(3642907759282013932739218713, 2570)
        // 3. removeCollateral(296695924278944779257290397234298756, 2570)

        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addQuoteToken(999999999844396154169639088436193915956854451, 6879, 2809);
        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(6879, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;
        _basicPoolHandler.addCollateral(2, 36429077592820139327392187131, 202214962129783771592);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(3642907759282013932739218713, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;
        _basicPoolHandler.removeCollateral(1, 2296695924278944779257290397234298756, 10180568736759156593834642286260647915348262280903719122483474452532722106636);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(296695924278944779257290397234298756, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_bug_2() external {
        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addQuoteToken(211670885988646987334214990781526025942, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 6894274025938223490357894120267612065037086600750070030707794233);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(211670885988646987334214990781526025942, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 6894274025938223490357894120267612065037086600750070030707794233)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;
        _basicPoolHandler.addCollateral(117281, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(117281, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;

        _basicPoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 12612911637698029036253737442696522, 115792089237316195423570985008687907853269984665640564039457584007913129639933);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 12612911637698029036253737442696522, 115792089237316195423570985008687907853269984665640564039457584007913129639933)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;

        _basicPoolHandler.removeCollateral(1, 1e36, 2570);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(1, 1e36, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");

        _basicPoolHandler.removeQuoteToken(1, 1e36, 2570);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeQuoteToken(1, 1e36, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");

        _basicPoolHandler.removeCollateral(2, 1e36, 2570);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(2, 1e36, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");

        _basicPoolHandler.removeQuoteToken(2, 1e36, 2570);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeQuoteToken(2, 1e36, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
    }

    // test will fail when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_bug_3() external {
        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addQuoteToken(2842, 304, 2468594405605444095992);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(2842, 304, 2468594405605444095992)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addCollateral(0, 1, 3);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(0, 1, 3)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");

        _basicPoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        // requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");

        _basicPoolHandler.removeCollateral(0, 1, 3);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(0, 1, 3)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
    }

    // test was failing when actors = 1, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_bug_4() external {
        // Actors = 1
        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 587135207579305083672251579076072787077);
        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 587135207579305083672251579076072787077)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.removeCollateral(712291886391993882782748602346033231793324080118979183300958, 673221151277569661050873992210938589, 999999997387885196930781163353866909746906615);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(712291886391993882782748602346033231793324080118979183300958, 673221151277569661050873992210938589, 999999997387885196930781163353866909746906615)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.removeCollateral(4434852123445331038838, 92373980881732279172264, 16357203);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(4434852123445331038838, 92373980881732279172264, 16357203)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addQuoteToken(6532756, 16338, 2488340072929715905208495398161339232954907500634);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(6532756, 16338, 2488340072929715905208495398161339232954907500634)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.removeCollateral(934473801621702106582064701468475360, 999999998588451849650292641565069384488310108, 2726105246641027837873401505120164058057757115396);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(934473801621702106582064701468475360, 999999998588451849650292641565069384488310108, 2726105246641027837873401505120164058057757115396)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;

        _basicPoolHandler.addQuoteToken(0, 3272, 688437777000000000);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(0, 3272, 688437777000000000)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.removeQuoteToken(36653992905059663682442427, 3272, 688437777000000000);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeQuoteToken(36653992905059663682442427, 3272, 688437777000000000)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;
    }

    // test was failing when actors = 1, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_bug_5() external {
        _basicPoolHandler.drawDebt(1156, 1686);
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicPoolHandler.addQuoteToken(711, 2161, 2012); 
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();   
    }

    // test was failing when actors = 1, buckets = [2570]
    function test_regression_exchange_rate_bug_6() external {
        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addCollateral(999999999000000000000000081002632733724231666, 999999999243662968633890481597751057821356823, 1827379824097500721086759239664926559);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(243662968633890481597751057821356823, 2570, 1672372187)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addQuoteToken(108018811574020559, 3, 617501271956497833026154369680502407518122199901237699791086943);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(3, 2570, 1672372187)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addCollateral(95036573736725249741129171676163161793295193492729984020, 5009341426566798172861627799, 2);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(5009341426566798172861627799, 2570, 1672372187)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;

        _basicPoolHandler.removeCollateral(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 5814100241);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(984665640564039457584007913129639935, 2570)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    // Fixed with commit -> https://github.com/ajna-finance/contracts/pull/613/commits/f106f0f7c96c1662325bdb5151fd745544e6dce0 
    function test_regression_exchange_rate_bug_7() external {
        uint256 previousExchangeRate = 1e18;
        _basicPoolHandler.addCollateral(999999999249784004703856120761629301735818638, 15200, 2324618456838396048595845067026807532884041462750983926777912015561);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(15200, 2570, 1672372187) by actor8");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addQuoteToken(0, 2, 60971449684543878);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(2, 2570, 1672372187) by actor0");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.addCollateral(0, 648001392760875820320327007315181208349883976901103343226563974622543668416, 38134304133913510899173609232567613);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(883976901103343226563974622543668416, 2570, 1672372187) by actor0");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;


        _basicPoolHandler.removeCollateral(0, 1290407354289435191451647900348688457414638662069174249777953, 125945131546441554612275631955778759442752893948134984981883798);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(900348688457414638662069174249777953, 2570) by actor0");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e12, "Incorrect exchange rate change");
        previousExchangeRate = exchangeRate;
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_bug_8() external {
        _basicPoolHandler.drawDebt(0, 10430);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(20860, 2570, 1672372187) and drawDebt(Actor0: [0x129862D03ec9aBEE86890af0AB05EC02C654B403], 10430, 7388, 5) by actor0");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();

        _basicPoolHandler.addCollateral(86808428701435509359888008280539191473421, 35, 89260656586096811497271673595050);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(35, 2570, 1689652187) by actor1");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_bug_9() external {
        _basicPoolHandler.addQuoteToken(179828875014111774829603408358905079754763388655646874, 39999923045226513122629818514849844245682430, 12649859691422584279364490330583846883);
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicPoolHandler.addCollateral(472, 2100, 11836);
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicPoolHandler.pledgeCollateral(7289, 8216);
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

}