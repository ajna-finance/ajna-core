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

        // check invariants hold true
        invariant_quoteTokenBalance_QT1();
    }

    function test_arithmetic_overflow() external {
        _liquidationPoolHandler.kickAuction(128942392769655840156268259377571235707684499808935108685525899532745, 9654010200996517229486923829624352823010316518405842367464881, 135622574118732106350824249104903);
        _liquidationPoolHandler.addQuoteToken(3487, 871, 1654);

        // check invariants hold true
        invariant_quoteTokenBalance_QT1();
    }

    function test_bucket_take_lps_bug() public {
        _liquidationPoolHandler.removeQuoteToken(7033457611004217223271238592369692530886316746601644, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationPoolHandler.addQuoteToken(1, 20033186019073, 1);
        _liquidationPoolHandler.bucketTake(0, 0, false, 2876997751);

        invariant_Lps_B1();
    }

    function test_interest_rate_bug() public {
        _liquidationPoolHandler.bucketTake(18065045387666484532028539614323078235438354477798625297386607289, 14629545458306, true, 1738460279262663206365845078188769);

        invariant_interest_rate_I1();
    }
}