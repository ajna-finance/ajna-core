// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 }  from "@solmate/tokens/ERC20.sol";
import { Maths }  from "../../libraries/Maths.sol";
import { Test }   from "@std/Test.sol";
import { Vm }     from "@std/Vm.sol";

abstract contract DSTestPlus is Test {

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    // FIXME: these prices are all wrong; the highest priced bucket now has the lowest index
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
    event DecreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 collateral_, uint256 quote_);
    event DecreaseLiquidityNFT(address indexed lender_, uint256 indexed price_, uint256[] collateral_, uint256 quote_);
    event IncreaseLiquidity(address indexed lender_, uint256 indexed price_, uint256 amount_);
    event MemorializePosition(address indexed lender_, uint256 tokenId_);
    event Mint(address indexed lender_, address indexed pool_, uint256 tokenId_);
    event MoveLiquidity(address indexed owner_, uint256 tokenId_);

    // Pool events
    event AddCollateral(address indexed borrower_, uint256 amount_);
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event AddNFTCollateral(address indexed borrower_, uint256[] tokenIds_);
    event AddQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Borrow(address indexed borrower_, uint256 lup_, uint256 amount_);
    event ClaimCollateral(address indexed claimer_, uint256 indexed price_, uint256 amount_, uint256 lps_);
    event ClaimNFTCollateral(address indexed claimer_, uint256 indexed price_, uint256[] tokenIds_, uint256 lps_);
    event Liquidate(address indexed borrower_, uint256 debt_, uint256 collateral_);
    event MoveQuoteToken(address indexed lender_, uint256 indexed from_, uint256 indexed to_, uint256 amount_, uint256 lup_);
    event PledgeCollateral(address indexed borrower_, uint256 amount_);
    event PullCollateral(address indexed borrower_, uint256 amount_);
    event Purchase(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256 collateral_);
    event PurchaseWithNFTs(address indexed bidder_, uint256 indexed price_, uint256 amount_, uint256[] tokenIds_);
    event RemoveCollateral(address indexed borrower_, uint256 amount_);
    event RemoveCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_, uint256 lps_);
    event RemoveNFTCollateral(address indexed borrower_, uint256[] tokenIds_);
    event RemoveQuoteToken(address indexed lender_, uint256 indexed price_, uint256 amount_, uint256 lup_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);
    event TransferLPTokens(address owner_, address newOwner_, uint256[] prices_, uint256 lpTokens_);
    event UpdateInterestRate(uint256 oldRate_, uint256 newRate_);

    // ERC20 events
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

    function generateAddress() internal returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(uint160(uint256(keccak256(abi.encodePacked(_nonce, blockhash(block.number))))));
        _nonce++;
    }

    function wadPercentDifference(uint256 lhs, uint256 rhs) internal pure returns (uint256 difference_) {
        difference_ = lhs < rhs ? Maths.WAD - Maths.wdiv(lhs, rhs) : Maths.WAD - Maths.wdiv(rhs, lhs);
    }

}
