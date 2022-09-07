// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { Maths } from "../../libraries/Maths.sol";
import { Heap} from "../../libraries/Heap.sol";
import { FenwickTree } from "../../base/FenwickTree.sol";

import { Test } from "@std/Test.sol";
import { Vm }   from "@std/Vm.sol";
import { ERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract DSTestPlus is Test {

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    uint256 internal _p50159    = 50_159.593888626183666006 * 1e18;
    uint256 internal _p49910    = 49_910.043670274810022205 * 1e18;
    uint256 internal _p15000    = 15_000.520048194378317056 * 1e18;
    uint256 internal _p10016    = 10_016.501589292607751220 * 1e18;
    uint256 internal _p9020     = 9_020.461710444470171420 * 1e18;
    uint256 internal _p8002     = 8_002.824356287850613262 * 1e18;
    uint256 internal _p5007     = 5_007.644384905151472283 * 1e18;
    uint256 internal _p4000     = 4_000.927678580567537368 * 1e18;
    uint256 internal _p3514     = 3_514.334495390401848927 * 1e18;
    uint256 internal _p3010     = 3_010.892022197881557845 * 1e18;
    uint256 internal _p3002     = 3_002.895231777120270013 * 1e18;
    uint256 internal _p2995     = 2_995.912459898389633881 * 1e18;
    uint256 internal _p2981     = 2_981.007422784467321543 * 1e18;
    uint256 internal _p2966     = 2_966.176540084047110076 * 1e18;
    uint256 internal _p2850     = 2_850.155149230026939621 * 1e18;
    uint256 internal _p2835     = 2_835.975272865698470386 * 1e18;
    uint256 internal _p2821     = 2_821.865943149948749647 * 1e18;
    uint256 internal _p2807     = 2_807.826809104426639178 * 1e18;
    uint256 internal _p2793     = 2_793.857521496941952028 * 1e18;
    uint256 internal _p2779     = 2_779.957732832778084277 * 1e18;
    uint256 internal _p2503     = 2_503.519024294695168295 * 1e18;
    uint256 internal _p2000     = 2_000.221618840727700609 * 1e18;
    uint256 internal _p1004     = 1_004.989662429170775094 * 1e18;
    uint256 internal _p1000     = 1_000.023113960510762449 * 1e18;
    uint256 internal _p502      = 502.433988063349232760 * 1e18;
    uint256 internal _p146      = 146.575625611106531706 * 1e18;
    uint256 internal _p145      = 145.846393642892072537 * 1e18;
    uint256 internal _p100      = 100.332368143282009890 * 1e18;
    uint256 internal _p14_63    = 14.633264579158672146 * 1e18;
    uint256 internal _p13_57    = 13.578453165083418466 * 1e18;
    uint256 internal _p13_31    = 13.310245063610237646 * 1e18;
    uint256 internal _p12_66    = 12.662674231425615571 * 1e18;
    uint256 internal _p5_26     = 5.263790124045347667 * 1e18;
    uint256 internal _p1_64     = 1.646668492116543299 * 1e18;
    uint256 internal _p1_31     = 1.315628874808846999 * 1e18;
    uint256 internal _p1_05     = 1.051140132040790557 * 1e18;
    uint256 internal _p0_951347 = 0.951347940696068854 * 1e18;
    uint256 internal _p0_607286 = 0.607286776171110946 * 1e18;
    uint256 internal _p0_189977 = 0.189977179263271283 * 1e18;
    uint256 internal _p0_006856 = 0.006856528811048429 * 1e18;
    uint256 internal _p0_006822 = 0.006822416727411372 * 1e18;
    uint256 internal _p0_000046 = 0.000046545370002462 * 1e18;
    uint256 internal _p1        = 1 * 1e18;

    // PositionManager events
    event Burn(address indexed lender_, uint256 indexed price_);
    event DecreaseLiquidity(address indexed lender_, uint256 indexed price_);
    event DecreaseLiquidityNFT(address indexed lender_, uint256 indexed price_);
    event IncreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 amount_);
    event MemorializePosition(address indexed lender_, uint256 tokenId_);
    event Mint(address indexed lender_, address indexed pool_, uint256 tokenId_);
    event MoveLiquidity(address indexed owner_, uint256 tokenId_);
    event RedeemPosition(address indexed lender_, uint256 tokenId_);

    // Pool events
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event Liquidate(address indexed borrower_, uint256 debt_, uint256 collateral_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event MoveCollateral(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event TransferLPTokens(address owner_, address newOwner_, uint256[] prices_, uint256 lpTokens_);
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    // Pool deployer events
    event PoolCreated(address pool_);

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

    function generateAddress() internal returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(uint160(uint256(keccak256(abi.encodePacked(_nonce, blockhash(block.number))))));
        _nonce++;
    }

    function randomInRange(uint256 min, uint256 max) public returns (uint256) {
        return randomInRange(min, max, false);
    }

    function randomInRange(uint256 min, uint256 max, bool nonZero) public returns (uint256) {
        if      (max == 0 && nonZero) return 1;
        else if (max == min)           return max;
        uint256 rand = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, _nonce))) % (max - min + 1) + min;
        _nonce++;
        return rand;
    }

    function wadPercentDifference(uint256 lhs, uint256 rhs) internal pure returns (uint256 difference_) {
        difference_ = lhs < rhs ? Maths.WAD - Maths.wdiv(lhs, rhs) : Maths.WAD - Maths.wdiv(rhs, lhs);
    }

}

contract HeapInstance is DSTestPlus {
    using Heap for Heap.Data;

    Heap.Data private _heap;

    /**
     *  @notice used to track fuzzing test insertions.
     */
    address[] private inserts;

    constructor () {
        _heap.init();
    }

    function getCount() public view returns (uint256) {
        return _heap.count;
    }

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIdByInsertIndex(uint256 i_) public view returns (address) {
        return inserts[i_];
    }

    function upsertTp(address borrower_, uint256 tp_) public {
        _heap.upsert(borrower_, tp_);
    }

    function removeTp(address borrower_) external {
        _heap.remove(borrower_);
    }

    function getTp(address borrower_) public view returns (uint256) {
        return _heap.getById(borrower_).val;
    }

    function getMaxTp() external view returns (uint256) {
        return _heap.getMax().val;
    }

    function getMaxBorrower() external view returns (address) {
        return _heap.getMax().id;
    }

    function getTotalTps() external view returns (uint256) {
        return _heap.count;
    }


    /**
     *  @notice fills Heap with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 inserts_,
        bool trackInserts_)
        external {

        uint256 tp;
        address borrower;

        // Calculate total insertions 
        uint256 totalInserts = bound(inserts_, 1000, 2000);
        uint256 insertsDec = totalInserts;

        while (insertsDec > 0) {

            // build address and TP
            borrower = makeAddr(vm.toString(insertsDec));
            tp = randomInRange(99_836_282_890, 1_004_968_987.606512354182109771 * 10**18, true);

            // Insert TP
            upsertTp(borrower, tp);
            insertsDec  -=  1;

            // Verify amount of Heap TPs
            assertEq(_heap.count - 1, totalInserts - insertsDec);
            assertEq(getTp(borrower), tp);

            if (trackInserts_)  inserts.push(borrower);
        }

        assertEq(_heap.count - 1, totalInserts);
    }
}


contract FenwickTreeInstance is FenwickTree, DSTestPlus {

    /**
     *  @notice used to track fuzzing test insertions.
     */
    uint256[] private inserts;

    function numInserts() public view returns (uint256) {
        return inserts.length;
    }

    function getIByInsertIndex(uint256 i_) public view returns (uint256) {
        return inserts[i_];
    }

    function add(uint256 i_, uint256 x_) public {
        _add(i_, x_);
    }

    function remove(uint256 i_, uint256 x_) public {
        _remove(i_, x_);
    }

    function mult(uint256 i_, uint256 f_) public {
        _mult(i_, f_);
    }

    function treeSum() external view returns (uint256) {
        return _treeSum();
    }

    function rangeSum(uint256 i_, uint256 j_) external view returns (uint256 m_) {
        return _rangeSum(i_, j_);
    }

    function get(uint256 i_) external view returns (uint256 m_) {
        return _valueAt(i_);
    }

    function scale(uint256 i_) external view returns (uint256 a_) {
        return _scale(i_);
    }

    function findIndexOfSum(uint256 x_) external view returns (uint256 m_) {
        return _findIndexOfSum(x_);
    }

    function prefixSum(uint256 i_) external view returns (uint256 s_) {
        return _prefixSum(i_);
    }

    /**
     *  @notice fills fenwick tree with fuzzed values and tests additions.
     */
    function fuzzyFill(
        uint256 insertions_,
        uint256 amount_,
        bool trackInserts)
        external {

        uint256 i;
        uint256 amount;

        // Calculate total insertions 
        uint256 insertsDec= bound(insertions_, 1000, 2000);

        // Calculate total amount to insert
        uint256 totalAmount = bound(amount_, 1 * 1e18, 9_000_000_000_000_000 * 1e18);
        uint256 totalAmountDec = totalAmount;


        while (totalAmountDec > 0 && insertsDec > 0) {

            // Insert at random index
            i = randomInRange(1, 8190);

            // If last iteration, insert remaining
            amount = insertsDec == 1 ? totalAmountDec : (totalAmountDec % insertsDec) * randomInRange(1_000, 1 * 1e10, true);

            // Update values
            add(i, amount);
            totalAmountDec  -=  amount;
            insertsDec      -=  1;

            // Verify tree sum
            assertEq(_treeSum(), totalAmount - totalAmountDec);

            if (trackInserts)  inserts.push(i);
        }

        assertEq(_treeSum(), totalAmount);
    }

}
