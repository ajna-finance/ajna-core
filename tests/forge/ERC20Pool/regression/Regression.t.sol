// SPDX-License-Identifier: UNLICENSED

import { BasicInvariants }            from "../invariants/BasicInvariants.t.sol";

pragma solidity 0.8.14;

import "@std/console.sol";


contract RegressionTest is BasicInvariants { 

    function setUp() public override { 
        super.setUp();

    }

    function test_regression_invariantUnderflow_1() external {
        _basicPoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000);
        // check invariants hold true
        invariant_Lps_B1();
        invariant_quoteTokenBalance_QT1();
    }

    function test_exchange_rate_bug_2() external {
        // Action sequence
        // 1. addQuoteToken(6879, 2570)
        // 2. addCollateral(3642907759282013932739218713, 2570)
        // 3. removeCollateral(296695924278944779257290397234298756, 2570)

        uint256 previousExchangeRate = 1e27;
        _basicPoolHandler.addQuoteToken(5100, 7576, 1);
        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(5100, 7576, 1)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        exchangeRate = previousExchangeRate;
        _basicPoolHandler.addCollateral(1488223273328773440688798324, 9792025095222862388755846307853263025243210652, 435977);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addCollateral(1488223273328773440688798324, 9792025095222862388755846307853263025243210652, 435977)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
        exchangeRate = previousExchangeRate;
        _basicPoolHandler.removeCollateral(0, 3, 1860606116966568790222836725195098);
        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(0, 3, 1860606116966568790222836725195098)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        requireWithinDiff(previousExchangeRate, exchangeRate, 1e18, "Incorrect exchange rate");
    }

    function test_exchange_rate_bug_3() external {
        // Actors = 1
        uint256 previousExchangeRate = 1e27;
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

// [FAIL. Reason: Incorrect exchange Rate changed]
//         [Sequence]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=addCollateral(uint256,uint256,uint256), args=[115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 587135207579305083672251579076072787077]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=removeCollateral(uint256,uint256,uint256), args=[712291886391993882782748602346033231793324080118979183300958, 673221151277569661050873992210938589, 999999997387885196930781163353866909746906615]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=removeCollateral(uint256,uint256,uint256), args=[4434852123445331038838, 92373980881732279172264, 16357203]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=addQuoteToken(uint256,uint256,uint256), args=[6532756, 16338, 2488340072929715905208495398161339232954907500634]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=removeCollateral(uint256,uint256,uint256), args=[934473801621702106582064701468475360, 999999998588451849650292641565069384488310108, 2726105246641027837873401505120164058057757115396]
//                 sender=0x0000000000000000000000000000000000001234 addr=[tests/forge/ERC20Pool/invariants/handlers/BasicPoolHandler.sol:BasicPoolHandler]0x42a83467e1cd1be83eb47095a77c2b5cee761606 calldata=removeQuoteToken(uint256,uint256,uint256), args=[36653992905059663682442427, 3272, 688437777000000000]


}