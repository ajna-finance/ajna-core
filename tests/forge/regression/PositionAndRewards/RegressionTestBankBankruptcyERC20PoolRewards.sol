// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { BucketBankruptcyERC20PoolRewardsInvariants } from "../../invariants/PositionsAndRewards/BucketBankruptcyERC20PoolRewardsInvariants.t.sol";

contract RegressionTestBankBankruptcyERC20PoolRewards is BucketBankruptcyERC20PoolRewardsInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    // Test was failing because token needs to be reapproved for stake after unstaking
    // Fixed with approving token before stake
    function test_regression_position_evm_revert_1() external {
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(3, 1, 4456004777645809093369137635038884732841, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 40687908950166026711192);
    }

    // Test was failing because of unbounded bucket used for `fromBucketIndex`
    // Fixed with bounding `fromBucketIndex`
    function test_regression_max_less_than_min() external {
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639934, 47501406159061048326781, 110986208267306903569458210414739750843311008184499947884172946209775740554);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1881514382560036936235, 3, 14814387297039010985037823532);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(797766346153846154214, 41446531673892822322, 11701, 27835018298679073652989722292632508325056543016077421626954570959368347669749);
    }

    // Test was failing because of incorrect borrower index from borrowers array
    // Fixed with bounding index to use from 0 to `length - 1` instead of `length`
    function test_regression_index_out_of_bounds() external {
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(8350, 38563772714580316601477528168172448197192851223481495804140163882250050756970, 2631419556349366366777984756718, 1211945352);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(211495175470613993028534000000, 278145600165504025408587, 27529661686764881266950946609980959649419024772429123428587103668572353435463);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 6893553321768, 0);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(999993651401512530, 102781931937447242982, 270951946802940031780297034197);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(142908941962660588271918613275457408417799350540, 2, 7499, 21259944100462201457856802765711375950508);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(10312411154, 11741, 808194882698130156430790172156918);

        invariant_positions_PM1_PM2_PM3();
    }

    function test_regression_interest_accumalation_overflow() external {
        _bucketBankruptcyerc20poolrewardsHandler.stake(320307692307692307841, 2490, 10917, 403196809217289663458043223580906563641609617294);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(15059177663891191985498469564581, 21691241494814563657, 5959198137984416944871985040941211962546971878394061014854717427126670802);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(1, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 2, 306748590411024027068452057, 3);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(0, 3, 3, 44869774749435413944328478986895177316804030, 2);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639933, 667409171832157313382210046675580725011953, 170966693897056629150807196294457349572402758607401923355019500107511084513);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 19549319890719740959827156450505379259184673736260904583824030491, 16629388526339);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(1, 57, 2126726397172127776919, 3);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(10662442004167, 0, 5497097760623451146595, 3162190482019759261701358441242229);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 4633);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(195082403288206510116943243208164172979846145506483861331524728636984, 5999490491512003998567204139527071137962581199636349206, 1);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(193, 115638053, 82905768405815550325167864157103591796198207319836507298376269364238808467864);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639933, 728230189013838280072632353261014942101509879986, 1074852977686923754516502207503688995019457654331626079784, 8647989100256796072321456855285912878676340053147534437521304860653);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(3941357502157973923804, 2, 806977082765068646659096738618743289712629038, 95470398010431964952450128551272930452522452449699886025877059807238, 1);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(36183411359542968180819498843191329944675962195184522815400173109497640044908, 5526, 3966754565367876855970249316229461606728002012105551523079085776320493, 12000000000000000000786344314428468140209160332, 1514);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639935, 19347515940517406236500101946818541192254229344198927883872669126, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(1236588951273351231845418839930179263983011495754, 38238240862444672488745854665, 105710195453976313965439090442863258002796095759252242871256962165021905861650, 447301751254033913445893214690834296930546521452);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(46514948025651225960345695072605648432715982671974779016300427285754698287368, 3286, 3218715805466846511984533600393324923883748231);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3950340310148269005, 5673061940259815795875572950552217903, 0);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(201, 16652, 456263400021039761424850168808020383038614345114, 185177884615384615469);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(844186718371423468438148597031199325852724093549, 8971, 1238939858024599757491003772585973626666495470478);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(14560967560043099906703147047009467303604341499091340414611613631940255690293, 1721, 1330742788975674320956191865797062835971931496250, 8012);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(610999999999999999999, 18990, 2964);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 2202462407395028941916385359630457052998061369773792102517381208520162, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(259629493051510264, 23614305666380977416230669400318875317806232271123308657121989217833132243233, 2497, 27835018298679073652989722292632508325056543016077421626954570959368347669748, 1606);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 4650754146616051773693243800451532316887707892427, 2674637045933147252314476540226577815868397623, 1637859);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(32610811746778589434426055746005034344393175264036753585460265204263347653842, 16005, 105710195453976313965439090442863258002796095759252242871256962165021905861709);
        _bucketBankruptcyerc20poolrewardsHandler.stake(27241022853949367504447088193, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 128000899661578863761148718566665636525956915466064429, 1336719368342255666688);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(41124169807925345164795, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 1313063028941469943130200174691186594877948408346228981);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(2166715437819344420775617703353734409787244706488647403995037751254234644362, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 7532212);
        _bucketBankruptcyerc20poolrewardsHandler.stake(14552177917818508405730171864883921324, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 84190559757713757784279975706433133519542327009581632460886117089373);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(37747710333430245980940452738832839721522435977096927851794211126014890045043, 105710195453976313965439090442863258002796095759252242871256962165021905861568, 4881, 3966754565367876869122194268884518216957992861677661334548387666061342);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(159533269946056829911817908703969087399676830547153393250667762079770747, 120375821746749532031, 553664897755275959629);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(2318, 371788003, 105710195453976313965439090442863258002796095759252242871256962165021905861824, 57957110594642022010328291066590663082489422500, 378363461538461538635);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 3108493389566117837926341948558162909763275523381432406469124236768340906924, 32229393624772079505360513009288184415901939, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(2836923789, 82757687462225415771947516030365134680378685014411112583900985134363263813950, 17992734256423583958967370161492784553176489409);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1, 2, 1599018514952142375998297880);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(55687575924400638, 727999999999999999999, 15644);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1, 2673041966562049323144905243406346442490148198615, 1285995676085316511341291864375645429377044076357986037173062379358204);
        _bucketBankruptcyerc20poolrewardsHandler.stake(27836410677470140405893559165022839553284246026566794216457, 26100442293941930306313869947915225019447736484493936778052910988, 1100121169003966414850619669523011925033070895519974812092, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(751722115384615384963, 87573722621992251438460370142942144054516549109457068516979097052450755011736, 3966754565367876854520184869943068556144348793969914759895680118784807, 27984893582647316189577999054762964794852908603917399358854612125647292485578);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(15048, 20980142891430666358441099170678931589412918730, 26229794335232538522551515320652626439652093573752750988891734989405951307592);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1623645501211, 581895706741971570416382, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(16294, 37775847772112785254257, 20408);
        _bucketBankruptcyerc20poolrewardsHandler.stake(233076476716696715, 19720626000000000000021835, 14786, 880);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(91, 48915418688551403693013933582174377748045,1, 0);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(8520254760456735866522434792660074894149362458110124278618188561008801076487, 4508341423132101367979353817313302855733981519104609141429822885854284517273, 1045732366170946687500335725634396288218029048535);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(5250764587436405674967118092556206155749365731, 141015099610895938496827107324000508240276523703380995216176939659, 0);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.stake(75715332515, 20249, 139492422255, 105710195453976313965439090442863258002796095759252242871256962165021905861575);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(5433, 21391, 754284941459726849420512743397530252182784738229, 23905);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(192677, 4773, 2683, 940037522744286018063446172177794105409762773472);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(1423000347840435497235966844164533984931800601575, 288276923076923077057, 17572, 4256931000379123634785033661970275022184774617022768398310874942392452426, 139403335757771137);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(2, 2587348281013517652545024121589073614070441106624530521348844741, 519685398);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(84919864282925853877573619845135091960602695946894030665170367426270992811938, 15050648105662257143935681434472465116789984907642743379717753234643085664126, 22213, 16413, 175589814974774645221481909980815519088940506341);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3966754565367876881842889880294569887040448346346191805828869027190062, 4571, 5227);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(907000000000000000000, 2868991328, 99389371209329274803747059355072193342651880195070161537527945916651123372097);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(2784308567599248162087449504, 3589, 476777860815159664263285898208782485328810582592);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(0, 93446225603511499598845951183108384660272702, 2024254557338330727781790737102999642155730612363585, 191889378792020151);
        _bucketBankruptcyerc20poolrewardsHandler.stake(36183411359542968180819498843191329944675962195184522815400173109497640044984, 50146794086275195190991942805708459010074680271220970599602693206755183387706, 2065, 32789382558206698454860319624949663673430750389618486004860947532855016388844);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(3, 29811238, 69968346427577179605244273168972327088469976079256197056454, 1497742154395667232899123570108019263133908353144179120765);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(3, 0, 87185381081925833627461609395751279524164897425148697297070669197775260);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(17279999, 3966754565367876867473138000603430830185306546546874883932992520117722, 776481524764705302352605934280580955971144914555, 962787287);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(19060901126391672628476228072540859898, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 1);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(26920601521589162671147619654088067061266745140905760588388649977853848299620, 1875, 27835018298679073652989722292632508325056543016077421626954570959368347669985);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(553591494574561111154252750468593088203, 26003311767849788325482998126201562168467079599, 3503171015763161693096394522251351236934013944546);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(36822330623891827054618617680243779734013976879104614005453233537599913890987, 2030, 351827466436279533, 36183411359542968180819498843191329944675962195184522815400173109497640045092, 431);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(4307769405459937793464500814388987723043870007160919438680139924065536869, 20774, 20905556733966496908705142171609168952816592958194260630754626678628699156025, 112677305303603608793464000990919617579761525091244043308691041092632466067909, 3966754565367876866027363177544639294642486780494516334079839883146086);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(5612107944, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 3, 3758652);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3, 13063704682547015731607989179567642095598985357156794100666758119236, 1663082272433979660889799306293339760568971320019141218266316592279716982939);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(698213858938870538487, 14890451379766624461267359941375, 48557935465010072094981800005966219309615168007618540929696328537074564550805);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(0, 0, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(355000000000000000000, 49046620449355538574108822723048473721226797556007972061207479861126558122006, 13060);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 1); 
        _bucketBankruptcyerc20poolrewardsHandler.stake(320307692307692307841, 2490, 10917, 403196809217289663458043223580906563641609617294);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(15059177663891191985498469564581, 21691241494814563657, 5959198137984416944871985040941211962546971878394061014854717427126670802);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(1, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 2, 306748590411024027068452057, 3);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(0, 3, 3, 44869774749435413944328478986895177316804030, 2);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639933, 667409171832157313382210046675580725011953, 170966693897056629150807196294457349572402758607401923355019500107511084513);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 19549319890719740959827156450505379259184673736260904583824030491, 16629388526339);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(1, 57, 2126726397172127776919, 3);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(10662442004167, 0, 5497097760623451146595, 3162190482019759261701358441242229);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 4633);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(195082403288206510116943243208164172979846145506483861331524728636984, 5999490491512003998567204139527071137962581199636349206, 1);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(193, 115638053, 82905768405815550325167864157103591796198207319836507298376269364238808467864);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639933, 728230189013838280072632353261014942101509879986, 1074852977686923754516502207503688995019457654331626079784, 8647989100256796072321456855285912878676340053147534437521304860653);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(3941357502157973923804, 2, 806977082765068646659096738618743289712629038, 95470398010431964952450128551272930452522452449699886025877059807238, 1);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(36183411359542968180819498843191329944675962195184522815400173109497640044908, 5526, 3966754565367876855970249316229461606728002012105551523079085776320493, 12000000000000000000786344314428468140209160332, 1514);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639935, 19347515940517406236500101946818541192254229344198927883872669126, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(1236588951273351231845418839930179263983011495754, 38238240862444672488745854665, 105710195453976313965439090442863258002796095759252242871256962165021905861650, 447301751254033913445893214690834296930546521452);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(46514948025651225960345695072605648432715982671974779016300427285754698287368, 3286, 3218715805466846511984533600393324923883748231);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3950340310148269005, 5673061940259815795875572950552217903, 0);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(201, 16652, 456263400021039761424850168808020383038614345114, 185177884615384615469);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(844186718371423468438148597031199325852724093549, 8971, 1238939858024599757491003772585973626666495470478);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(14560967560043099906703147047009467303604341499091340414611613631940255690293, 1721, 1330742788975674320956191865797062835971931496250, 8012);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(610999999999999999999, 18990, 2964);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 2202462407395028941916385359630457052998061369773792102517381208520162, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(259629493051510264, 23614305666380977416230669400318875317806232271123308657121989217833132243233, 2497, 27835018298679073652989722292632508325056543016077421626954570959368347669748, 1606);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 4650754146616051773693243800451532316887707892427, 2674637045933147252314476540226577815868397623, 1637859);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(32610811746778589434426055746005034344393175264036753585460265204263347653842, 16005, 105710195453976313965439090442863258002796095759252242871256962165021905861709);
        _bucketBankruptcyerc20poolrewardsHandler.stake(27241022853949367504447088193, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 128000899661578863761148718566665636525956915466064429, 1336719368342255666688);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(41124169807925345164795, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 1313063028941469943130200174691186594877948408346228981);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(2166715437819344420775617703353734409787244706488647403995037751254234644362, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 7532212);
        _bucketBankruptcyerc20poolrewardsHandler.stake(14552177917818508405730171864883921324, 0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 84190559757713757784279975706433133519542327009581632460886117089373);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(37747710333430245980940452738832839721522435977096927851794211126014890045043, 105710195453976313965439090442863258002796095759252242871256962165021905861568, 4881, 3966754565367876869122194268884518216957992861677661334548387666061342);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(159533269946056829911817908703969087399676830547153393250667762079770747, 120375821746749532031, 553664897755275959629);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(2318, 371788003, 105710195453976313965439090442863258002796095759252242871256962165021905861824, 57957110594642022010328291066590663082489422500, 378363461538461538635);
        _bucketBankruptcyerc20poolrewardsHandler.stake(1, 3108493389566117837926341948558162909763275523381432406469124236768340906924, 32229393624772079505360513009288184415901939, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(2836923789, 82757687462225415771947516030365134680378685014411112583900985134363263813950, 17992734256423583958967370161492784553176489409);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1, 2, 1599018514952142375998297880);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(55687575924400638, 727999999999999999999, 15644);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(1, 2673041966562049323144905243406346442490148198615, 1285995676085316511341291864375645429377044076357986037173062379358204);
        _bucketBankruptcyerc20poolrewardsHandler.stake(27836410677470140405893559165022839553284246026566794216457, 26100442293941930306313869947915225019447736484493936778052910988, 1100121169003966414850619669523011925033070895519974812092, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(751722115384615384963, 87573722621992251438460370142942144054516549109457068516979097052450755011736, 3966754565367876854520184869943068556144348793969914759895680118784807, 27984893582647316189577999054762964794852908603917399358854612125647292485578);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(15048, 20980142891430666358441099170678931589412918730, 26229794335232538522551515320652626439652093573752750988891734989405951307592);
        _bucketBankruptcyerc20poolrewardsHandler.stake(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1623645501211, 581895706741971570416382, 115792089237316195423570985008687907853269984665640564039457584007913129639933);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(16294, 37775847772112785254257, 20408);
        _bucketBankruptcyerc20poolrewardsHandler.stake(233076476716696715, 19720626000000000000021835, 14786, 880);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(91, 48915418688551403693013933582174377748045,1, 0);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(8520254760456735866522434792660074894149362458110124278618188561008801076487, 4508341423132101367979353817313302855733981519104609141429822885854284517273, 1045732366170946687500335725634396288218029048535);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(5250764587436405674967118092556206155749365731, 141015099610895938496827107324000508240276523703380995216176939659, 0);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.stake(75715332515, 20249, 139492422255, 105710195453976313965439090442863258002796095759252242871256962165021905861575);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(5433, 21391, 754284941459726849420512743397530252182784738229, 23905);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(192677, 4773, 2683, 940037522744286018063446172177794105409762773472);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(1423000347840435497235966844164533984931800601575, 288276923076923077057, 17572, 4256931000379123634785033661970275022184774617022768398310874942392452426, 139403335757771137);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(2, 2587348281013517652545024121589073614070441106624530521348844741, 519685398);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(84919864282925853877573619845135091960602695946894030665170367426270992811938, 15050648105662257143935681434472465116789984907642743379717753234643085664126, 22213, 16413, 175589814974774645221481909980815519088940506341);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3966754565367876881842889880294569887040448346346191805828869027190062, 4571, 5227);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(907000000000000000000, 2868991328, 99389371209329274803747059355072193342651880195070161537527945916651123372097);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(2784308567599248162087449504, 3589, 476777860815159664263285898208782485328810582592);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(0, 93446225603511499598845951183108384660272702, 2024254557338330727781790737102999642155730612363585, 191889378792020151);
        _bucketBankruptcyerc20poolrewardsHandler.stake(36183411359542968180819498843191329944675962195184522815400173109497640044984, 50146794086275195190991942805708459010074680271220970599602693206755183387706, 2065, 32789382558206698454860319624949663673430750389618486004860947532855016388844);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(3, 29811238, 69968346427577179605244273168972327088469976079256197056454, 1497742154395667232899123570108019263133908353144179120765);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(3, 0, 87185381081925833627461609395751279524164897425148697297070669197775260);
        _bucketBankruptcyerc20poolrewardsHandler.moveQuoteTokenToLowerBucket(17279999, 3966754565367876867473138000603430830185306546546874883932992520117722, 776481524764705302352605934280580955971144914555, 962787287);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(19060901126391672628476228072540859898, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 1);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(26920601521589162671147619654088067061266745140905760588388649977853848299620, 1875, 27835018298679073652989722292632508325056543016077421626954570959368347669985);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(553591494574561111154252750468593088203, 26003311767849788325482998126201562168467079599, 3503171015763161693096394522251351236934013944546);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(36822330623891827054618617680243779734013976879104614005453233537599913890987, 2030, 351827466436279533, 36183411359542968180819498843191329944675962195184522815400173109497640045092, 431);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(4307769405459937793464500814388987723043870007160919438680139924065536869, 20774, 20905556733966496908705142171609168952816592958194260630754626678628699156025, 112677305303603608793464000990919617579761525091244043308691041092632466067909, 3966754565367876866027363177544639294642486780494516334079839883146086);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(5612107944, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 3, 3758652);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(3, 13063704682547015731607989179567642095598985357156794100666758119236, 1663082272433979660889799306293339760568971320019141218266316592279716982939);
        _bucketBankruptcyerc20poolrewardsHandler.failed();
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(698213858938870538487, 14890451379766624461267359941375, 48557935465010072094981800005966219309615168007618540929696328537074564550805);
        _bucketBankruptcyerc20poolrewardsHandler.moveStakedLiquidity(0, 0, 1, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932);
        _bucketBankruptcyerc20poolrewardsHandler.lenderKickAuction(355000000000000000000, 49046620449355538574108822723048473721226797556007972061207479861126558122006, 13060);
        _bucketBankruptcyerc20poolrewardsHandler.takeOrSettleAuction(115792089237316195423570985008687907853269984665640564039457584007913129639932, 0, 1);
    }
    
}
