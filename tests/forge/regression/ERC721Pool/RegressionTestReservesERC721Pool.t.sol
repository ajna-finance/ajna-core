// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { ReserveERC721PoolInvariants } from "../../invariants/ERC721Pool/ReserveERC721PoolInvariants.t.sol";

contract RegressionTestReserveERC721Pool is ReserveERC721PoolInvariants { 
    function setUp() public override { 
        super.setUp();
    }

    function test_regression_arithmetic_overflow() external {
        _reserveERC721PoolHandler.takeAuction(92769370221611464325146803683156031925894702957583423527130966373453460, 1, 0, 0);
        _reserveERC721PoolHandler.bucketTake(946681003919344525962988194461032341334826191474892406752540091475466732435, 115792089237316195423570985008687907853269984665640564039457584007913129639932, false, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.pledgeCollateral(110349606679412691172957834289542550319383271247755660854362242977991410022199, 14546335109189328620313099, 0);
        _reserveERC721PoolHandler.transferLps(7966696646007323951141060300, 1382000000000000000000, 14900528365458273129607000593, 18640181410506725405733865833824324648215384731482764797343269315726072943072, 0);
        _reserveERC721PoolHandler.drawDebt(107285134268485238885825019843523094619958942033886535891203702184170570337916, 1008096043491529984, 0);
        _reserveERC721PoolHandler.bucketTake(0, 1177, true, 698469034333322743784201375142656365110267526102696086972, 0);
    }

    function test_regression_CT4_1() external {
        _reserveERC721PoolHandler.takeAuction(12081493032056306060837676478, 17112687674220907985671783478, 156086231189053706777082702350822415, 0);
        _reserveERC721PoolHandler.bucketTake(2751921977392940485992662421841654754784896, 0, false, 74485124857288266409128701303509478629061526535257123857425657075, 0);
        _reserveERC721PoolHandler.settleAuction(28196, 350662677223461989004552717744870304232548804666, 36769010933687420804596073, 0);
        _reserveERC721PoolHandler.bucketTake(83908, 44550000000000000, false, 20000000000000000000000312288, 0);

        invariant_CT4();
    }

    function test_regression_CT4_2() external {
        _reserveERC721PoolHandler.drawDebt(0, 3, 0);
        _reserveERC721PoolHandler.addQuoteToken(110722066303045195479382873847756822996893052638415787811385263327686542008, 2595467720355805256177, 44804955487212801727231000414524018578, 0);
        _reserveERC721PoolHandler.moveQuoteToken(43739203749898257092507987414800731, 45406433371816793948702636, 12374955966170596958032853251, 781, 0);
        _reserveERC721PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1, 61586, 11856671202668897206441691542968611274078091901056358965450125, 0);
        _reserveERC721PoolHandler.pledgeCollateral(349513993113487194057973, 362746040314235282459383005583790844, 0);
        _reserveERC721PoolHandler.settleAuction(3, 2, 3, 0);

        invariant_CT4();
    }

    function test_regression_CT2_2() external {
        _reserveERC721PoolHandler.addQuoteToken(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 3, 0);
        _reserveERC721PoolHandler.repayDebt(47903824342862105100722366, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _reserveERC721PoolHandler.moveQuoteToken(14954617124484181050069718572841414619329, 4019052775, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 18404722369483097182428514137726899016323228344857237503694710754857187987, 0);
        _reserveERC721PoolHandler.repayDebt(8642195270788292, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _reserveERC721PoolHandler.kickAuction(37599242352987749812798760790120682114398140522946909699266021534073157156, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 42022531711777130710006520923822265578840019061180471553959992811, 0);
        _reserveERC721PoolHandler.drawDebt(12048316057, 12017048940743955664316982882044887141128535965, 0);
        _reserveERC721PoolHandler.removeQuoteToken(17773795768966620525, 1047143, 54863162, 0);
        _reserveERC721PoolHandler.withdrawBonds(115792089237316195423570985008687907853269984665640564039457584007913129639933, 3, 0);
        _reserveERC721PoolHandler.takeAuction(2698759183557, 47540095330112933707821447439580287140189201532316467969464, 28821914686174180822501529566772569775778735295453392587173140587, 0);
        _reserveERC721PoolHandler.repayDebt(11851070455092288342427255581330021498615848370966979414877793886456318988205, 20000469912106847714032076597, 0);
        _reserveERC721PoolHandler.pullCollateral(9906355507789251046177658200, 789628541711133703256041458103535389653400352665407731094226888831, 0);
        _reserveERC721PoolHandler.drawDebt(0, 5711299, 0);
        _reserveERC721PoolHandler.takeReserves(52580967332816855446614075396003761174408900540583074540513, 3066371283933430634405115377931952568434121552, 0);
        _reserveERC721PoolHandler.moveQuoteToken(187, 10746658534810329994020169146, 26326378734592892198504991, 3678, 0);
        _reserveERC721PoolHandler.kickWithDeposit(9347, 1019767997450901378, 0);
        _reserveERC721PoolHandler.pullCollateral(0, 1727508752834082423180670412007678522620836706739773785431403804, 0);
        _reserveERC721PoolHandler.addQuoteToken(10272927241872097800945271290053605104341355430184682823901929, 133408017309487439448075733, 17099185418125710911451484450376088, 0);
        _reserveERC721PoolHandler.drawDebt(448053659500389508982384470106829047, 1400284447444730491147774097, 0);
        _reserveERC721PoolHandler.removeQuoteToken(10288285818208197682336817035, 45968783023960545347406014687, 691, 0);
        _reserveERC721PoolHandler.settleAuction(154, 860492567187269218261780934935914770288503137169306025450164292967, 463633433497382452344200590293648002678143898236, 0);

        invariant_CT2();
    }

    /*
        Test was failing due to buckets where quote tokens are added through `mergeCollateral` handler were not considered in F2 invariant
        Fixed by considering all buckets in invariants and changing `fenwickSumTillIndex` method
    */
    function test_regression_invariant_F2() external {
        _reserveERC721PoolHandler.pledgeCollateral(3, 3249247182472647789271370143468153988911, 0);
        _reserveERC721PoolHandler.takeAuction(3, 68002012319987217885680836087921689752254473803305406, 3, 0);
        _reserveERC721PoolHandler.mergeCollateral(280792061588141829088525786592236158704094119781363060, 0);

        invariant_fenwick_depositAtIndex_F1();
        invariant_fenwick_depositsTillIndex_F2();
    }

    /*
        Test was failing when partial collateral is added in bucket for borrower after borrower becomes collateralized
        Fixed by updating depositTime in 'takeAuction' handler when collateral is added for borrower in bucket.
    */
    function test_regression_invariant_B5() external {
        _reserveERC721PoolHandler.withdrawBonds(29901450120321179040232647, 33707253840165794915329047600407010147409078919505035384547761916581261664771, 64256482982762173601681848012735492443236160824527223136253084902273448022922);
        _reserveERC721PoolHandler.removeQuoteToken(1035551263513576830, 41740568139652812265713570158854588029242418548921997608771244687820831484709, 71044, 62590313429503445735623493678970090625742913234641758074604729049807113894487);
        _reserveERC721PoolHandler.settleAuction(1, 0, 268121947844, 1);
        _reserveERC721PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 2, 0);
        _reserveERC721PoolHandler.takeAuction(106448808771037447301803820926416226252394847235491597014603888747398433951911, 77069574318109684248039198042740367334616176706977431797535974098463346496942, 77528075296808727840369101218435242378516990509439357003969850559946810538911, 6444651742970749586626021422362454367627580772250065944299506552651206353728);
        _reserveERC721PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639933, 2, 285525856813675343840641688174225684908631009);
        _reserveERC721PoolHandler.drawDebt(0, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 2);
        _reserveERC721PoolHandler.settleAuction(3, 132142413661373040125626290113760150183940291131, 123613323046465865910874738151644490943543283029000699929340077966695767, 1981041880214457766957806662399378912);
        _reserveERC721PoolHandler.settleAuction(85528495297011614367290117735627897273430599924159987514558136255281351756656, 51899086351157718719907596611713215459672847846628811043751547933087535149139, 6017, 32356);
        _reserveERC721PoolHandler.moveQuoteToken(41852115601722687085018, 838, 110349606679412691172957834289542550319383271247755660854362242977991410021116, 10708, 1000147102256879879);
        _reserveERC721PoolHandler.takeAuction(65083383064492179858552362056041108711907790400214219220470719778313668067918, 47044205696979556241773847817964719479426890797480386218806479041076417646753, 49891310239897651922054921325833048160713517515033725083348033871686585409233, 113036808365357047396163273250845284856347394197766632691494752070902864551847);

        invariant_Bucket_deposit_time_B5_B6_B7();
    }

    function test_regression_erc721_evm_revert_1() external {
        _reserveERC721PoolHandler.settleAuction(9989243900619820637977810558874905516372668734956884150787421704623, 18550308766242836156918, 185813535265204352484610945242967379275287026502359577631531764507799333257, 0);
        _reserveERC721PoolHandler.settleAuction(3978325917508522510207263223865211237976, 7790053814939864208425264498, 999999999999999996743786245260429581471869387, 0);
        _reserveERC721PoolHandler.kickWithDeposit(46026209085391641194310671609, 3130043694548050944738567, 0);
        _reserveERC721PoolHandler.bucketTake(321403975624759, 1, true, 33704310988122856275082007990402091273248356, 0);
        _reserveERC721PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1, 0);
        _reserveERC721PoolHandler.drawDebt(18035929394751812384297714732077328967746743, 119690523270955711756656740687855244882128084589819921547953371161511980, 0);
        _reserveERC721PoolHandler.kickReserveAuction(1000003054177280997, 0);
        _reserveERC721PoolHandler.removeCollateral(37627902510457025898862651961, 2114410737361246229072388400, 1008232170738253019, 0);
        _reserveERC721PoolHandler.pullCollateral(56236866537195270857449900111, 9403183666454523262172211919, 0);
        _reserveERC721PoolHandler.moveQuoteToken(99928573928507228525177075463, 46129133660158866813269117251, 44072647100529699393033080146, 17209665044181598648772038778694195, 0);
        _reserveERC721PoolHandler.takeAuction(49510515049714247913361, 3, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.kickReserveAuction(0, 0);
        _reserveERC721PoolHandler.moveQuoteToken(1292329311184978054029223707608815228366442482359118197, 245731237234102963770011164221044194699962572289589, 2, 499131904050126199254174184464801061408, 0);
        _reserveERC721PoolHandler.kickAuction(12878604154240405292071458, 1000077974370365988, 5250731775066900335970481825, 0);
        _reserveERC721PoolHandler.kickWithDeposit(30005857229801396387000562790, 262188009448718993801623229194350476, 0);
        _reserveERC721PoolHandler.transferLps(85517991264671346765943178766299956200222191839647589428775263346038301370940, 1001528530588111108, 5892088159565189714123454118, 81450625910729021997682284682898584896063448663928167861202354603723895077022, 0);
        _reserveERC721PoolHandler.takeReserves(1, 1, 0);
        _reserveERC721PoolHandler.moveQuoteToken(141666662243202853679, 56777880157945535810, 3, 1065279319875431430205, 0);
        _reserveERC721PoolHandler.removeQuoteToken(54442961114281489312962864640, 7664727213604432043974924746, 26543484436186811991723140317, 0);
        _reserveERC721PoolHandler.drawDebt(1, 17076375012234525656406669839643421151969741, 0);
        _reserveERC721PoolHandler.moveQuoteToken(2491755515222518, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 685411026715369241875429, 0);
        _reserveERC721PoolHandler.repayDebt(766817023589264423276010993270111294441469322285344513127010440552071147, 46167432873108613001947698653568595, 0);
        _reserveERC721PoolHandler.removeQuoteToken(2999999999999999990003843100076175080049767807, 43767925322264082584316143503, 5798400103286714157374960270, 0);
        _reserveERC721PoolHandler.removeCollateral(363349503122708, 1116100944119057116, 106039457316425099783017640, 0);
        _reserveERC721PoolHandler.pullCollateral(105543882139698869110686, 73433708449377181858755380995, 0);
        _reserveERC721PoolHandler.pledgeCollateral(0, 193805990262767737979667904191845569153058129047262518417094401922845726, 0);
        _reserveERC721PoolHandler.kickWithDeposit(115792089237316195423570985008687907853269984665640564039457584007913129639935, 16910632010742109640505760601383025605, 0);
        _reserveERC721PoolHandler.drawDebt(115102, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.moveQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 502278298364, 15623406760877121471307769380791966990279994, 25804227618345963384523584277775608274901137376896553430212216675747581362, 0);
        _reserveERC721PoolHandler.kickReserveAuction(706553361502694834509668636, 0);
        _reserveERC721PoolHandler.takeAuction(1008933132135642147, 63849767418381441757665327769, 3000000000000000000009545218614793863981329058, 0);
        _reserveERC721PoolHandler.kickAuction(1897933710841310333005368598886, 1000867455304781533, 50027874221493313760260247, 0);
        _reserveERC721PoolHandler.kickWithDeposit(532262591863, 1001203767205043464, 0);
        _reserveERC721PoolHandler.pullCollateral(20627776779876037812477066019170418743803603627426329204, 15621817480121736319934257078370317632228890568374574704147371391628169050220, 0);
        _reserveERC721PoolHandler.transferLps(2964971320695470084755812518644439501, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2418436671989139908121468417555958956713, 3, 0);
        _reserveERC721PoolHandler.kickAuction(4353115105586914085762881497, 1029709442025500487720749904677337277025353438765212074, 3839837154162449238408405046265155159774, 0);
        _reserveERC721PoolHandler.kickWithDeposit(3, 36307900544, 0);
        _reserveERC721PoolHandler.settleAuction(36222422140461077799644694858694814901204980637473820481182588, 4294499838797823, 3, 0);
        _reserveERC721PoolHandler.addQuoteToken(12243, 1, 0, 0);
        _reserveERC721PoolHandler.takeAuction(0, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _reserveERC721PoolHandler.addCollateral(43036656387401835818710642809, 102292442512853022585172627047482697338758087389118360669301779723744169241429, 74381750930592072482138046563, 0);
        _reserveERC721PoolHandler.repayDebt(24937488734288345893346053564, 17186699442063728778426820146, 0);
        _reserveERC721PoolHandler.kickWithDeposit(0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.settleAuction(72429479998190670655551465151, 9240337923752307137120083262, 22687272470234089804757129661, 0);
        _reserveERC721PoolHandler.pullCollateral(3, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _reserveERC721PoolHandler.pledgeCollateral(2, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.pullCollateral(2918422498137450666451130421, 77350276990013056505165905825, 0);
        _reserveERC721PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.pullCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639935, 889276185739199985936235438556693168616610734505050053512642270184, 0);
        _reserveERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639935, 3, 554624990711346507653069624423030973525676, 0);
        _reserveERC721PoolHandler.removeQuoteToken(2251866325354453773077336221300023580, 222, 3, 0);
        _reserveERC721PoolHandler.moveQuoteToken(123650365982471245338713857121667733, 35105258508868484293417757, 22295206987311590982827774848, 74945278786956923224251005587, 0);
        _reserveERC721PoolHandler.addCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.takeAuction(1172306772584624351856208685522146403029246191404191786716629, 2, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _reserveERC721PoolHandler.bucketTake(811703581330, 115792089237316195423570985008687907853269984665640564039457584007913129639932, true, 0, 0);
        _reserveERC721PoolHandler.kickAuction(1028774831976039031564221, 4578732511218696101589288780, 4859802282515382026734761444045339, 0);
        _reserveERC721PoolHandler.removeQuoteToken(274229616292567761765209865, 24953698065325383952620181319, 1000095664506366315, 0);
        _reserveERC721PoolHandler.kickReserveAuction(115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.addQuoteToken(0, 3, 99691945509, 0);
        _reserveERC721PoolHandler.addCollateral(5766796938812677355387930891395113, 288002600499162231870351402, 435233011359827354313831636, 0);
        _reserveERC721PoolHandler.addQuoteToken(85344700051619986265659741016111247459107651, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 2, 0);
        _reserveERC721PoolHandler.takeAuction(65312717544128511224937543, 18135742951999295406333258932186571425970, 781093421128583206897747505897978867422699538655581451997044515664756273, 0);
        _reserveERC721PoolHandler.pullCollateral(259473337270831183017994333896554, 294057109712549874823012923996796824976898610768757665, 0);
        _reserveERC721PoolHandler.repayDebt(1553935548599900755779937769741796418080663909315217304924969565141, 1753288154, 0);
        _reserveERC721PoolHandler.addQuoteToken(339656777343182735833410076875189883770225978090681, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 10340, 0);
        _reserveERC721PoolHandler.withdrawBonds(0, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.withdrawBonds(188612993025, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0);
        _reserveERC721PoolHandler.kickReserveAuction(1048744425938643176732690, 0);
        _reserveERC721PoolHandler.pledgeCollateral(11753358666346362554554879757, 5507117624984936503303840539, 0);
        _reserveERC721PoolHandler.removeCollateral(1000000001535304079, 14671886099814337092771426807, 18009642691634231989826403877, 0);
        _reserveERC721PoolHandler.drawDebt(837002711176102011, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _reserveERC721PoolHandler.pullCollateral(1167136726518055746602457, 23509863280439963595933859, 0);
        _reserveERC721PoolHandler.kickAuction(1, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639932, 0);
        _reserveERC721PoolHandler.bucketTake(0, 3, false, 138091692785668962716252818839955350291929588551104878008006, 0);
        _reserveERC721PoolHandler.repayDebt(115792089237316195423570985008687907853269984665640564039457584007913129639935, 311, 0);
        _reserveERC721PoolHandler.transferLps(752903459804834965586569651346997617246587799173479778576760907953836448, 146298533823304742010835, 103615710601751332103756957817, 69405023554253103277610822914380584, 0);
        _reserveERC721PoolHandler.takeReserves(1012665958949308566, 177416867554370280, 0);
        _reserveERC721PoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639934, 3875728828061841163202845524857245468261238092259805815683539712017173678592, true, 2393246296210532619542785541, 0);
        _reserveERC721PoolHandler.settleAuction(10369876769927149300389541014894, 11070977873620208837152554829439125558230779613438972369142, 13777309608751380820116073370229018594509906176432114388639978697897921012618, 0);
        _reserveERC721PoolHandler.pullCollateral(1014016118270937365, 6340556633446773025359948976786978451042102723087085940808511224960199174600, 0);
        _reserveERC721PoolHandler.settleAuction(3, 53337372410, 3, 0);
        _reserveERC721PoolHandler.bucketTake(255900146988474796409179646550407717307895, 115792089237316195423570985008687907853269984665640564039457584007913129639935, true, 1, 0);
        _reserveERC721PoolHandler.withdrawBonds(37265148526773569372834855495662430, 4988820783623387801724846309959641453403267681025459208299910064551123874983, 0);
        _reserveERC721PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639933, 44267216979886732074630088278413595696368543, 924081605547189602, 0);
        _reserveERC721PoolHandler.pullCollateral(2, 11669512158650368192010470775094343729019707, 0);
        _reserveERC721PoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639935, 297833736277915904555969542, false, 3723447156753903433035498391678024115204002571332204603364802, 0);
        _reserveERC721PoolHandler.pullCollateral(512404138751450848174526, 1004146160102770488120892, 0);
        _reserveERC721PoolHandler.takeReserves(30791302059671964372157, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.addCollateral(15512100897390773589908642159, 2, 321920008789184824183814316188725730531565361183918228575156, 0);
        _reserveERC721PoolHandler.drawDebt(19284758994236494670966, 1, 0);
        _reserveERC721PoolHandler.settleAuction(572796359, 82148900746589956860679, 3791377056847435511218448, 0);
        _reserveERC721PoolHandler.removeCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639935, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 0, 0);   
        _reserveERC721PoolHandler.moveQuoteToken(0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0, 860079124895993175714360170799297849152313321205528195, 0);
        _reserveERC721PoolHandler.transferLps(28780197407063436039710954046362029098904, 1, 1, 6593435024184850284469188356623245591393626224980171186416310, 0);
        _reserveERC721PoolHandler.kickAuction(1000033666141126900, 15532185648165618112899638485, 2171491756641401528, 0);
        _reserveERC721PoolHandler.drawDebt(0, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _reserveERC721PoolHandler.bucketTake(345362186405571926389, 7276370881508547803935068544139613462580774841071846933829011860, false, 3633849637809798110025, 0);
        _reserveERC721PoolHandler.pledgeCollateral(1669854942504566015637996, 1073386465480733342, 0);
        _reserveERC721PoolHandler.withdrawBonds(19174166339526806846085773058269110515363070460764173334124129870807275, 174966598084495728289701121898364031774468553170, 0);
        _reserveERC721PoolHandler.addCollateral(54338345102882397005446646649, 296434726144300605, 434176380723246532, 0);
        _reserveERC721PoolHandler.repayDebt(2457041645836413668927847435563113072869, 2848845499534433021782402043548511002109358104809346501115, 0);
        _reserveERC721PoolHandler.kickAuction(1292323496377463849739404597093664720078233979, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 142013602590330014773, 0);
        _reserveERC721PoolHandler.drawDebt(14123299200383641766505028871470962132405121329245023526446, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.addCollateral(767101366776769527680095371944857204608730339042925994572893017125804165, 4280505478315725266413404, 96010358395158310312554552175, 0);
        _reserveERC721PoolHandler.takeReserves(115792089237316195423570985008687907853269984665640564039457584007913129639935, 1704671674752, 0);
        _reserveERC721PoolHandler.takeAuction(19508288960754978692045245382, 170235774181690164200301357408926028, 47002633218755764125132471620, 0);
        _reserveERC721PoolHandler.settleAuction(8992183507265639573248893, 4948322329552446840331481280888646457892876549100932251353776029676, 24436159126393543, 0);
        _reserveERC721PoolHandler.transferLps(115792089237316195423570985008687907853269984665640564039457584007913129639932, 1309109437302657435999253502800945732311115, 246635029661418290740728213828851169257791551197900, 4748716256207326181, 0);
        _reserveERC721PoolHandler.bucketTake(5388773089439822668635410714635754090150052065685035079481, 40178153991548110570727334220, false, 78321394639232636963281486810596578029017214620046605340356468485950163747631, 0);
        _reserveERC721PoolHandler.pullCollateral(972663672805078903187908088413582, 0, 0);
        _reserveERC721PoolHandler.moveQuoteToken(41409915616372054150141458826, 3203661316023335215798442, 646496991485809, 65156362431663904975287881513, 0);
        _reserveERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 1, 800404889989915630302549214634050337149289823307816824, 0);
        _reserveERC721PoolHandler.bucketTake(470337734563241, 21009572365460309064416, true, 16471319431161946890, 0);
        _reserveERC721PoolHandler.removeCollateral(161392005819398201968670707224848184440749989012562316, 13267661369, 0, 0);
        _reserveERC721PoolHandler.drawDebt(115792089237316195423570985008687907853269984665640564039457584007913129639934, 383421996791313084600335354670573737952816626942126251, 0);
        _reserveERC721PoolHandler.addQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639932, 673824508261568970293686498332596224150040089943592641915998592613169, 115792089237316195423570985008687907853269984665640564039457584007913129639935, 0);
        _reserveERC721PoolHandler.withdrawBonds(0, 197699705801791554836116752843373104817521949, 0);
        _reserveERC721PoolHandler.removeCollateral(966377854059039259, 21217498223392332276035662894, 215577885491798253558843047, 0);
        _reserveERC721PoolHandler.withdrawBonds(66727830256366286580574327638, 66459660741465818290544579493239, 0);
        _reserveERC721PoolHandler.takeAuction(92410921267361668907824861, 1000059641322139954, 41777508526532448067212268270, 0);
        _reserveERC721PoolHandler.removeCollateral(46478200565360825212971411959501343390137866538430593136312684116211770113983, 1246939165512998657443189640, 210177940739649281025696544, 0);
        _reserveERC721PoolHandler.removeQuoteToken(1171780431447374871886987039, 854523403760765428182731803, 1010592275847958316, 0);
        _reserveERC721PoolHandler.moveQuoteToken(2913970992235361986540207480498, 1, 3910345503097307393855, 278786698370971243898520651552401338675291759134438373, 0);
        _reserveERC721PoolHandler.pullCollateral(115792089237316195423570985008687907853269984665640564039457584007913129639932, 2, 0);
        _reserveERC721PoolHandler.addQuoteToken(3, 2036364831458569, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 0);
        _reserveERC721PoolHandler.kickWithDeposit(1457413383332496534674315845, 37509813785472017970525636662, 0);
        _reserveERC721PoolHandler.transferLps(44188279104373937481999858181, 39286859172421825465539369065, 44628425590202646236523866533, 51555673326592954378962902209, 0);
        _reserveERC721PoolHandler.addQuoteToken(1072136986589800395035805, 22904335154524190434559120, 1030801052100464518, 0);
        _reserveERC721PoolHandler.addQuoteToken(97677075084166305679836442, 1000008452124308451, 15249165865336324622600068551, 0);
        _reserveERC721PoolHandler.removeCollateral(1, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 3287808436188136722, 0);
        invariant_CT2();
        invariant_CT3();
        invariant_CT4();
        invariant_CT5();
        invariant_CT6();
        invariant_CT7();
        invariant_Lps_B1();
        invariant_Lps_B4();
        invariant_Buckets_B2_B3();
    }

    function test_regression_erc721_CT2() external {
        _reserveERC721PoolHandler.settleAuction(13652854, 3, 22274361584262295180502534344873136686717874240, 77611568702503302987473072664549443425918559);
        _reserveERC721PoolHandler.withdrawBonds(707, 12156087, 19174970663707445513928200315780515094988880044);
        _reserveERC721PoolHandler.kickWithDeposit(3, 3, 672444647);
        _reserveERC721PoolHandler.kickAuction(56848152111578191493999238385381542863095352, 58529940235731531982925635292876828548122574070883324158957672865569214, 899039491413, 107401523435280391282671144);
        _reserveERC721PoolHandler.settleAuction(19634294495748734616428837200, 4937, 77655590346650144951112602856523781688846543008934920669778106922357739827346, 994969230863047393940054601942);
        _reserveERC721PoolHandler.removeQuoteToken(115792089237316195423570985008687907853269984665640564039457584007913129639934, 71512, 2, 3);
        _reserveERC721PoolHandler.moveQuoteToken(15905680501786579444933931057811252717108353959172, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 271318302293, 0, 40);
        _reserveERC721PoolHandler.kickAuction(115792089237316195423570985008687907853269984665640564039457584007913129639935, 1, 273285540430841592066075105397763679903422015958, 266767292382552685109896561555);
        _reserveERC721PoolHandler.moveQuoteToken(19067960621863745617958471469, 2999999999999999996834739158156220923161820262, 20085132340471043072465796726, 92001987806333700856071384682550468910212704266158266358190575554223580054768, 8420);
        _reserveERC721PoolHandler.pledgeCollateral(107821936054956412679567988, 1727154709158370, 3);
        _reserveERC721PoolHandler.mergeCollateral(742, 36731090122697131118614904036939339014023299978771437847280286066139902285955);
        _reserveERC721PoolHandler.bucketTake(115792089237316195423570985008687907853269984665640564039457584007913129639933, 115792089237316195423570985008687907853269984665640564039457584007913129639932, true, 115792089237316195423570985008687907853269984665640564039457584007913129639933, 4);

        invariant_CT2();
    }
}
