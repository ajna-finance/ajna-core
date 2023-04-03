// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BasicERC20PoolInvariants } from "../../invariants/ERC20Pool/BasicERC20PoolInvariants.t.sol";

contract RegressionTestBasicERC20Pool is BasicERC20PoolInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_Underflow_1() external {
        _basicERC20PoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000);

        // check invariants hold true
        invariant_quoteTokenBalance_QT1();
    }

    function test_regression_exchange_rate_1() external {
        _basicERC20PoolHandler.addQuoteToken(999999999844396154169639088436193915956854451, 6879, 2809);
        _basicERC20PoolHandler.addCollateral(2, 36429077592820139327392187131, 202214962129783771592);
        _basicERC20PoolHandler.removeCollateral(1, 2296695924278944779257290397234298756, 10180568736759156593834642286260647915348262280903719122483474452532722106636);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8(); 
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_2() external {
        _basicERC20PoolHandler.addQuoteToken(211670885988646987334214990781526025942, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 6894274025938223490357894120267612065037086600750070030707794233);
        _basicERC20PoolHandler.addCollateral(117281, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 12612911637698029036253737442696522, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _basicERC20PoolHandler.removeCollateral(1, 1e36, 2570);
        _basicERC20PoolHandler.removeQuoteToken(1, 1e36, 2570);
        _basicERC20PoolHandler.removeCollateral(2, 1e36, 2570);
        _basicERC20PoolHandler.removeQuoteToken(2, 1e36, 2570);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test will fail when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_3() external {
        _basicERC20PoolHandler.addQuoteToken(2842, 304, 2468594405605444095992);
        _basicERC20PoolHandler.addCollateral(0, 1, 3);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _basicERC20PoolHandler.removeCollateral(0, 1, 3);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 1, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_4() external {
        _basicERC20PoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 587135207579305083672251579076072787077);
        _basicERC20PoolHandler.removeCollateral(712291886391993882782748602346033231793324080118979183300958, 673221151277569661050873992210938589, 999999997387885196930781163353866909746906615);
        _basicERC20PoolHandler.removeCollateral(4434852123445331038838, 92373980881732279172264, 16357203);
        _basicERC20PoolHandler.addQuoteToken(6532756, 16338, 2488340072929715905208495398161339232954907500634);
        _basicERC20PoolHandler.removeCollateral(934473801621702106582064701468475360, 999999998588451849650292641565069384488310108, 2726105246641027837873401505120164058057757115396);
        _basicERC20PoolHandler.addQuoteToken(0, 3272, 688437777000000000);
        _basicERC20PoolHandler.removeQuoteToken(36653992905059663682442427, 3272, 688437777000000000);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 1, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_5() external {
        _basicERC20PoolHandler.drawDebt(1156, 1686);
        
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addQuoteToken(711, 2161, 2012); 

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();   
    }

    // test was failing when actors = 1, buckets = [2570]
    function test_regression_exchange_rate_6() external {
        _basicERC20PoolHandler.addCollateral(999999999000000000000000081002632733724231666, 999999999243662968633890481597751057821356823, 1827379824097500721086759239664926559);
        _basicERC20PoolHandler.addQuoteToken(108018811574020559, 3, 617501271956497833026154369680502407518122199901237699791086943);
        _basicERC20PoolHandler.addCollateral(95036573736725249741129171676163161793295193492729984020, 5009341426566798172861627799, 2);
        _basicERC20PoolHandler.removeCollateral(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 5814100241);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    // Fixed with commit -> https://github.com/ajna-finance/contracts/pull/613/commits/f106f0f7c96c1662325bdb5151fd745544e6dce0 
    function test_regression_exchange_rate_7() external {
        _basicERC20PoolHandler.addCollateral(999999999249784004703856120761629301735818638, 15200, 2324618456838396048595845067026807532884041462750983926777912015561);
        _basicERC20PoolHandler.addQuoteToken(0, 2, 60971449684543878);
        _basicERC20PoolHandler.addCollateral(0, 648001392760875820320327007315181208349883976901103343226563974622543668416, 38134304133913510899173609232567613);
        _basicERC20PoolHandler.removeCollateral(0, 1290407354289435191451647900348688457414638662069174249777953, 125945131546441554612275631955778759442752893948134984981883798);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_8() external {
        _basicERC20PoolHandler.drawDebt(0, 10430);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addCollateral(86808428701435509359888008280539191473421, 35, 89260656586096811497271673595050);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_9() external {
        _basicERC20PoolHandler.addQuoteToken(179828875014111774829603408358905079754763388655646874, 39999923045226513122629818514849844245682430, 12649859691422584279364490330583846883);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addCollateral(472, 2100, 11836);
        
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.pledgeCollateral(7289, 8216);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_fenwick_deposit_1() external {
        _basicERC20PoolHandler.addQuoteToken(60321923115154876306287876901335341390357684483818363750, 2, 0);
        _basicERC20PoolHandler.repayDebt(58055409653178, 2);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_fenwick_deposit_2() external {
        _basicERC20PoolHandler.addQuoteToken(2, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2146593659305556796718319988088528090847459411703413796483450011160);
        _basicERC20PoolHandler.addCollateral(16885296866566559818671993560820380984757301691657405859955072474117, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 7764878663795446754367);
        _basicERC20PoolHandler.removeCollateral(999999997000000000000000000000000000000756426, 7366, 4723);
        _basicERC20PoolHandler.addQuoteToken(5673, 8294, 11316);
        _basicERC20PoolHandler.moveQuoteToken(919997327910338711763724656061931477, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 3933155006830995444792575696);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_fenwick_deposit_3() external {
        _basicERC20PoolHandler.pullCollateral(64217420783566726909348297066823202824683000164554083, 651944294303386510182040138076901697073);
        _basicERC20PoolHandler.removeQuoteToken(172614182, 2999, 725);
        _basicERC20PoolHandler.addQuoteToken(52646814442098488638488433580148374391481084017027388775686120188766352301, 5021, 16410);
        _basicERC20PoolHandler.moveQuoteToken(2, 1, 3, 11769823729834119405789456482320067049929344685247053661486);
        _basicERC20PoolHandler.moveQuoteToken(1, 2833727997543655292227288672285470, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 7962018528962356191057551420322350);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_fenwick_deposit_4() external {
        _basicERC20PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 2, 1267);
        _basicERC20PoolHandler.pledgeCollateral(1700127358962530, 0);
        _basicERC20PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 2);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_fenwick_deposit_5() external {
        _basicERC20PoolHandler.repayDebt(281, 1502);
        _basicERC20PoolHandler.addCollateral(5529, 1090, 5431);
        _basicERC20PoolHandler.pullCollateral(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_fenwick_deposit_6() external {
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _basicERC20PoolHandler.addQuoteToken(1000000000000000, 19319, 308);
        _basicERC20PoolHandler.pullCollateral(4218, 4175);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_fenwick_prefixSum_1() external {
        _basicERC20PoolHandler.addQuoteToken(5851, 999999999999999999999999999999000087, 1938);
        _basicERC20PoolHandler.addCollateral(135454721201807374404103595951250949, 172411742705067521609848985260337891060745418778973, 3);
        _basicERC20PoolHandler.pledgeCollateral(2, 185978674898652363737734333012844452989790885966093618883814734917759475);
        _basicERC20PoolHandler.moveQuoteToken(976453319, 2825105681459470134743617749102858205411027017903767825282483319, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 145056082857394229503325854914710239303685607721150607568547620026);

        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_fenwick_index_1() external {
        _basicERC20PoolHandler.addQuoteToken(3056, 915, 1594);
        _basicERC20PoolHandler.pullCollateral(274694202801760577094218807, 1);
        _basicERC20PoolHandler.addQuoteToken(1088, 3407, 3555);
        _basicERC20PoolHandler.addCollateral(1557, 13472, 15303);
        _basicERC20PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639933, 40692552539277917058910464963);
        _basicERC20PoolHandler.pullCollateral(1131485716992204156645660898919702, 30971207810832254868222941038507448);
        _basicERC20PoolHandler.removeCollateral(27428712668923640148402320299830959263828759458932482391338247903954077260349, 1136, 3944);
        _basicERC20PoolHandler.moveQuoteToken(9746204317995874651524496302383356801834068305156642323380998069579800880, 1723109236200550802774859945265636287, 3213180193920898024510373220802133410941904907229061207617048152428481, 0);

        invariant_fenwick_bucket_index_F3();
    }

    function test_regression_transferLps_1() external {
        _basicERC20PoolHandler.transferLps(0, 1, 200, 2570);

        invariant_Bucket_deposit_time_B5_B6_B7();
    }

    function test_regression_transferLps_2() external {
        _basicERC20PoolHandler.transferLps(37233021465377552730514154972012012669272, 45957263314208417069590941186697869465410494677646946058359554, 405, 89727160292150007024940);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_transferLps_3() external {
        _basicERC20PoolHandler.transferLps(1795, 6198, 3110, 11449);

        invariant_Bucket_deposit_time_B5_B6_B7();
        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_pull_collateral_when_encumbered_greater_than_pledged() external {
        _basicERC20PoolHandler.drawDebt(1535776046383997344779595, 5191646246012456798576386242824793107669233);
        _basicERC20PoolHandler.transferLps(17293, 19210, 227780, 999999999999999999999999999999999999999999997);
        _basicERC20PoolHandler.removeQuoteToken(0, 0, 2);
        _basicERC20PoolHandler.pullCollateral(115, 149220);
    }

    function test_regression_incorrect_zero_deposit_buckets_1() external {
        _basicERC20PoolHandler.repayDebt(15119, 6786);
        _basicERC20PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1578322581132549441186648538841, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        invariant_fenwick_prefixSumIndex_F4();
    }

    function test_regression_fenwick_index_2() external {
        uint256 depositAt2570 = 570036521745120847917211;
        uint256 depositAt2571 = _basicERC20PoolHandler.constrictToRange(2578324552477056269186646552413, 1e6, 1e28);
        uint256 depositAt2572 = _basicERC20PoolHandler.constrictToRange(1212, 1e6, 1e28);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2570, 2570);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2571, 2571);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2572, 2572);
        assertEq(_pool.depositIndex(depositAt2570), 2570);
        assertEq(_pool.depositIndex(depositAt2570 + depositAt2571), 2571);
        assertEq(_pool.depositIndex(depositAt2570 + depositAt2571 + depositAt2572), 2572);
    }

    function test_regression_collateralBalance_CT1_CT7() external {
        _basicERC20PoolHandler.pullCollateral(2, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _basicERC20PoolHandler.repayDebt(2712912126128356234217, 251720382485531952743041849848);
        _basicERC20PoolHandler.addQuoteToken(253022590763482364356576159, 999999999999999273028438503236995092261608400, 712808213364422679443324012750);
        _basicERC20PoolHandler.removeQuoteToken(121890555084215923472733925382, 0, 3);

        invariant_collateralBalance_CT1_CT7();
    }

    // TODO: poolBalance + poolDebt >= _pool.depositSize fails by 1 unit of WAD (1.000115588871659711 >= 1.000115588871659712)
    function test_regression_invariant_quoteTokenBalance_QT1() external {
        _basicERC20PoolHandler.pledgeCollateral(47134563260349377955683144555119028889734284095914219439962386869, 2323610696462098);
        _basicERC20PoolHandler.repayDebt(1, 2);
        _basicERC20PoolHandler.removeCollateral(200953640940463935290718680397023889633667961549, 2481, 3);
        _basicERC20PoolHandler.moveQuoteToken(695230664226651211376892782958299806602599384639648126900062519785408512, 1000115588871659705, 22812, 1955101796782211288928817909562);
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639932, 103);

        invariant_quoteTokenBalance_QT1();
    }

    function test_regression_fenwick_deposit_8() external {
        _basicERC20PoolHandler.drawDebt(226719918559509764892175185709, 228676957600917178383525685311331);

        invariant_fenwick_depositAtIndex_F1();
    }
}
