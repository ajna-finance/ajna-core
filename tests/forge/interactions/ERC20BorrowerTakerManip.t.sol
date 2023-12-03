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
    PoolInfoUtils internal _infoUtils;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _taker;

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
        _taker    = makeAddr("taker");

        // fund lenders with quote token
        deal(USDC, _lender, 120_000.0 * 1e6);
        deal(USDC, _taker,  120_000.0 * 1e6);

        // fund borrower
        deal(WETH, _borrower,  2_000.0 * 1e18);
        deal(USDC, _borrower,  10_000.0 * 1e6);

        // fund borrower2
        deal(WETH, _borrower2,  2 * 1e18);
    }


    function testBorrowerArbTakeLittlePenalty() external {

        // External market price is 1 WETH @ 15 USDC 

        // assert Borrower balances
        assertEq(usdc.balanceOf(_borrower), 10_000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 2000.0 * 1e18);

        // assert Kicker (_lender) balances
        assertEq(usdc.balanceOf(_lender), 120_000.000000 * 1e6);
        assertEq(weth.balanceOf(_lender), 0 * 1e18);

        // add liquidity to the Ajna pool
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(7_000 * 1e18, _i9_81, type(uint256).max);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700, type(uint256).max);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702, type(uint256).max);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704, type(uint256).max);
        vm.stopPrank();

        // lender balance after deposits (future balance impacts are due to kicking)
        assertEq(usdc.balanceOf(_lender), 47_000.000000 * 1e6);

        // borrower2 is a regular borrower in the pool
        vm.startPrank(_borrower2);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower2, 18.0 * 1e18, 7388, 2 * 1e18);
        vm.stopPrank();

        // borrower is the explointing actor, draws debt
        vm.startPrank(_borrower);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower, 9_300.0 * 1e18, 7388, 1_000 * 1e18);
        vm.stopPrank();

        skip(100 days);

        vm.startPrank(_lender);
        _ajnaPool.kick(_borrower, 3887);
        vm.stopPrank();

        skip(6.2 hours);

        (
            ,
            ,
            ,
            uint256 auctionKickTime,
            uint256 auctionReferencePrice,
            uint256 neutralPrice,
            uint256 thresholdPrice,
            ,
            ,
        ) = _ajnaPool.auctionInfo(_borrower);

        // auction price is below external market price, meaning this is unlikely to happen
        assertEq(9.789817054040823232 * 1e18, _auctionPrice(auctionReferencePrice, auctionKickTime));
        assertEq(10.492466121606186168 * 1e18, neutralPrice);
        assertEq(9.437339490258162853 * 1e18, thresholdPrice);

        uint256 snapshot = vm.snapshot();

        // deposit into 10x price bucket 100_33
        vm.startPrank(_borrower);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(9_599.613713492040293515 * 1e18, 3232, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.bucketTake(_borrower, false, 3232);
        vm.stopPrank();

        vm.startPrank(_borrower);
        _ajnaPool.removeCollateral(980.469161017685997533 * 1e18, 3232);
        vm.stopPrank();

        (
            uint256 lp,
            uint256 collateral,
            uint256 bankruptcyTime,
            uint256 deposit,
            uint256 scale
        ) = _ajnaPool.bucketInfo(3232);

        assertEq(lp, 0.605494834822718483 * 1e18);
        assertEq(collateral, 0 * 1e18);
        assertEq(deposit, 0.605494834822718484 * 1e18);

        vm.startPrank(_borrower);
        _ajnaPool.removeQuoteToken(0.605494834822718484 * 1e18, 3232);
        vm.stopPrank();

        // borrower LP post borrower removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _borrower);
        assertEq(lp, 0 * 1e18);

        // kicker LP post borrower removal, NO LP reward since the bucket price is high
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 0);

        // borrower lost 299 USDC | 19.5 weth (@ 15 USDC = 292.5 USDC) =  591.5 USDC w/ arbTake
        assertEq(usdc.balanceOf(_borrower), 9_700.991781 * 1e6);
        assertEq(weth.balanceOf(_borrower), 1_980.469161017685997533 * 1e18);

        // kicker (_lender) makes less with arb take
        (uint256 kickerClaimable, uint256 kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0,   kickerClaimable);
        assertEq(0, kickerLocked);

        // kicker loss (47,000 - 46_894.487336) = 105.512664
        assertEq(usdc.balanceOf(_lender), 46894.487336 * 1e6);
        assertEq(weth.balanceOf(_lender), 0); 

        vm.revertTo(snapshot);

        // borrower uses some of his initial QT to take
        vm.startPrank(_borrower);
        _ajnaPool.take(_borrower, 1000.0 * 1e18, _borrower, new bytes(0));
        vm.stopPrank();

        // borrower lost 506.740552 USDC with take
        assertEq(usdc.balanceOf(address(_borrower)), 9746.629724 * 1e6); // loss of 253.370276  
        assertEq(weth.balanceOf(address(_borrower)), 1975.847681578175846340 * 1e18); // (@ 15 USDC = loss of 362.284776327 USDC)

        // kicker (_lender) bond is larger with take
        (kickerClaimable, kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(176.641467210861091754 * 1e18,   kickerClaimable);
        assertEq(0, kickerLocked);

        // kicker bal (46_894.487336 + 176.641467210861091754 ) = 47071.128803211
        // kicker gains 71.128803211 USDC
        assertEq(usdc.balanceOf(_lender), 46_894.487336 * 1e6);
        assertEq(weth.balanceOf(_lender), 0);
    }

    function testTakerArbTakeMaxCollateralDebtBound() external {

        // External market price is 1 WETH @ 15 USDC 

        // assert Borrower balances
        assertEq(usdc.balanceOf(_borrower), 10_000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 2000.0 * 1e18);

        // assert Kicker (_lender) balances
        assertEq(usdc.balanceOf(_lender), 120_000.000000 * 1e6);
        assertEq(weth.balanceOf(_lender), 0 * 1e18);

        // add liquidity to the Ajna pool
        vm.startPrank(_lender);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(7_000 * 1e18, _i9_81, type(uint256).max);
        _ajnaPool.addQuoteToken(11_000 * 1e18, 3700, type(uint256).max);
        _ajnaPool.addQuoteToken(25_000 * 1e18, 3702, type(uint256).max);
        _ajnaPool.addQuoteToken(30_000 * 1e18, 3704, type(uint256).max);
        vm.stopPrank();

        // lender balance after deposits (future balance impacts are due to kicking)
        assertEq(usdc.balanceOf(_lender), 47_000.000000 * 1e6);

        // borrower2 is a regular borrower in the pool
        vm.startPrank(_borrower2);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower2, 18.0 * 1e18, 7388, 2 * 1e18);
        vm.stopPrank();

        // exploited borrower draws debt
        vm.startPrank(_borrower);
        weth.approve(address(_ajnaPool), type(uint256).max);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.drawDebt(_borrower, 9_300.0 * 1e18, 7388, 1_000 * 1e18);
        vm.stopPrank();

        skip(100 days);

        vm.startPrank(_lender);
        _ajnaPool.kick(_borrower, 3887);
        vm.stopPrank();

        skip(5 hours);

        (
            ,
            ,
            ,
            uint256 auctionKickTime,
            uint256 auctionReferencePrice,
            uint256 neutralPrice,
            uint256 thresholdPrice,
            ,
            ,
        ) = _ajnaPool.auctionInfo(_borrower);

        // auction price is below external market price, meaning this is unlikely to happen
        assertEq(14.838587891915696852 * 1e18, _auctionPrice(auctionReferencePrice, auctionKickTime));
        assertEq(10.492466121606186168 * 1e18, neutralPrice);
        assertEq(9.437339490258162853 * 1e18, thresholdPrice);

        uint256 snapshot = vm.snapshot();

        // deposit into 10x price bucket 100_33
        vm.startPrank(_taker);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.addQuoteToken(9_599.613713492040293515 * 1e18, 3232, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(_taker);
        _ajnaPool.bucketTake(_borrower, false, 3232);
        vm.stopPrank();

        (uint256 borrowerDebt, uint256 borrowerCollateral,) = _ajnaPool.borrowerInfo(_borrower);

        //  proof take is debt bound
        assertEq(borrowerDebt, 0);
        assertEq(borrowerCollateral, 353.135580416835362763 * 1e18);

        vm.startPrank(_taker);
        _ajnaPool.removeCollateral(646.864419583164637237 * 1e18, 3232);
        vm.stopPrank();

        (
            uint256 lp,
            uint256 collateral,
            uint256 bankruptcyTime,
            uint256 deposit,
            uint256 scale
        ) = _ajnaPool.bucketInfo(3232);

        assertEq(lp, 0.664664189041246530 * 1e18);
        assertEq(collateral, 0 * 1e18);
        assertEq(deposit, 0.664664189041246530 * 1e18);

        vm.startPrank(_taker);
        _ajnaPool.removeQuoteToken(0.664664189041246530 * 1e18, 3232);
        vm.stopPrank();

        // taker LP post removal
        (lp, ) = _ajnaPool.lenderInfo(3232, _taker);
        assertEq(lp, 0 * 1e18);

        // kicker LP post borrower removal, NO LP reward since the bucket price is high
        (lp, ) = _ajnaPool.lenderInfo(3232, _lender);
        assertEq(lp, 0);

        // borrower balances
        assertEq(usdc.balanceOf(_borrower), 19300.000000 * 1e6);
        assertEq(weth.balanceOf(_borrower), 1000.0 * 1e18);

        // taker 
        assertEq(usdc.balanceOf(_taker), 110_401.050951 * 1e6);
        assertEq(weth.balanceOf(_taker), 646.864419583164637237 * 1e18);

        // kicker balances
        (uint256 kickerClaimable, uint256 kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0, kickerClaimable);
        assertEq(0, kickerLocked);
        assertEq(usdc.balanceOf(_lender), 46894.487336 * 1e6);
        assertEq(weth.balanceOf(_lender), 0); 
        
        vm.revertTo(snapshot);

        // borrower uses some of his initial QT to take
        vm.startPrank(_taker);
        usdc.approve(address(_ajnaPool), type(uint256).max);
        _ajnaPool.take(_borrower, 1000.0 * 1e18, _taker, new bytes(0));
        vm.stopPrank();

        (borrowerDebt, borrowerCollateral,) = _ajnaPool.borrowerInfo(_borrower);

        //  proof take is debt bound
        assertEq(borrowerDebt, 0);
        assertEq(borrowerCollateral, 353.135580416835362763 * 1e18);

        // borrower lost 506.740552 USDC with take
        assertEq(usdc.balanceOf(address(_borrower)), 19300.000000 * 1e6); // loss of 253.370276  
        assertEq(weth.balanceOf(address(_borrower)), 1000.0 * 1e18); // (@ 15 USDC = loss of 362.284776327 USDC)

        // taker balance
        assertEq(usdc.balanceOf(address(_taker)), 110401.445455 * 1e6); // loss of 253.370276  
        assertEq(weth.balanceOf(address(_taker)), 646.864419583164637237 * 1e18); // (@ 15 USDC = loss of 362.284776327 USDC)

        // kicker (_lender) bond is larger with take
        (kickerClaimable, kickerLocked) = _ajnaPool.kickerInfo(_lender);
        assertEq(0,   kickerClaimable);
        assertEq(0, kickerLocked);

        // kicker bal (46_894.487336 + 176.641467210861091754 ) = 47071.128803211
        // kicker gains 71.128803211 USDC
        assertEq(usdc.balanceOf(_lender), 46_894.487336 * 1e6);
        assertEq(weth.balanceOf(_lender), 0);
    }
    
}