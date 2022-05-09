// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.11;

import { ERC20 }  from "@solmate/tokens/ERC20.sol";
import { Test }   from "@std/Test.sol";
import { Vm }     from "@std/Vm.sol";

contract DSTestPlus is Test {

    // nonce for generating random addresses
    uint16 internal _nonce = 0;

    // prices
    uint256 internal _p50159    = 50_159.593888626183666006 * 1e18;
    uint256 internal _p49910    = 49_910.043670274810022205 * 1e18;
    uint256 internal _p10016    = 10_016.501589292607751220 * 1e18;
    uint256 internal _p9020     = 9_020.461710444470171420 * 1e18;
    uint256 internal _p8002     = 8_002.824356287850613262 * 1e18;
    uint256 internal _p5007     = 5_007.644384905151472283 * 1e18;
    uint256 internal _p4000     = 4_000.927678580567537368 * 1e18;
    uint256 internal _p3514     = 3_514.334495390401848927 * 1e18;
    uint256 internal _p3010     = 3_010.892022197881557845 * 1e18;
    uint256 internal _p2850     = 2_850.155149230026939621 * 1e18;
    uint256 internal _p2835     = 2_835.975272865698470386 * 1e18;
    uint256 internal _p2821     = 2_821.865943149948749647 * 1e18;
    uint256 internal _p2807     = 2_807.826809104426639178 * 1e18;
    uint256 internal _p2793     = 2_793.857521496941952028 * 1e18;
    uint256 internal _p2779     = 2_779.957732832778084277 * 1e18;
    uint256 internal _p2503     = 2_503.519024294695168295 * 1e18;
    uint256 internal _p2000     = 2_000.221618840727700609 * 1e18;
    uint256 internal _p1004     = 1_004.989662429170775094 * 1e18;
    uint256 internal _p502      = 502.433988063349232760 * 1e18;
    uint256 internal _p146      = 146.575625611106531706 * 1e18;
    uint256 internal _p145      = 145.846393642892072537 * 1e18;
    uint256 internal _p100      = 100.332368143282009890 * 1e18;
    uint256 internal _p13_57    = 13.578453165083418466 * 1e18;
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
    event Mint(address lender, address pool, uint256 tokenId);
    event MemorializePosition(address lender, uint256 tokenId);
    event Burn(address lender, uint256 price);
    event IncreaseLiquidity(address lender, uint256 amount, uint256 price);
    event DecreaseLiquidity(
        address lender,
        uint256 collateral,
        uint256 quote,
        uint256 price
    );

    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event AddQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event AddCollateral(address indexed borrower, uint256 amount);
    event RemoveCollateral(address indexed borrower, uint256 amount);
    event ClaimCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lps
    );
    event Borrow(address indexed borrower, uint256 lup, uint256 amount);
    event Repay(address indexed borrower, uint256 lup, uint256 amount);
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);
    event Purchase(
        address indexed bidder,
        uint256 indexed price,
        uint256 amount,
        uint256 collateral
    );
    event Liquidate(address indexed borrower, uint256 debt, uint256 collateral);

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

    function generateAddress() internal returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(uint160(uint256(keccak256(abi.encodePacked(_nonce, blockhash(block.number))))));
        _nonce++;
    }

}
