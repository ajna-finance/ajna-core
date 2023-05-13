// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { LiquidationERC721PoolInvariants } from "../../invariants/ERC721Pool/LiquidationERC721PoolInvariants.t.sol";

contract RegressionTestLiquidationERC721Pool is LiquidationERC721PoolInvariants {

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_CT2_1() external {
        _liquidationERC721PoolHandler.transferLps(82763479476530761653416180818770120221606073479896485216701663210067343854989, 13965680104257999009544220, 19607095117906083242714379712137487321145009755129413368920688919580383224, 172964, 0);
        _liquidationERC721PoolHandler.drawDebt(890267305151917142442750426831409392687842064959563694229432652653, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _liquidationERC721PoolHandler.moveQuoteToken(4235656392303564786676824298, 95172, 43998930769576514260444206117, 19, 0);
        _liquidationERC721PoolHandler.removeCollateral(3, 2498246403298170224512157430407755467635042114433885793390715371, 100495355660528314100606431049031638496400849091716919265110381324275, 0);
        _liquidationERC721PoolHandler.addQuoteToken(2, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _liquidationERC721PoolHandler.transferLps(519335861499288467890359611142992274483199326, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 58994010504161811237846499984711170588879896808493104194231, 3, 0);
        _liquidationERC721PoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 41193994068653137125420839784619, 2, 0);
        _liquidationERC721PoolHandler.pledgeCollateral(20422241426722852797507678149773415955101379369266542516369, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        invariant_collateral();
    }

    function test_regression_CT2_2() external {
        _liquidationERC721PoolHandler.pledgeCollateral(11364442794296936806062834101, 2, 0);
        _liquidationERC721PoolHandler.repayDebt(127588, 83100081073501003261077111710432816811128546597964956253465927696489949357170, 0);
        _liquidationERC721PoolHandler.addCollateral(106002141912347165539594289495307219487505255691982710940541429529032942318473, 92001987806333700856071384682550468910212704266158266358190575554223580055372, 10372528004978988523232445248742074319234365108658587623559014019285393461590, 0);
        _liquidationERC721PoolHandler.pullCollateral(3, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _liquidationERC721PoolHandler.pullCollateral(123201780725572471227365690095045434559536667998811844, 1, 0);
        _liquidationERC721PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 29385674639660674352849281126447, 104213395651073427726178922661176810647437412987911413866648707979037858111, 120099089654852364357199080589352201114952444751633, 0);
        _liquidationERC721PoolHandler.takeAuction(20272072497355131279266366599, 62702303947006190164253670404709792694262725188679134323940816202830205182957, 2018886559710986403697166, 0);
        _liquidationERC721PoolHandler.removeCollateral(3700863476119406681, 459532160275944001121201486579288279690, 64339, 0);
        _liquidationERC721PoolHandler.kickAuction(241465325251293207620629184765800029, 272324, 4286, 0);
        _liquidationERC721PoolHandler.addCollateral(14183352841703051060560888149196444796369982703801170254620915975140557318165, 58035546441149173952074400174948456045444728138319576872232054245393948126862, 1516000000000000000000, 0);
        _liquidationERC721PoolHandler.repayDebt(113036808365357047396163273250845284856347394197766632691494752070902864551209, 770331998269427329234302, 0);
        _liquidationERC721PoolHandler.settleAuction(231577253, 1483514342575063812508584719638203116171392315272235623, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _liquidationERC721PoolHandler.settleAuction(2, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _liquidationERC721PoolHandler.drawDebt(41199243733551491091355970566553968189620029998048, 143444422045802851477052828901, 0);
        _liquidationERC721PoolHandler.settleAuction(2, 8106084097424684161337344993693951687492733297750298657163090782893337803, 0, 0);
        _liquidationERC721PoolHandler.settleAuction(24837746324089221857760845057323397822024818909964892790635250470570076078486, 76738562199262389151219341912555113757197572023777541085268052336938591410624, 95228427349014753291008393411121665873108183485006042815631164420251653152751, 0);
        
        invariant_collateral();

    }

    function test_regression_evm_revert() external {
        _liquidationERC721PoolHandler.bucketTake(2, 1349541295405069308566056236594888526270892896988, false, 18293394963373947391940175296817481, 0);
        _liquidationERC721PoolHandler.addQuoteToken(994255470879741784854463339406983, 160443962062009775217345068718654486938090, 0, 0);
        _liquidationERC721PoolHandler.removeQuoteToken(110349606679412691172957834289542550319383271247755660854362242977991410022932, 20146, 18640181410506725405733865833824324648215384731482764797343269315726072943243, 0);
        _liquidationERC721PoolHandler.removeQuoteToken(3, 32353860919711184369008251816, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _liquidationERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 5787821553126, 1, 0);
        _liquidationERC721PoolHandler.addCollateral(416000000000000000000, 92001987806333700856071384682550468910212704266158266358190575554223580055260, 210789749744805153960619, 0);
    }

    /*
        Test was failing when partial collateral is added in bucket for borrower after borrower becomes collateralized
        Fixed by updating depositTime in 'repayDebt' handler when collateral is added for borrower in bucket.
    */
    function test_regression_invariant_B5_1() external {
        _liquidationERC721PoolHandler.mergeCollateral(26379999973303451405097860853, 0);
        _liquidationERC721PoolHandler.pledgeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639933, 198376655287800286010070308646851129242192857410305918128183504, 0);
        _liquidationERC721PoolHandler.kickAuction(3, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0, 0);
        _liquidationERC721PoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 3, 43157292751004395266775137041853631830242177281331941838335997503, 0);
        _liquidationERC721PoolHandler.repayDebt(3, 15336155681082503431099729405384462718738794298796523878220489474831773, 0);
        invariant_bucket();
    }

    /*
        Test was failing when partial collateral is added in bucket for borrower after borrower becomes collateralized
        Fixed by updating depositTime in 'takeAuction' handler when collateral is added for borrower in bucket.
    */
    function test_regression_invariant_B5_2() external {
        _liquidationERC721PoolHandler.pledgeCollateral(62072624193766640913909390994885052970245728906467889094353399451535599113244, 1000012687123859870, 16756831076010021813036667829318578467494198906224313602492810544840827711497);
        _liquidationERC721PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639934, 2, 39522838938);
        _liquidationERC721PoolHandler.takeAuction(38436, 12796163474520465714881469213596991307095756029235757350527859532818979149848, 236, 26511057352925151874817900429276281706694346584662189088043467429524323658773);

        invariant_bucket();
    }

    /*
        Test was failing when partial collateral is added in bucket for borrower after borrower becomes collateralized
        Fixed by updating depositTime in 'settleAuction' handler when collateral is added for borrower in bucket.
    */
    function test_regression_invariant_B5_3() external {
        _liquidationERC721PoolHandler.moveQuoteToken(898761346601995332968440, 1, 281290971280478301822821494347217658505029428037879054325, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _liquidationERC721PoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1, 2, 9813692387192478769130999425125066055);
        _liquidationERC721PoolHandler.kickWithDeposit(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2);
        _liquidationERC721PoolHandler.settleAuction(140569786344478, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 761335476707022719857597);

        invariant_bucket();
    }
    
    /*
        Test was failing when partial collateral is added in bucket for borrower after borrower becomes collateralized
        Fixed by updating depositTime in 'bucketTake' handler when collateral is added for borrower in bucket.
    */
    function test_regression_invariant_B5_4() external {
        _liquidationERC721PoolHandler.bucketTake(3, 37625625304, true, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationERC721PoolHandler.kickWithDeposit(3, 3, 2);
        _liquidationERC721PoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932, true, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 51633399605532141251772874775295477365945157734353620);

        invariant_bucket();
    }

    /*
        Test was failing because not all buckets were checked for collateral.
        Fixed by recording bucket 7388 when settle performed.
    */
    function test_regression_liquidation_CT2_3() external {
        _liquidationERC721PoolHandler.pullCollateral(54505878282630621336327288518119032809649402198240989711348043195888862303, 6425192232404400726345611481226777529322694577339980527764654089807135, 6069097751382701056451900914776322223900273807977361688596777846059535);
        _liquidationERC721PoolHandler.kickWithDeposit(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationERC721PoolHandler.kickWithDeposit(40634111685881491540685038935075868009461471090313, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 794065631491126295075683045712740549307641208240422976574);
        _liquidationERC721PoolHandler.removeQuoteToken(3, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 316968315, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationERC721PoolHandler.addQuoteToken(3, 853851203028462651768, 1, 198496430460941314962462441789669119480667961292532319857094939);
        _liquidationERC721PoolHandler.transferLps(123534659549619259016658721662490016547975255328, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 1, 95841980982668727695631410563963, 2775913420849760488284925839916);
        _liquidationERC721PoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639933, 3, 632442574811, 115792089237316195423570985008687907853269984665640564039457584007913129639934);

        invariant_collateral();
    }

    function test_regression_failure_A7_2() external {
        _liquidationERC721PoolHandler.transferLps(3, 3655401935970994745314177259069, 136769163886422778021983457809130981124, 620942, 1614577858204991477254907493467892865454785457516379154703135967980998);
        _liquidationERC721PoolHandler.mergeCollateral(14415645877527481541237295, 1760186990);
        _liquidationERC721PoolHandler.repayDebt(1000000695944099010, 16993974611660335558976021378, 1029330184651320407038081);
        _liquidationERC721PoolHandler.drawDebt(4328262361357328728637911, 47588289579251568248070879524529354134046701502508304900513168544189400494834, 163877757788701);
        _liquidationERC721PoolHandler.mergeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639933, 3);
        _liquidationERC721PoolHandler.removeQuoteToken(5449, 91509897037395202876797812344977844707030753189520454312427981040645023300161, 27148793820061636064048228406033257075967858404134388565084496840094190573263, 68204480129603149590387);
        _liquidationERC721PoolHandler.bucketTake(1952, 28983545358618010459712306, false, 13032548439900914730104193430142520601254748129114504767930157203676332456812, 43817174866998552171439861576627097690755969820199181774526642711234088737122);
        _liquidationERC721PoolHandler.takeAuction(7935121589753152746852190684010525637673690118211584, 14310869928515213918577392, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _liquidationERC721PoolHandler.settleAuction(702583206831323402817113656096695809209331170244307993885312291422022820, 47550419425327480616706511499075798664039401458387139243899912475947071841730, 74505891748485969091948648129770258991970468658634199385495564883913582243243, 113036808365357047396163273250845284856347394197766632691494752070902864551622);
        _liquidationERC721PoolHandler.bucketTake(3213372609584362733908673163142669149311, 2290945060886243605554466763, true, 8445027141357287130032866527068625178566766937761078571759981382980382264, 28391959860257138642471040);
        _liquidationERC721PoolHandler.mergeCollateral(2268945743684874020491693, 2);
        _liquidationERC721PoolHandler.withdrawBonds(62327682220484206871903967718340409567719302497922097525845296561024214438722, 16808, 24594494922636051517911114439);
        _liquidationERC721PoolHandler.repayDebt(110349606679412691172957834289542550319383271247755660854362242977991410022677, 40484, 68922747499527301465922997970508131469854010565703396983048833295964811389555);
        _liquidationERC721PoolHandler.kickAuction(1742469479, 35752, 1057920036681767842, 13785);
        _liquidationERC721PoolHandler.moveQuoteToken(185314179206261555624584351144983452451405601815379485223429112334894697, 17918874221260324, 1, 68680246090887050619676561085287, 18360614768259939305695461144185959073097149642445960);
        _liquidationERC721PoolHandler.bucketTake(37996, 62327682220484206871903967718340409567719302497922097525845296561024214438972, false, 74491541637816183323432, 23548913611057647608499462034660876148235797357470439794500690624628936294752);
        _liquidationERC721PoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 2, true, 122391791823515205739915477639339999027699445717632722485958, 1);
        _liquidationERC721PoolHandler.mergeCollateral(7137415919637491141881, 1025411825);
        _liquidationERC721PoolHandler.bucketTake(2074255567, 62930419783609851358322950084447067504714907123847879176349713897770248274790, false, 30898680600184438890868737570792388570065267524078030025687460257800451485100, 14079292358154521351);
        _liquidationERC721PoolHandler.kickWithDeposit(91387242540804, 1000002606711604178, 85946383966053781430487237900937953007849640831813517263628662558720153363601);

        invariant_auction();
    }

}

contract RegressionTestLiquidationWith10BucketsERC721Pool is LiquidationERC721PoolInvariants {

    function setUp() public override { 
        // failures reproduced with 10 active buckets
        vm.setEnv("NO_OF_BUCKETS", "10");
        super.setUp();
    }

    /**
        Test was failing when auction was settled and borrower compensated with LP for fractional collateral in a bucket with higher price (lower index) than LENDER_MIN_BUCKET_INDEX.
        Fixed by extracting min and max index from `getCollateralBuckets()` buckets inside `fenwickIndexForSum`.
     */
    function test_regression_10_buckets_erc721_F1_F2() external {
        _liquidationERC721PoolHandler.kickWithDeposit(2, 0, 119623984614);
        _liquidationERC721PoolHandler.kickAuction(2, 1156683884353192742341767421, 459270, 3);
        _liquidationERC721PoolHandler.transferLps(29013806206364598365, 1427168328567585510116210033014146583028839301025725954083, 1, 0, 18572119254493611002099);
        _liquidationERC721PoolHandler.kickAuction(16695879118143227003041354410, 20257574621205291951103843117, 1000003697188716997, 26779825480547342678627084615);
        _liquidationERC721PoolHandler.bucketTake(3280418125857788317050603953, 176282641858576987454471425, false, 16221146755676127337872614096, 5719780674512502579213031);
        _liquidationERC721PoolHandler.takeAuction(216149463574981355299029660, 2204585273468972976606239, 14202322417006445890282145, 5570162265941831905935436152);
        _liquidationERC721PoolHandler.mergeCollateral(71336864736767260483891823, 2906866016419824116426532083);
        _liquidationERC721PoolHandler.settleAuction(64099094221235656371, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 3, 747666507251);

        invariant_fenwick();
    }

    function test_regression_10_buckets_erc721_F4() external {
        _liquidationERC721PoolHandler.transferLps(115792089237316195423570985008687907853269984665640564039457584007913129639933, 1, 1, 42504427691589606283165800893934124287580245001833672855645, 0);
        _liquidationERC721PoolHandler.removeCollateral(2338384960821630, 37971, 5258902754545952356143353956533290310813045465660334120841530710051, 1954160822312032281420621834956443112457669884);
        _liquidationERC721PoolHandler.moveQuoteToken(4415136867997578786911969045242690242353686451094010568923781565, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 0, 261601710765263531096194656);
        _liquidationERC721PoolHandler.settleAuction(970340745519190785737461702432489766136265250, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationERC721PoolHandler.kickAuction(21153289945874099718636115846686023780707539150855083580438348991810009707592, 231833300790627422, 2430778200610757092748730249372285, 13040999445181237637293392234);
        _liquidationERC721PoolHandler.settleAuction(28829603314846949380261872, 112191708732827586266077754, 22638900296959380506195308927, 1000335038342628591);
        _liquidationERC721PoolHandler.kickWithDeposit(14160215155867284847068871, 3066449405235676217230027, 1000005659521776292);
        _liquidationERC721PoolHandler.takeAuction(2, 3, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationERC721PoolHandler.repayDebt(1, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 158201561385950295129615012177899108288175);
        _liquidationERC721PoolHandler.mergeCollateral(15443, 3967798534471471250975814546);
        _liquidationERC721PoolHandler.bucketTake(265675567841576807269139862031630268230868201731408755044, 1, false, 106011217333220949447594880381675749272305231079944677237283, 0);
        _liquidationERC721PoolHandler.drawDebt(1, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 3);
        _liquidationERC721PoolHandler.withdrawBonds(127179069139973317056614208, 42246834220634196516812567595, 14065985258895841707585160);
        _liquidationERC721PoolHandler.pledgeCollateral(1701800127446919499887, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _liquidationERC721PoolHandler.pullCollateral(3192815848274377638412039248467009, 1000095668280866596, 64178081538320216018064036617);
        _liquidationERC721PoolHandler.settleAuction(2, 25048, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 802066695147857202016229418032364951522568736188);
        _liquidationERC721PoolHandler.pullCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639934, 416397059448796703242931408872, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _liquidationERC721PoolHandler.addCollateral(13220838817253690172767154778072, 1999999999999999995880152427011457736061077728, 29180409110952100332235038396, 17288399772299390020534912302326444351334405637644953526600175516079968667848);
        _liquidationERC721PoolHandler.pledgeCollateral(1852463940, 14405253157292265303350254, 57971399944576321545764649);
        _liquidationERC721PoolHandler.kickAuction(1000277034516230710, 30954808526785312119079012343, 14487730249589799367853358, 13152781927156401109554570295);
        _liquidationERC721PoolHandler.addCollateral(3448140312856629044587243742, 1348358160890871310590453920, 15842488178240192214745242746, 58008031395385767820578938);
        _liquidationERC721PoolHandler.addCollateral(5001316239475079972880121226, 1883226606569036507982030, 28748898880297414770244979624, 13445171010414284115249708888);
        _liquidationERC721PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 1, 1411895302507976009166499453930, 7800118848801360443);
        _liquidationERC721PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 3, 63431142893837086477399906862, 115792089237316195423570985008687907853269984665640564039457584007913129639935);
        _liquidationERC721PoolHandler.removeCollateral(1001095406396501137, 28903515406024512918814693, 42681137331396124029476, 1088052134382329659);
        _liquidationERC721PoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 4784357727836865, 3876873216497407066272355531633, 16399789615293865);
        _liquidationERC721PoolHandler.drawDebt(3860251784759441355850425654, 10022160373994742100540867773, 86926429185491158163971785);
        _liquidationERC721PoolHandler.kickAuction(1000023404955489823332134, 25365911766656173122139859337, 20012742395166753493977469175, 9333154884192050595923467164);
        _liquidationERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 573593659528923718, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 3);
        _liquidationERC721PoolHandler.kickWithDeposit(32882475918305935415526014479, 71712963014369177599807221, 702536441180428194811094101333785233668641934645322721111759648519780728);
        _liquidationERC721PoolHandler.removeQuoteToken(32684121703749567918313030113529773051, 244784655, 3, 25487161);
        _liquidationERC721PoolHandler.pledgeCollateral(288999079921244931741500695891, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationERC721PoolHandler.takeAuction(33410008093666158498951519, 481975152400521717024558009967316, 1005864628141771195, 1000004180567372692);
        _liquidationERC721PoolHandler.settleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 2537743727110740503569278362730, 1, 1);
        _liquidationERC721PoolHandler.settleAuction(3253385564908967779436236718, 28276713074860098780254266272, 5837230669964347830868836887, 6252323640064169991251338021);
        _liquidationERC721PoolHandler.addQuoteToken(3, 5158865936150580623717254521873401546277661243070599862, 0, 3);
        _liquidationERC721PoolHandler.addCollateral(33020828092900921632894247715, 10504880927923291577237829931, 12492310190457093324544966547, 818639664676614552485166588);
        _liquidationERC721PoolHandler.kickWithDeposit(115792089237316195423570985008687907853269984665640564039457584007913129639933, 10300652091, 1032463552968);
        _liquidationERC721PoolHandler.settleAuction(14989907985802722133727358, 1000081351959314238, 7993376402219492844516656910, 16388963991550774779688403792);
        _liquidationERC721PoolHandler.drawDebt(5464118811185766229700296775734451, 57514763379348766299186557, 15058213631944735895160588);
        _liquidationERC721PoolHandler.pledgeCollateral(0, 574270603285831642985387182167035891353834349631418692, 1184504645755354943030405957751217066414186144);
        _liquidationERC721PoolHandler.withdrawBonds(2, 0, 2);
        _liquidationERC721PoolHandler.kickWithDeposit(2, 8747239138299630922320054146639159820141434760146080, 167002917966202206884);
        _liquidationERC721PoolHandler.takeAuction(566195741605537888263397312246837580262190272351822333745934353086, 3948248540667634345713024497862548201881780252187246019937162277, 27810772533350621789874295209691369393366591925132656, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _liquidationERC721PoolHandler.pullCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 717180990621304163923299428654137326974164894424239886804322771768);
        _liquidationERC721PoolHandler.addCollateral(69350434094149412981208550, 41760775104065152001952235, 10121285650495161460634668771, 56273450916713270865378253);
        _liquidationERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 135981887711744514179144651359704900807, 115792089237316195423570985008687907853269984665640564039457584007913129639934);

        invariant_fenwick();
    }
}