// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BasicInvariants } from "../invariants/BasicInvariants.t.sol";

import '@std/console.sol';

contract RegressionTestBasic is BasicInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_invariantUnderflow_1() external {
        _basicPoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000);
        // check invariants hold true
        invariant_Lps_B1();
        invariant_quoteTokenBalance_QT1();
    }

    function test_exchange_rate_bug_simulation() external {
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

    function test_exchange_rate_bug2() external {
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
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
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
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
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
        // require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;

        _basicPoolHandler.removeCollateral(1, 1e36, 2570);
        _basicPoolHandler.removeQuoteToken(1, 1e36, 2570);

        _basicPoolHandler.removeCollateral(2, 1e36, 2570);
        _basicPoolHandler.removeQuoteToken(2, 1e36, 2570);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 12612911637698029036253737442696522, 115792089237316195423570985008687907853269984665640564039457584007913129639933)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");

    }

}