// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ReserveERC721PoolInvariants } from "../../invariants/ERC721Pool/ReserveERC721PoolInvariants.t.sol";

contract RegressionTestReserveERC721Pool is ReserveERC721PoolInvariants { 
    function setUp() public override { 
        super.setUp();
    }

    function test_regression_arithmetic_overflow() external {
        _reserveERC721PoolHandler.takeAuction(92769370221611464325146803683156031925894702957583423527130966373453460, 1, 0);
        _reserveERC721PoolHandler.bucketTake(946681003919344525962988194461032341334826191474892406752540091475466732435, 115792089237316195423570985008687907853269984665640564039457584007913129639932, false, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _reserveERC721PoolHandler.pledgeCollateral(110349606679412691172957834289542550319383271247755660854362242977991410022199, 14546335109189328620313099);
        _reserveERC721PoolHandler.transferLps(7966696646007323951141060300, 1382000000000000000000, 14900528365458273129607000593, 18640181410506725405733865833824324648215384731482764797343269315726072943072);
        _reserveERC721PoolHandler.drawDebt(107285134268485238885825019843523094619958942033886535891203702184170570337916, 1008096043491529984);
        _reserveERC721PoolHandler.bucketTake(0, 1177, true, 698469034333322743784201375142656365110267526102696086972);
    }

    function test_regression_CT4_1() external {
        _reserveERC721PoolHandler.takeAuction(12081493032056306060837676478, 17112687674220907985671783478, 156086231189053706777082702350822415);
        _reserveERC721PoolHandler.bucketTake(2751921977392940485992662421841654754784896, 0, false, 74485124857288266409128701303509478629061526535257123857425657075);
        _reserveERC721PoolHandler.settleAuction(28196, 350662677223461989004552717744870304232548804666, 36769010933687420804596073);
        _reserveERC721PoolHandler.bucketTake(83908, 44550000000000000, false, 20000000000000000000000312288);

        invariant_CT4();
    }

    function test_regression_CT4_2() external {
        _reserveERC721PoolHandler.drawDebt(0, 3);
        _reserveERC721PoolHandler.addQuoteToken(110722066303045195479382873847756822996893052638415787811385263327686542008, 2595467720355805256177, 44804955487212801727231000414524018578);
        _reserveERC721PoolHandler.moveQuoteToken(43739203749898257092507987414800731, 45406433371816793948702636, 12374955966170596958032853251, 781);
        _reserveERC721PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1, 61586, 11856671202668897206441691542968611274078091901056358965450125);
        _reserveERC721PoolHandler.pledgeCollateral(349513993113487194057973, 362746040314235282459383005583790844);
        _reserveERC721PoolHandler.settleAuction(3, 2, 3);

        invariant_CT4();
    }
}
