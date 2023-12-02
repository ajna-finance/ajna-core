// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ERC20Pool }        from "src/ERC20Pool.sol";
import { ERC20PoolFactory } from "src/ERC20PoolFactory.sol";

import "src/PoolInfoUtils.sol";
import "src/libraries/helpers/PoolHelper.sol";

import "./BalancerUniswapExample.sol";
import "./UniswapTakeExample.sol";

contract ERC20TakeWithExternalLiquidityTest is Test {
    // pool events
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);

    address constant WETH     = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC     = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant AJNA     = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    uint24  constant POOL_FEE = 3000;

    IWETH  private weth = IWETH(WETH);
    IERC20 private usdc = IERC20(USDC);

    ERC20Pool internal _ajnaPool;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    uint256 internal _i100_33;
    uint256 internal _i9_91;
    uint256 internal _i9_81;
    uint256 internal _i9_72;
    uint256 internal _i9_62;
    uint256 internal _i9_52;

    function setUp() external {

        _i100_33 = 3232;
        _i9_91   = 3696;
        _i9_81   = 3698;
        _i9_72   = 3700;
        _i9_62   = 3702;
        _i9_52   = 3704;

        // create an Ajna pool
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _ajnaPool = ERC20Pool(new ERC20PoolFactory(AJNA).deployPool(WETH, USDC, 0.05 * 10**18));

        // create lenders and borrowers
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        // fund lenders with quote token
        deal(USDC, _lender, 120_000.0 * 1e6);

        // fund borrower
        deal(WETH, _borrower,  2_000.0 * 1e18);
        deal(USDC, _borrower,  3_000.0 * 1e6);

        // fund borrower2
        deal(WETH, _borrower2,  2 * 1e18);
    }


    function testBorrowerArbTakeLittlePenalty() external {

        // External market price is 1 WETH @ 15 USDC 

        // assert Borrower balances
        assertEq(usdc.balanceOf(_borrower), 3_000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 2000.0 * 1e18);

        // assert Kicker (_lender) balances
        assertEq(usdc.balanceOf(_lender), 120_000.000000 * 1e6);
        assertEq(weth.balanceOf(_lender), 0 * 1e18);

        // add liquidity to the Ajna pool
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(7_000 * 1e18, _i9_81, type(uint256).max, false);
        // _ajnaPool.addQuoteToken(5_000 * 1e18, 3698, type(uint256).max, false);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700, type(uint256).max, false);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702, type(uint256).max, false);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704, type(uint256).max, false);
        vm.stopPrank();

        // lender balance after deposits (future balance impacts are due to kicking)
        assertEq(usdc.balanceOf(_lender), 47_000.000000 * 1e6);

        // borrower2 is a regular borrower in the pool
        vm.startPrank(_borrower2);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower2, 19.25 * 1e18, 7388, 2 * 1e18);
        vm.stopPrank();

        // borrower is the explointing actor, draws debt
        vm.startPrank(_borrower);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower, 9_711.0 * 1e18, 7388, 1_000 * 1e18);
        vm.stopPrank();

        skip(100 days);

        vm.startPrank(_lender);
        _ajnaPool.kick(_borrower, 3887);
        vm.stopPrank();

        skip(6.4 hours);

        (
            ,
            ,
            ,
            uint256 auctionKickTime,
            uint256 auctionReferencePrice,
            ,
            ,
            ,
        ) = _ajnaPool.auctionInfo(_borrower);

        // auction price is below external market price, meaning this is unlikely to happen
        assertEq(9.881046439965794000 * 1e18, _auctionPrice(auctionReferencePrice, auctionKickTime));

        uint256 snapshot = vm.snapshot();

        // deposit into 10x price bucket 100_33
        vm.startPrank(_borrower);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(9_730 * 1e18, 3232, type(uint256).max, false);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.bucketTake(_borrower, false, 3232);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.removeCollateral(998.152979445346260209 * 1e18, 3232);
        vm.stopPrank();

        (
            uint256 lp,
            uint256 collateral,
            uint256 bankruptcyTime,
            uint256 deposit,
            uint256 scale
        ) = _ajnaPool.bucketInfo(3232);

        assertEq(lp, 147.302784519210463820 * 1e18);
        assertEq(collateral, 1.468148188317963756 * 1e18);
        assertEq(deposit, 5);

        // borrower LP post borrower removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _borrower);
        assertEq(lp, 0.000000000000000051 * 1e18);

        // kicker LP post borrower removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 147.302784519210463769 * 1e18);

        vm.startPrank(_lender);
        _ajnaPool.removeCollateral(1.468148188317963755 * 1e18, 3232);
        vm.stopPrank();

        // kicker LP post kicker removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 0.000000000000000054 * 1e18);

        // borrower lost 19 USDC | 1.847020555 weth (@ 15 USDC = 27.70530833 USDC) = 46.70530833 USDC w/ arbTake
        assertEq(usdc.balanceOf(_borrower), 2_981.000000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 1_998.152979445346260209 * 1e18);

        // kicker (_lender) makes less with arb take
        (uint256 kickerClaimable, uint256 kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0 * 1e18,   kickerClaimable);
        assertEq(149.593278157167041134 * 1e18, kickerLocked);

        // kicker bal (22.02222282 + 46,850.406721 + 149.593278157167041134) = 47022.022218157
        // kicker gains  22.02222282 USDC
        assertEq(usdc.balanceOf(_lender), 46_850.406721 * 1e6);
        assertEq(weth.balanceOf(_lender), 1.468148188317963755 * 1e18); // (@ 15 USDC = 22.02222282 USDC)

        vm.revertTo(snapshot);

        // borrower uses some of his initial QT to take
        vm.startPrank(_borrower);
        _ajnaPool.take(_borrower, 1000.0 * 1e18, _borrower, new bytes(0));
        vm.stopPrank();

        // borrower lost 170.04644 USDC with take
        assertEq(usdc.balanceOf(address(_borrower)), 2_829.953560 * 1e6);
        assertEq(weth.balanceOf(address(_borrower)), 2_000.0 * 1e18);

        // kicker (_lender) bond is larger with take
        (kickerClaimable, kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0 * 1e18,   kickerClaimable);
        assertEq(296.951892783400907825 * 1e18, kickerLocked);

        // kicker bal (46,850.406721 + 296.951892783400907825) = 47147.358613783
        // kicker gains 147.358613783 USDC
        assertEq(usdc.balanceOf(_lender), 46_850.406721 * 1e6);
        assertEq(weth.balanceOf(_lender), 0); // (@ 15 USDC = 22.02222282 USDC)
    }
    
    function testBorrowerLittlePenaltyArbTakeHigherAuctionPrice() external {

        // External market price is 1 WETH @ 9.92 USDC 

        // assert Borrower balances
        assertEq(usdc.balanceOf(_borrower), 3_000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 2000.0 * 1e18);

        // assert Kicker (_lender) balances
        assertEq(usdc.balanceOf(_lender), 120_000.000000 * 1e6);
        assertEq(weth.balanceOf(_lender), 0 * 1e18);

        // add liquidity to the Ajna pool
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(2_000 * 1e18, _i9_91, type(uint256).max, false);
        _ajnaPool.addQuoteToken(5_000 * 1e18, 3698, type(uint256).max, false);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700, type(uint256).max, false);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702, type(uint256).max, false);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704, type(uint256).max, false);
        vm.stopPrank();

        // lender balance after deposits (future balance impacts are due to kicking)
        assertEq(usdc.balanceOf(_lender), 47_000.000000 * 1e6);

        // borrower2 is a regular borrower in the pool
        vm.startPrank(_borrower2);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower2, 19.25 * 1e18, 7388, 2 * 1e18);
        vm.stopPrank();

        // borrower is the explointing actor, draws debt
        vm.startPrank(_borrower);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower, 9_711.0 * 1e18, 7388, 1_000 * 1e18);
        vm.stopPrank();

        skip(100 days);

        vm.startPrank(_lender);
        _ajnaPool.kick(_borrower, 3887);
        vm.stopPrank();

        skip(6.38 hours);

        (
            ,
            ,
            ,
            uint256 auctionKickTime,
            uint256 auctionReferencePrice,
            uint256 neutralPrice,
            ,
            ,
        ) = _ajnaPool.auctionInfo(_borrower);

        assertEq(9.949774553091739272 * 1e18, _auctionPrice(auctionReferencePrice, auctionKickTime));
        assertEq(11.350341791238016630 * 1e18 , neutralPrice);

        uint256 snapshot = vm.snapshot();

        // deposit into 10x price bucket 100_33
        vm.startPrank(_borrower);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(9_808 * 1e18, 3232, type(uint256).max, false);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.bucketTake(_borrower, false, 3232);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.removeCollateral(998.556468141527261759 * 1e18, 3232);
        vm.stopPrank();

        (
            uint256 lp,
            uint256 collateral,
            uint256 bankruptcyTime,
            uint256 deposit,
            uint256 scale
        ) = _ajnaPool.bucketInfo(3232);

        assertEq(lp, 141437867054818765556);
        assertEq(collateral, 1409693299103984831);
        assertEq(deposit, 2);

        // borrower LP post borrower removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _borrower);
        assertEq(lp, 93);

        // kicker LP post borrower removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 141.437867054818765463 * 1e18);

        vm.startPrank(_lender);
        _ajnaPool.removeCollateral(1.409693299103984830 * 1e18, 3232);
        vm.stopPrank();

        // kicker LP post kicker removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 9);

        // borrower lost  97 USDC | 1.443531858 weth (@ 9.92 USDC = 14.319836031 USDC) = 111.319836031 USDC w/ arbTake
        assertEq(usdc.balanceOf(_borrower), 2903.000000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 1998.556468141527261759 * 1e18);

        // kicker (_lender) makes less with arb take
        (uint256 kickerClaimable, uint256 kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0 * 1e18,   kickerClaimable);
        assertEq(149.593278157167041134 * 1e18, kickerLocked);

        // kicker bal (13.984157527 + 46,850.406721 + 149.593278157167041134) = 47013.98415668447013.984156684
        // kicker gains  13.98415668447013 USDC
        assertEq(usdc.balanceOf(_lender), 46_850.406721 * 1e6);
        assertEq(weth.balanceOf(_lender), 1.409693299103984830 * 1e18); // (@ 9.92 USDC = 13.984157527 USDC)

        vm.revertTo(snapshot);

        // borrower uses some of his initial QT to take
        vm.startPrank(_borrower);
        _ajnaPool.take(_borrower, 1000.0 * 1e18, _borrower, new bytes(0));
        vm.stopPrank();

        // borrower lost 238.774554 USDC with take
        assertEq(usdc.balanceOf(address(_borrower)), 2761.225446 * 1e6);
        assertEq(weth.balanceOf(address(_borrower)), 2_000.0 * 1e18);

        // kicker (_lender) bond is larger with take
        (kickerClaimable, kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0 * 1e18,   kickerClaimable);
        assertEq(291.035931427605772341 * 1e18, kickerLocked);

        // kicker bal (46,850.406721 + 291.035931427605772341) = 47141.442652428
        // kicker gains 141.442652428 USDC
        assertEq(usdc.balanceOf(_lender), 46_850.406721 * 1e6);
        assertEq(weth.balanceOf(_lender), 0);
        
    }        
}