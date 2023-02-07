// SPDX-License-Identifier: UNLICENSED

import { LiquidationInvariant }            from "../invariants/LiquidationInvariant.t.sol";

pragma solidity 0.8.14;

import '@std/console.sol';


contract RegressionTestLiquidation is LiquidationInvariant { 

    function setUp() public override { 
        super.setUp();

    }

    function test_regression_quote_token() external {
        _liquidationPoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        // _liquidationPoolHandler.bucketTake(51828712774376551522763836267, 115792089237316195423570985008687907853269984665640564039457584007913129639935, true, 65341451524603236382335424603223150396);

        // check invariants hold true
        invariant_quoteTokenBalance_QT1();
    }

    function test_arithmetic_overflow() external {
        _liquidationPoolHandler.kickAuction(128942392769655840156268259377571235707684499808935108685525899532745, 9654010200996517229486923829624352823010316518405842367464881, 135622574118732106350824249104903);
        _liquidationPoolHandler.addQuoteToken(3487, 871, 1654);

        // check invariants hold true
        invariant_quoteTokenBalance_QT1();
    }

    function test_exchange_rate_bugs() external {
        uint256 previousExchangeRate = 1e18;

        _liquidationPoolHandler.drawDebt(11107, 2212);

        ( , uint256 quote, uint256 collateral, uint256 lps, , uint256 exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After drawDebt(11107, 2212)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;

        _liquidationPoolHandler.addQuoteToken(10440325087293679399519637, 3, 0);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After addQuoteToken(10440325087293679399519637, 3, 0)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;
        _liquidationPoolHandler.removeQuoteToken(203523152199607539024211010303008326965431455389194686949299, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639932);

        ( , quote, collateral, lps, , exchangeRate) = _poolInfo.bucketInfo(address(_pool), 2570);
        console.log("After removeQuoteToken(203523152199607539024211010303008326965431455389194686949299, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639932)");
        console.log("============");
        console.log("Quote Tokens -->", quote);
        console.log("Collateral Tokens -->", collateral);
        console.log("Lps -->", lps);
        console.log("Exchange Rate-->", exchangeRate);
        console.log("============");
        require(previousExchangeRate == exchangeRate, "Incorrect exchange rate");
        previousExchangeRate = exchangeRate;

        invariant_exchangeRate_R3_R4_R5_R6();
    }
}