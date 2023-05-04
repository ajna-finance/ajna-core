// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BasicERC20PoolInvariants } from "../../invariants/ERC20Pool/BasicERC20PoolInvariants.t.sol";

contract RegressionTestBasicERC20Pool is BasicERC20PoolInvariants { 

    function setUp() public override {
        // failures reproduced with 3 active buckets
        vm.setEnv("NO_OF_BUCKETS", "3");
        super.setUp();
    }

    function test_regression_Underflow_1() external {
        _basicERC20PoolHandler.addQuoteToken(14227, 5211, 3600000000000000000000, 0);

        // check invariants hold true
        invariant_quote_QT1();
    }

    function test_regression_exchange_rate_1() external {
        _basicERC20PoolHandler.addQuoteToken(999999999844396154169639088436193915956854451, 6879, 2809, 0);
        _basicERC20PoolHandler.addCollateral(2, 36429077592820139327392187131, 202214962129783771592, 0);
        _basicERC20PoolHandler.removeCollateral(1, 2296695924278944779257290397234298756, 10180568736759156593834642286260647915348262280903719122483474452532722106636, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8(); 
    }

    function test_regression_exchange_rate_2() external {
        _basicERC20PoolHandler.addQuoteToken(211670885988646987334214990781526025942, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 6894274025938223490357894120267612065037086600750070030707794233, 0);
        _basicERC20PoolHandler.addCollateral(117281, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2, 0);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 12612911637698029036253737442696522, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _basicERC20PoolHandler.removeCollateral(1, 1e36, 2570, 0);
        _basicERC20PoolHandler.removeQuoteToken(1, 1e36, 2570, 0);
        _basicERC20PoolHandler.removeCollateral(2, 1e36, 2570, 0);
        _basicERC20PoolHandler.removeQuoteToken(2, 1e36, 2570, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_3() external {
        _basicERC20PoolHandler.addQuoteToken(2842, 304, 2468594405605444095992, 0);
        _basicERC20PoolHandler.addCollateral(0, 1, 3, 0);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _basicERC20PoolHandler.removeCollateral(0, 1, 3, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_4() external {
        _basicERC20PoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 587135207579305083672251579076072787077, 0);
        _basicERC20PoolHandler.removeCollateral(712291886391993882782748602346033231793324080118979183300958, 673221151277569661050873992210938589, 999999997387885196930781163353866909746906615, 0);
        _basicERC20PoolHandler.removeCollateral(4434852123445331038838, 92373980881732279172264, 16357203, 0);
        _basicERC20PoolHandler.addQuoteToken(6532756, 16338, 2488340072929715905208495398161339232954907500634, 0);
        _basicERC20PoolHandler.removeCollateral(934473801621702106582064701468475360, 999999998588451849650292641565069384488310108, 2726105246641027837873401505120164058057757115396, 0);
        _basicERC20PoolHandler.addQuoteToken(0, 3272, 688437777000000000, 0);
        _basicERC20PoolHandler.removeQuoteToken(36653992905059663682442427, 3272, 688437777000000000, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_5() external {
        _basicERC20PoolHandler.drawDebt(1156, 1686, 0);
        
        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addQuoteToken(711, 2161, 2012, 0); 

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();   
    }

    function test_regression_exchange_rate_6() external {
        _basicERC20PoolHandler.addCollateral(999999999000000000000000081002632733724231666, 999999999243662968633890481597751057821356823, 1827379824097500721086759239664926559, 0);
        _basicERC20PoolHandler.addQuoteToken(108018811574020559, 3, 617501271956497833026154369680502407518122199901237699791086943, 0);
        _basicERC20PoolHandler.addCollateral(95036573736725249741129171676163161793295193492729984020, 5009341426566798172861627799, 2, 0);
        _basicERC20PoolHandler.removeCollateral(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 5814100241, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    // Fixed with commit -> https://github.com/ajna-finance/contracts/pull/613/commits/f106f0f7c96c1662325bdb5151fd745544e6dce0 
    function test_regression_exchange_rate_7() external {
        _basicERC20PoolHandler.addCollateral(999999999249784004703856120761629301735818638, 15200, 2324618456838396048595845067026807532884041462750983926777912015561, 0);
        _basicERC20PoolHandler.addQuoteToken(0, 2, 60971449684543878, 0);
        _basicERC20PoolHandler.addCollateral(0, 648001392760875820320327007315181208349883976901103343226563974622543668416, 38134304133913510899173609232567613, 0);
        _basicERC20PoolHandler.removeCollateral(0, 1290407354289435191451647900348688457414638662069174249777953, 125945131546441554612275631955778759442752893948134984981883798, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    // test was failing when actors = 10, buckets = [2570], maxAmount = 1e36
    function test_regression_exchange_rate_8() external {
        _basicERC20PoolHandler.drawDebt(0, 10430, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addCollateral(86808428701435509359888008280539191473421, 35, 89260656586096811497271673595050, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_exchange_rate_9() external {
        _basicERC20PoolHandler.addQuoteToken(179828875014111774829603408358905079754763388655646874, 39999923045226513122629818514849844245682430, 12649859691422584279364490330583846883, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.addCollateral(472, 2100, 11836, 0);
        
        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
        _basicERC20PoolHandler.pledgeCollateral(7289, 8216, 0);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_fenwick_deposit_1() external {
        _basicERC20PoolHandler.addQuoteToken(60321923115154876306287876901335341390357684483818363750, 2, 0, 0);
        _basicERC20PoolHandler.repayDebt(58055409653178, 2, 0);

        invariant_fenwick_F1();
    }

    function test_regression_fenwick_deposit_2() external {
        _basicERC20PoolHandler.addQuoteToken(2, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2146593659305556796718319988088528090847459411703413796483450011160, 0);
        _basicERC20PoolHandler.addCollateral(16885296866566559818671993560820380984757301691657405859955072474117, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 7764878663795446754367, 0);
        _basicERC20PoolHandler.removeCollateral(999999997000000000000000000000000000000756426, 7366, 4723, 0);
        _basicERC20PoolHandler.addQuoteToken(5673, 8294, 11316, 0);
        _basicERC20PoolHandler.moveQuoteToken(919997327910338711763724656061931477, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 3933155006830995444792575696, 0);

        invariant_fenwick_F1();
    }

    function test_regression_fenwick_deposit_3() external {
        _basicERC20PoolHandler.pullCollateral(64217420783566726909348297066823202824683000164554083, 651944294303386510182040138076901697073, 0);
        _basicERC20PoolHandler.removeQuoteToken(172614182, 2999, 725, 0);
        _basicERC20PoolHandler.addQuoteToken(52646814442098488638488433580148374391481084017027388775686120188766352301, 5021, 16410, 0);
        _basicERC20PoolHandler.moveQuoteToken(2, 1, 3, 11769823729834119405789456482320067049929344685247053661486, 0);
        _basicERC20PoolHandler.moveQuoteToken(1, 2833727997543655292227288672285470, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 7962018528962356191057551420322350, 0);

        invariant_fenwick_F1();
        invariant_fenwick_F2();
    }

    function test_regression_fenwick_deposit_4() external {
        _basicERC20PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 2, 1267, 0);
        _basicERC20PoolHandler.pledgeCollateral(1700127358962530, 0, 0);
        _basicERC20PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 2, 0);

        invariant_fenwick_F1();
        invariant_fenwick_F2();
    }

    function test_regression_fenwick_deposit_5() external {
        _basicERC20PoolHandler.repayDebt(281, 1502, 0);
        _basicERC20PoolHandler.addCollateral(5529, 1090, 5431, 0);
        _basicERC20PoolHandler.pullCollateral(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);

        invariant_fenwick_F1();
        invariant_fenwick_F2();
    }

    function test_regression_fenwick_deposit_6() external {
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639933, 0, 0);
        _basicERC20PoolHandler.addQuoteToken(1000000000000000, 19319, 308, 0);
        _basicERC20PoolHandler.pullCollateral(4218, 4175, 0);

        invariant_fenwick_F1();
    }

    function test_regression_fenwick_prefixSum_1() external {
        _basicERC20PoolHandler.addQuoteToken(5851, 999999999999999999999999999999000087, 1938, 0);
        _basicERC20PoolHandler.addCollateral(135454721201807374404103595951250949, 172411742705067521609848985260337891060745418778973, 3, 0);
        _basicERC20PoolHandler.pledgeCollateral(2, 185978674898652363737734333012844452989790885966093618883814734917759475, 0);
        _basicERC20PoolHandler.moveQuoteToken(976453319, 2825105681459470134743617749102858205411027017903767825282483319, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 145056082857394229503325854914710239303685607721150607568547620026, 0);

        invariant_fenwick_F2();
    }

    function test_regression_fenwick_index_1() external {
        _basicERC20PoolHandler.addQuoteToken(3056, 915, 1594, 0);
        _basicERC20PoolHandler.pullCollateral(274694202801760577094218807, 1, 0);
        _basicERC20PoolHandler.addQuoteToken(1088, 3407, 3555, 0);
        _basicERC20PoolHandler.addCollateral(1557, 13472, 15303, 0);
        _basicERC20PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639933, 40692552539277917058910464963, 0);
        _basicERC20PoolHandler.pullCollateral(1131485716992204156645660898919702, 30971207810832254868222941038507448, 0);
        _basicERC20PoolHandler.removeCollateral(27428712668923640148402320299830959263828759458932482391338247903954077260349, 1136, 3944, 0);
        _basicERC20PoolHandler.moveQuoteToken(9746204317995874651524496302383356801834068305156642323380998069579800880, 1723109236200550802774859945265636287, 3213180193920898024510373220802133410941904907229061207617048152428481, 0, 0);

        invariant_fenwick_F3();
    }

    function test_regression_transferLps_1() external {
        _basicERC20PoolHandler.transferLps(0, 1, 200, 2570, 0);

        invariant_bucket_B5_B6_B7();
    }

    function test_regression_transferLps_2() external {
        _basicERC20PoolHandler.transferLps(37233021465377552730514154972012012669272, 45957263314208417069590941186697869465410494677646946058359554, 405, 89727160292150007024940, 0);

        invariant_fenwick_F1();
        invariant_fenwick_F2();
    }

    function test_regression_transferLps_3() external {
        _basicERC20PoolHandler.transferLps(1795, 6198, 3110, 11449, 0);

        invariant_bucket_B5_B6_B7();
        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_pull_collateral_when_encumbered_greater_than_pledged() external {
        _basicERC20PoolHandler.drawDebt(1535776046383997344779595, 5191646246012456798576386242824793107669233, 0);
        _basicERC20PoolHandler.transferLps(17293, 19210, 227780, 999999999999999999999999999999999999999999997, 0);
        _basicERC20PoolHandler.removeQuoteToken(0, 0, 2, 0);
        _basicERC20PoolHandler.pullCollateral(115, 149220, 0);
    }

    function test_regression_incorrect_zero_deposit_buckets_1() external {
        _basicERC20PoolHandler.repayDebt(15119, 6786, 0);
        _basicERC20PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1578322581132549441186648538841, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        invariant_fenwick_F4();
    }

    function test_regression_fenwick_index_2() external {
        uint256 depositAt2570 = 570036521745120847917211;
        uint256 depositAt2571 = _basicERC20PoolHandler.constrictToRange(2578324552477056269186646552413, 1e6, 1e28);
        uint256 depositAt2572 = _basicERC20PoolHandler.constrictToRange(1212, 1e6, 1e28);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2570, 2570, 0);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2571, 2571, 0);
        _basicERC20PoolHandler.addQuoteToken(1, depositAt2572, 2572, 0);
        assertEq(_pool.depositIndex(depositAt2570), 2570);
        assertEq(_pool.depositIndex(depositAt2570 + depositAt2571), 2571);
        assertEq(_pool.depositIndex(depositAt2570 + depositAt2571 + depositAt2572), 2572);
    }

    function test_regression_collateralBalance_CT1_CT7() external {
        _basicERC20PoolHandler.pullCollateral(2, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _basicERC20PoolHandler.repayDebt(2712912126128356234217, 251720382485531952743041849848, 0);
        _basicERC20PoolHandler.addQuoteToken(253022590763482364356576159, 999999999999999273028438503236995092261608400, 712808213364422679443324012750, 0);
        _basicERC20PoolHandler.removeQuoteToken(121890555084215923472733925382, 0, 3, 0);

        invariant_collateral_CT1_CT7();
    }

    function test_regression_invariant_quote_QT1() external {
        _basicERC20PoolHandler.pledgeCollateral(47134563260349377955683144555119028889734284095914219439962386869, 2323610696462098, 0);
        _basicERC20PoolHandler.repayDebt(1, 2, 0);
        _basicERC20PoolHandler.removeCollateral(200953640940463935290718680397023889633667961549, 2481, 3, 0);
        _basicERC20PoolHandler.moveQuoteToken(695230664226651211376892782958299806602599384639648126900062519785408512, 1000115588871659705, 22812, 1955101796782211288928817909562, 0);
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639932, 103, 0);

        invariant_quote_QT1();
    }

    function test_regression_fenwick_deposit_8() external {
        _basicERC20PoolHandler.drawDebt(226719918559509764892175185709, 228676957600917178383525685311331, 0);

        invariant_fenwick_F1();
    }
}

contract RegressionTestBasicWith10BucketsERC20Pool is BasicERC20PoolInvariants { 

    function setUp() public override {
        // failures reproduced with 10 active buckets
        vm.setEnv("NO_OF_BUCKETS", "10");
        super.setUp();
    }

    function test_regression_10_buckets_CT1_CT7() external {
        _basicERC20PoolHandler.transferLps(19078983173372942890417748018722377435183373748499322243247546781962442185, 1, 4391160926701505967325397265181132015972183318, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _basicERC20PoolHandler.transferLps(270997981512080867078682324706934707221242205867293069, 7864, 3651, 3166, 0);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639934, 3635889843872116931397407365290249, 23021664368573277020436789355588670855277006870, 0);
        _basicERC20PoolHandler.drawDebt(268, 181582671641966396883195899256, 0);
        _basicERC20PoolHandler.pullCollateral(1227515749685864358137095510127654245525351748189001609, 3818828157139154512, 0);
        _basicERC20PoolHandler.repayDebt(3042268540744255610589705434124741203255613373849507141, 0, 0);
        _basicERC20PoolHandler.pullCollateral(6802, 6279, 0);
        _basicERC20PoolHandler.addQuoteToken(2, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 127935328935713960735227335223838560292175, 0);
        _basicERC20PoolHandler.pullCollateral(2930, 36104017659498278503100244564470932293, 0);
        _basicERC20PoolHandler.addQuoteToken(1681414255953633817920736095340458401, 2, 331564777626112378272493610241099454882166422929878794700, 0);
        _basicERC20PoolHandler.addCollateral(1834, 38146939, 39424949171633211915315804, 0);
        _basicERC20PoolHandler.addQuoteToken(8640216505061661298, 13070, 10696, 0);
        _basicERC20PoolHandler.pullCollateral(962704044, 8898752, 0);
        _basicERC20PoolHandler.moveQuoteToken(34331296, 236168072844073492133156025194, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 19256400511825415508859240250358, 0);
        _basicERC20PoolHandler.transferLps(2, 1183061996845258949, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 2, 0 );
        _basicERC20PoolHandler.drawDebt(2169832191680919598423992113933409675947, 459159100237615494082512466719091280519979494228, 0 );
        _basicERC20PoolHandler.pledgeCollateral(363165343283932793766391798512, 14747, 0 );
        _basicERC20PoolHandler.removeCollateral(3985, 1824, 6960, 0);
        _basicERC20PoolHandler.addCollateral(1650938994639952252010012965502, 7253, 7574, 0);
        _basicERC20PoolHandler.transferLps(190195262656118760688724739, 999999999999999999999999999999999999999997115, 1248306590932896398273554030427, 6130, 0);
        _basicERC20PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 8113004849018889317737081296151463737388429, 0);
        _basicERC20PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0 );
        _basicERC20PoolHandler.moveQuoteToken(3, 2, 10960996744849996375050327179144415056797335841576787, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _basicERC20PoolHandler.transferLps(1, 743324445647492969999445842202717517856825, 1214649867011363567867599949068071550706, 239704513237, 0);
        _basicERC20PoolHandler.moveQuoteToken(78781837290735535753552291770891423860043710162602546000110480894858317836924, 993620562130177991745562150, 50000000000000000, 7110950, 0);
        _basicERC20PoolHandler.removeQuoteToken(3201781718151524032696177608091, 2788940717158963266260644637275, 1001719209787209063137009778273, 0);
        _basicERC20PoolHandler.removeCollateral(1481112300711317586348171215820373858161462484006514, 168870288186037165317237437722657252078900747583218061139236575915, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);

        invariant_collateral_CT1_CT7();
    }

    function test_regression_10_buckets_exchange_rate() external {
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 26963870279491362, 3601254755561650650360315550225832165809937215074736, 3);
        _basicERC20PoolHandler.pledgeCollateral(1, 40937702662375620098041553673274794675563238421444364181, 1806299292781392482814941608217714);
        _basicERC20PoolHandler.transferLps(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 26);
        _basicERC20PoolHandler.addQuoteToken(9086412395094638972007390189682, 8017988708875371050349109733764, 266534290007540556135436437121220, 787972529567086468575527683806);
        _basicERC20PoolHandler.drawDebt(3, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _basicERC20PoolHandler.repayDebt(607418644361740467859860, 3596613749317836791599288999578, 126973386001551158);
        _basicERC20PoolHandler.addCollateral(17961069541001395512, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 81216080311786972267543281713646, 36083189127252982075046);
        _basicERC20PoolHandler.repayDebt(879265086388357000017570476021613397720047, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _basicERC20PoolHandler.addQuoteToken(2074760358537425509206115888966642, 1000052509226306402, 1000216183594279728, 3626850572378510482520934156110);
        _basicERC20PoolHandler.addQuoteToken(7237766368913837526279800803850926, 2318473227034367386476981536426, 3397753274562712559962219817121, 3497677980587);
        _basicERC20PoolHandler.removeCollateral(2, 1, 22225753124285528776218150577139424248166623103654, 2);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_10_buckets_exchange_rate_2() external {
        _basicERC20PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 17818855137382186474378203925478798087362081064669755109660);
        _basicERC20PoolHandler.addCollateral(964764110637273391149124793103, 936928192160217426868916642063, 12955560945978902771121849, 2701606087371011725063830630393);
        _basicERC20PoolHandler.removeCollateral(1000233017073419014, 493168574173516667837628028479, 1000343878875971862, 1000456862367981607271282879183);
        _basicERC20PoolHandler.removeCollateral(688160553555940795759938325497944173800517078344861811099552611334630134, 5520300724063246494671071725488, 3164757341640618278, 2566067341560472579524138938086);
        _basicERC20PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 41316723850064749855432968190893852, 1704156508, 1);
        _basicERC20PoolHandler.moveQuoteToken(2338402619729444670366505962819150530378316367411261236887124071421, 1002224041809029153, 2834327347641428773029188, 1000413425240358656, 746591544249884746466149963933);
        _basicERC20PoolHandler.removeCollateral(1388044745591696560869746190501689966701146364533, 1444911079603055211427832649212708779095906518345500, 146224647513095394826, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _basicERC20PoolHandler.removeQuoteToken(3, 0, 14682057797145934596306613629765202023028155589188791234994295689059743703775, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _basicERC20PoolHandler.addCollateral(1573875203397848960670186019073248854602426094673, 2504217569840181286227620309719896586961536673187089015258250231162, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 2);
        _basicERC20PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 25673965657298153291575883442400894202624273572440854514727495, 1606415152236964885598131062907211614020217776051558);

        invariant_rate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_10_buckets_F4() external {
        _basicERC20PoolHandler.moveQuoteToken(13234449535566095703531866953212457366696209938115942596093570715251, 60374778675415672380560, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 3, 171308252132017301932164837198243853648547295794439243930145939017);
        _basicERC20PoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639935, 6335515217046864691, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _basicERC20PoolHandler.pledgeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _basicERC20PoolHandler.addCollateral(6296421660734538372623618614208786496541, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0, 1);
        _basicERC20PoolHandler.addCollateral(4518678283152371114, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 102774731127178500371069294026531481660623908768344624881339468320844617);
        _basicERC20PoolHandler.pledgeCollateral(787973584684501059282315698711, 2920151741518916367111665950222, 123224745043874830703997919895);
        _basicERC20PoolHandler.pullCollateral(1573681034138562592148446961981, 5395039744831658857563353458119, 999999999999999999976489190096550336802923519);
        _basicERC20PoolHandler.drawDebt(6394102097403381167740208256634, 1000018554440804369, 8672057495977214373296863722573852739162441602919679032972630);
        _basicERC20PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 140881254558364192728545623, 613322747455025846625942820);
        _basicERC20PoolHandler.drawDebt(714318606031963959460439666, 3840097364686600160570735710605, 1619253008376079830967680273);
        _basicERC20PoolHandler.repayDebt(1673798751, 5694842710945459528642451559494, 283670364632203665819796449);
        _basicERC20PoolHandler.pullCollateral(6440809887369074468946703546240400837213546534, 2703097808456042804242921317, 1280483304446323279875015625413976687208364448);
        _basicERC20PoolHandler.moveQuoteToken(2645907677966809348905615900887, 1000290596345984668, 8911595135731625941490882255952, 1000114004480165314, 999999999999999492047613175637745184412049525);
        _basicERC20PoolHandler.moveQuoteToken(17910056905799029767578947, 1864370690112038787667315417001207317411, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2, 749884739185720130);
        _basicERC20PoolHandler.pledgeCollateral(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2);
        _basicERC20PoolHandler.removeCollateral(29916223351185949468184326014674437876671, 4589, 52359455270961644929860673030618666251977951329658, 107072856710625989514364630708);
        _basicERC20PoolHandler.addQuoteToken(4993846574496845238683822200553772267301, 183, 29385267992611576362491572129746482837, 565);
        _basicERC20PoolHandler.addQuoteToken(1000000587241149501, 4116061719989634076062029107625, 6527585355223355420736028299386, 1000911055401543919);
        _basicERC20PoolHandler.transferLps(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1470588913202219277134099465404333890924499099636114330, 573574378967188764061305709654269675491379293416, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _basicERC20PoolHandler.addQuoteToken(6140956152846499655446977014073860862591380590488851, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 51907021185997214374267034487848418094701660362324021482169247216619633872456);
        _basicERC20PoolHandler.transferLps(261107, 7446853454023879126467395434433, 506895469181496737976330135, 7619952985071068405252281695334, 6154220663342048290252790511294);
        _basicERC20PoolHandler.drawDebt(688145878123546326583851366405289536070038389815044157043873133851063296, 7068007098627274874879419480, 7572765270442657913100320178565);
        _basicERC20PoolHandler.addCollateral(132849244362624672017210770, 160220481144050675301217580027770099132176677062347807, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 3);
        _basicERC20PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 4635788663783749582745368569664957810107889387318368328644395925, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 118711021541658804984564302878252);
        _basicERC20PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 8445096883336947366831914851854070736188169226787134562965608120754828249, 31702553921285986);
        _basicERC20PoolHandler.addCollateral(580611839910456831033498928563420669329295299872174796, 365592807736295354208641933456297478927564166157028915669712361006111378, 28139754781488792473550239412555, 16783034798732718173574507487472772049042281150918117690);
        _basicERC20PoolHandler.removeQuoteToken(3894404124500698217057152848884, 27478283841917457404525494988, 3021754851825746291696621607292, 1000001004962305311928772643717);
        _basicERC20PoolHandler.addQuoteToken(468, 2, 43724, 1152399744924008194743423951);
        _basicERC20PoolHandler.repayDebt(796770899347121193810335509368635, 788797746707273155957044869328, 325418985476243884442958426017);
        _basicERC20PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 7422932955149615012023501180176513465114, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _basicERC20PoolHandler.moveQuoteToken(11029268151348809599542295670992, 1674842588, 8836271060776756896119326907222, 688281732625303322675897722815970653485080269470846731021832930365693760, 535384403053933584684655656);
        _basicERC20PoolHandler.pledgeCollateral(1574478871504291917188801399286, 4544847225095148439060231333417, 130666618043756744430885952105154);
        _basicERC20PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 342447337001, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _basicERC20PoolHandler.transferLps(2, 0, 855521114601779757043497214366146208917380641227576, 6763612574518268953226767616, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _basicERC20PoolHandler.removeQuoteToken(4611889325915228483301526481319615, 38084, 42580832955904510762171045873877, 2636152856526958443712217183212702);
        _basicERC20PoolHandler.removeQuoteToken(29970599961641859108393123641560445894663409577582723877517332108011544504464, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 135, 13893178818345121509111186504303183497844);
        _basicERC20PoolHandler.pullCollateral(5769192817483987112721415532428, 16259463482118041401855347103, 1543735509442123611738770410327);
        _basicERC20PoolHandler.removeQuoteToken(1628467737203148079868996591494, 447404570018145143444980749, 4762130513423858141603250586289, 1885022364152755698804721861718);
        _basicERC20PoolHandler.addQuoteToken(0, 1, 69913830042719777813687647207537411321915157217229742561136685684500709, 3);
        _basicERC20PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 1);
        _basicERC20PoolHandler.pledgeCollateral(536503026894930742915592263726, 5958204048624414206720153263482, 981672851175865744292519803023);

        invariant_fenwick_F4();
    }
}

