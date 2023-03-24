// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationInvariants } from "../invariants/LiquidationInvariants.t.sol";

contract RegressionTestLiquidation is LiquidationInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_quote_token() external {
        _liquidationPoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639932);

        invariant_quoteTokenBalance_QT1();
    }

    function test_regression_arithmetic_overflow() external {
        _liquidationPoolHandler.kickAuction(128942392769655840156268259377571235707684499808935108685525899532745, 9654010200996517229486923829624352823010316518405842367464881, 135622574118732106350824249104903);
        _liquidationPoolHandler.addQuoteToken(3487, 871, 1654);

        invariant_quoteTokenBalance_QT1();
    }

    function test_regression_bucket_take_lps() external {
        _liquidationPoolHandler.removeQuoteToken(7033457611004217223271238592369692530886316746601644, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationPoolHandler.addQuoteToken(1, 20033186019073, 1);
        _liquidationPoolHandler.bucketTake(0, 0, false, 2876997751);

        invariant_Lps_B1_B4();
    }

    function test_regression_interest_rate() external {
        _liquidationPoolHandler.bucketTake(18065045387666484532028539614323078235438354477798625297386607289, 14629545458306, true, 1738460279262663206365845078188769);

        invariant_interest_rate_I1();
    }

    function test_regression_incorrect_no_of_borrowers() external {
        _liquidationPoolHandler.moveQuoteToken(18178450611611937161732340858718395124120481640398450530303803, 0, 93537843531612826457318744802930982491, 15596313608676556633725998020226886686244513);
        _liquidationPoolHandler.addCollateral(2208149704044082902772911545020934265, 340235628931125711729099234105522626267587665393753030264689924088, 2997844437211835697043096396926932785920355866486893005710984415271);
        _liquidationPoolHandler.moveQuoteToken(56944009718062971164908977784993293, 737882204379007468599822110965749781465, 1488100463155679769353095066686506252, 11960033727528802202227468733333727294);
        _liquidationPoolHandler.moveQuoteToken(47205392335275917691737183012282140599753693978176314740917, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 164043848691337333691028718232);
        _liquidationPoolHandler.kickAuction(184206711567329609153924955630229148705869686378631519380021040314, 78351, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationPoolHandler.kickAuction(3, 199726916764352560035199423206927461876998880387108455962754538835220966553, 3);
        _liquidationPoolHandler.removeQuoteToken(999999991828440064944955196599190431639924811, 2781559202773230142346489450532860130, 3000000005240421579956496007310960085855569344);
        _liquidationPoolHandler.pullCollateral(48768502867710912107594904694036421700, 275047566877984818806178837359260100);
        _liquidationPoolHandler.bucketTake(2, 115792089237316195423570985008687907853269984665640564039457584007913129639934, false, 8154570107391684241724530527782571978369827827856399749867491880);
        _liquidationPoolHandler.removeCollateral(43733538637150108518954934566131291302796656384802361118757432084573, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationPoolHandler.addQuoteToken(1, 2, 2);
        _liquidationPoolHandler.repayDebt(647805461526201272, 0);
        _liquidationPoolHandler.kickAuction(1019259585194528028904148545812353964867041444572537077023497678982801, 58796345025472936970320, 131319002678489819637546489086162345032717166507611595521);
        _liquidationPoolHandler.moveQuoteToken(2, 2, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _liquidationPoolHandler.moveQuoteToken(6164937621056362865643346803975636714, 4, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 315548939052682258);
        _liquidationPoolHandler.repayDebt(2987067394366841692658, 170206016570563384086766968869520628);
        _liquidationPoolHandler.pledgeCollateral(3558446182295495994762049031, 0);
        _liquidationPoolHandler.drawDebt(4525700839008283200312069904720925039, 3000000000753374912785563581177665475703155339);
        _liquidationPoolHandler.kickAuction(1, 3559779948348618822016735773117619950447774, 218801416747720);
        _liquidationPoolHandler.addQuoteToken(1469716416900282992357252011629715552, 13037214114647887147246343731476169800, 984665637618013480616943810604306792);
        _liquidationPoolHandler.pullCollateral(438961419917818200942534689247815826455600131, 64633474453314038763068322072915580384442279897841981);

        invariant_auctions_A3_A4();
    }

    // test was failing due to deposit time update even if kicker lp reward is 0.
    // resolved with PR: https://github.com/ajna-finance/contracts/pull/674
    function test_regression_bucket_deposit_time() external {
        _liquidationPoolHandler.kickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 2079356830967144967054363629631641573895835179323954988585146991431, 233005625580787863707944);
        _liquidationPoolHandler.bucketTake(21616, 1047473235778002354, false, 1062098588952039043823357);
        _liquidationPoolHandler.bucketTake(1673497622984405133414814181152, 94526073941076989987362055170246, false, 1462);

        invariant_Bucket_deposit_time_B5_B6_B7();
    }

    function test_regression_transfer_taker_lps_bucket_deposit_time() external {
        _liquidationPoolHandler.settleAuction(3637866246331061119113494215, 0, 6163485280468362485998190762304829820899757798629605592174295845105660515);
        _liquidationPoolHandler.transferLps(1610, 1000000000018496758270674070884, 168395863093969200027183125335, 2799494920515362640996160058);
        _liquidationPoolHandler.bucketTake(0, 10619296457595008969473693936299982020664977642271808785891719078511288, true, 1681500683437506364426133778273769573223975355182845498494263153646356302);

        invariant_Bucket_deposit_time_B5_B6_B7();
    }

    function test_regression_invariant_fenwick_depositAtIndex_F1() external {
        _liquidationPoolHandler.moveQuoteToken(4058, 2725046678043704335543997294802562, 16226066, 4284);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_depositKick() external {
        _liquidationPoolHandler.repayDebt(13418, 1160);
        _liquidationPoolHandler.kickWithDeposit(143703836638834364678, 470133688850921941603);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_invariant_incorrect_take_2() external {
        _liquidationPoolHandler.kickAuction(13452, 7198, 11328);
        _liquidationPoolHandler.takeAuction(6772, 18720, 6668);
        _liquidationPoolHandler.takeAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1666258487708695528254610529989951, 490873240291829575083322665078478117042861655783753);

        invariant_auction_taken_A6();
    }

    function test_regression_invariant_exchange_rate_bucket_take_1() external {
        _liquidationPoolHandler.bucketTake(183325863789657771277097526117552930424549597961930161, 34356261125910963886574176318851973698031483479551872234291832833800, true, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationPoolHandler.settleAuction(52219427432114632, 2227306986719506048214107429, 154672727048162052261854237547755782166311596848556350861587480089015671);
        _liquidationPoolHandler.removeQuoteToken(1999999999999999943017433781133248199223345020, 9070, 3519433319314336634208412746825);
        _liquidationPoolHandler.bucketTake(1, 115792089237316195423570985008687907853269984665640564039457584007913129639932, true, 115792089237316195423570985008687907853269984665640564039457584007913129639932);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_invariant_exchange_rate_bucket_take_2() external {
        _liquidationPoolHandler.moveQuoteToken(1676213736466301051643762607860, 1344, 2018879446031241805536743752775, 4101);
        _liquidationPoolHandler.settleAuction(186120755740, 2, 59199623628501455128);
        _liquidationPoolHandler.kickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 29888344);
        _liquidationPoolHandler.bucketTake(2, 259574184, true, 248534890472324170412180243783490514876275);

        invariant_exchangeRate_R1_R2_R3_R4_R5_R6_R7_R8();
    }

    function test_regression_quote_token_2() external {
        _liquidationPoolHandler.kickAuction(2, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationPoolHandler.kickAuction(416882035302092397436677640325827, 7379, 253058086367250264569525665396366);
        _liquidationPoolHandler.kickAuction(95740057146806695735694068330212313517380414204596464841344800376300745, 15462030827034, 17811087070659573835739283446817);
        _liquidationPoolHandler.drawDebt(91685640224888183606335500279, 3284161781338443742266950748717011);
        _liquidationPoolHandler.settleAuction(366366807138151363686, 2, 39227118695514892784493088788799944161631371060);

        invariant_quoteTokenBalance_QT1();
    }
    function test_regression_invariant_settle_F1_1() external {
        _liquidationPoolHandler.moveQuoteToken(950842133422927133350903963095785051820046356616, 12698007000117331615195178867, 28462469898, 3434419004419233872687259780980);
        _liquidationPoolHandler.kickAuction(5135, 1752, 6350);
        _liquidationPoolHandler.kickAuction(142699, 4496, 4356);
        _liquidationPoolHandler.moveQuoteToken(1173, 1445, 792325212, 447);
        _liquidationPoolHandler.settleAuction(18308, 3145, 947);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_invariant_settle_F1_2() external {
        _liquidationPoolHandler.kickAuction(2, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationPoolHandler.takeAuction(166780275301665520376512760721506, 1999999999999999999999999999999999999999997110, 2558901617183837697153566056202031);
        _liquidationPoolHandler.settleAuction(33663580470110889117800273608260215520117498607286850968631643620668, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 376647916322842326327814305437229315203341777076993910570400198695301486);
        _liquidationPoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 25553353095446, 4576944944764318279058650381557372220045541635899392217977105401448189236370);
        _liquidationPoolHandler.settleAuction(1124188319925967896480196098633929774470471695473649161072280, 2, 1);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_invariant_settle_F1_3() external {
        _liquidationPoolHandler.kickAuction(0, 3945558181153878030177, 4183257860938847260218679701589682740098170267658022767240);
        _liquidationPoolHandler.drawDebt(4462122177274869820804814924250, 18446744073709551705);
        _liquidationPoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 80620507131699866090869932155783811264689);

        invariant_fenwick_depositAtIndex_F1();
    }

    function test_regression_invariant_settle_F2_1() external {
        _liquidationPoolHandler.kickAuction(2, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationPoolHandler.takeAuction(166780275301665520376512760721506, 1999999999999999999999999999999999999999997110, 2558901617183837697153566056202031);
        _liquidationPoolHandler.settleAuction(33663580470110889117800273608260215520117498607286850968631643620668, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 376647916322842326327814305437229315203341777076993910570400198695301486);
        _liquidationPoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 25553353095446, 4576944944764318279058650381557372220045541635899392217977105401448189236370);
        _liquidationPoolHandler.settleAuction(1124188319925967896480196098633929774470471695473649161072280, 2, 1);

        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_invariant_settle_F2_2() external {
        _liquidationPoolHandler.kickAuction(0, 3945558181153878030177, 4183257860938847260218679701589682740098170267658022767240);
        _liquidationPoolHandler.drawDebt(4462122177274869820804814924250, 18446744073709551705);
        _liquidationPoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 80620507131699866090869932155783811264689);

        invariant_fenwick_depositsTillIndex_F2();
    }

    function test_regression_invariant_F3_1() external {
        _liquidationPoolHandler.bucketTake(2935665707632064617811462067363503938617565993411989637, 3, false, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationPoolHandler.moveQuoteToken(13019605457845697172279618365097597238993925, 1, 3994854914, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _liquidationPoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 3731592205777443374190, 2);
        _liquidationPoolHandler.takeAuction(3554599780774102176805971372130467746, 140835031537485528703906318530162192, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationPoolHandler.repayDebt(2692074105646752292572533908391, 1968526964305399089154844418825);
        _liquidationPoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 4553829);
        _liquidationPoolHandler.bucketTake(3, 115792089237316195423570985008687907853269984665640564039457584007913129639934, true, 0);
        _liquidationPoolHandler.drawDebt(626971501456142588551128155365, 816763288150043968438676);
        _liquidationPoolHandler.pullCollateral(381299861468989210101433912, 999999999999997998400442008957368645662570165);

        invariant_fenwick_bucket_index_F3();
    }

    function test_regression_invariant_F4_1() external {
        _liquidationPoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639935, 127546297848367334892478587751, 723921922395815633171615243621131242188407029895233162931857565302);
        _liquidationPoolHandler.removeQuoteToken(2, 2, 7361820555);
        _liquidationPoolHandler.takeAuction(85885591922376805486065427318859822458293427950603, 8526258315228761831408142393759013524255378290706574861831877477, 1267004887455971938409309909682740381503049590444968840223);
        _liquidationPoolHandler.drawDebt(663777721413606329209923101072, 946300054291644291801213511570);
        _liquidationPoolHandler.kickAuction(2, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 2);
        _liquidationPoolHandler.addQuoteToken(9360900796482582322800, 694431436637841996793959397509, 553923154643858021986449189292);
        _liquidationPoolHandler.settleAuction(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 34469655866078951331675076928366708920312931751567797);
        _liquidationPoolHandler.bucketTake(0, 1, false, 3);
        _liquidationPoolHandler.bucketTake(1190209291225920034207711400729307351194726, 2492241351445208059551299524117408972943752042954, false, 3385052658235853990473420226123930971);
        _liquidationPoolHandler.settleAuction(2693191148227658159823862814074, 44032195641927234172430384447, 2992758194960713897487381207167);
        _liquidationPoolHandler.removeQuoteToken(3, 34308174710409047450205135565, 2);
        _liquidationPoolHandler.takeAuction(235062105582030911119033338, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639933);

        invariant_fenwick_prefixSumIndex_F4();
    }

}