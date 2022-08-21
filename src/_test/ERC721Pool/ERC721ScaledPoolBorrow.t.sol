// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }               from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC721ScaledBorrowTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    address internal _collectionPoolAddress;
    address internal _subsetPoolAddress;

    NFTCollateralToken internal _collateral;
    QuoteToken         internal _quote;
    ERC721Pool         internal _collectionPool;
    ERC721Pool         internal _subsetPool;

    function setUp() external {
        // deploy token and user contracts; mint and set balances
        _collateral = new NFTCollateralToken();
        _quote      = new QuoteToken();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        _collateral.mint(address(_borrower),  52);
        _collateral.mint(address(_borrower2), 10);
        _collateral.mint(address(_borrower3), 13);

        deal(address(_quote), _lender, 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _collectionPool        = ERC721Pool(_collectionPoolAddress);

        vm.startPrank(_borrower);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_borrower3);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Subset State ***/
        /*******************************/

        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;

        _subsetPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds, 0.05 * 10**18);
        _subsetPool        = ERC721Pool(_subsetPoolAddress);

        changePrank(_borrower);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_borrower3);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);
    }

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    // TODO: skip block number ahead as well
    function testBorrowerInterestAccumulation() external {
        changePrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2553);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2554);

        skip(864000);

        // borrower adds collateral and borrows initial amount
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));
        _subsetPool.borrow(5_000 * 1e18, 2551, address(0), address(0));

        assertEq(_subsetPool.borrowerDebt(), 5_004.807692307692310000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256[] memory col, uint256 inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        5_004.807692307692310000 * 1e18);
        assertEq(pendingDebt, 5_010.981808339947401080 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1 * 1e18);

        // borrower pledge additional collateral after some time has passed
        skip(864000);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));
        assertEq(_subsetPool.borrowerDebt(), 5_017.163540990287215539 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        5_017.163540990287215539 * 1e18);
        assertEq(pendingDebt, 5_017.163540990287215539 * 1e18);
        assertEq(col.length,  4);
        assertEq(inflator,    1.002468795894312911 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(864000);
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        _subsetPool.pullCollateral(tokenIdsToRemove, address(0), address(0));
        assertEq(_subsetPool.borrowerDebt(), 5_022.733620349293441850 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        5_022.733620349293441850 * 1e18);
        assertEq(pendingDebt, 5_022.733620349293441850 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.003581741625987546 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(864000);
        _subsetPool.borrow(1_000 * 1e18, 3000, address(0), address(0));
        assertEq(_subsetPool.borrowerDebt(), 6_028.452940372539936903 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        6_028.452940372539936903 * 1e18);
        assertEq(pendingDebt, 6_028.452940372539936903 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.004584449181064656 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(864000);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        _subsetPool.repay(pendingDebt, address(0), address(0));
        assertEq(_subsetPool.borrowerDebt(), 0);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(col.length,  3);
        assertEq(inflator,    1.005487742520903760 * 1e18);

    }

    // TODO: finish implementing
    function testMultipleBorrowerInterestAccumulation() external {

    }

    function testBorrowLimitReached() external {
        // lender deposits 10000 Quote into 3 buckets
        changePrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // should revert if insufficient quote available before limit price
        vm.expectRevert("S:B:LIMIT_REACHED");
        _subsetPool.borrow(21_000 * 1e18, 2551, address(0), address(0));
    }

    // TODO: finish implementing
    function testBorrowBorrowerUnderCollateralized() external {

    }

    // TODO: finish implementing
    function testBorrowPoolUnderCollateralized() external {

    }

    function testBorrowAndRepay() external {
        // lender deposits 10000 Quote into 3 buckets
        changePrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);

        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(address(_borrower)), 52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        assertEq(_quote.balanceOf(address(_subsetPool)),   30_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 0);

        // check pool state
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        assertEq(_subsetPool.poolSize(),              30_000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          0);
        assertEq(_subsetPool.lenderDebt(),            0);
        assertEq(_subsetPool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), 0);
        assertEq(_subsetPool.poolMinDebtAmount(),     0);
        assertEq(_subsetPool.exchangeRate(2550),      1 * 1e27);

        // check initial bucket state
        (uint256 lpAccumulator, uint256 availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // borrower deposits three NFTs into the subset pool
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _subsetPool.pledgeCollateral(tokenIdsToAdd, address(0), address(0));

        // borrower borrows from the pool
        uint256 borrowAmount = 3_000 * 1e18;
        emit Borrow(address(_borrower), _subsetPool.indexToPrice(2550), borrowAmount);
        _subsetPool.borrow(borrowAmount, 2551, address(0), address(0));

        // check token balances after borrow
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)),   27_000 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), borrowAmount);

        // check pool state after borrow
        assertEq(_subsetPool.htp(), 1_000.961538461538462000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.poolSize(),              30_000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          3_002.88461538461538600 * 1e18);
        assertEq(_subsetPool.lenderDebt(),            borrowAmount);
        assertEq(_subsetPool.poolTargetUtilization(), 1 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), .100096153846153846 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(),     300.288461538461538600 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(), _subsetPool.borrowerDebt() / 10);
        assertEq(_subsetPool.exchangeRate(2550),      1 * 1e27);

        // check bucket state after borrow
        (lpAccumulator, availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // check borrower info after borrow
        (uint256 debt, uint256 pendingDebt, uint256[] memory col, uint256 inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        3_002.884615384615386000 * 1e18);
        assertEq(pendingDebt, 3_002.884615384615386000 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1 * 1e18);

        // pass time to allow interest to accumulate
        skip(864000);

        // borrower partially repays half their loan
        emit Repay(address(_borrower), _subsetPool.indexToPrice(2550), borrowAmount / 2);
        _subsetPool.repay(borrowAmount / 2, address(0), address(0));

        // check token balances after partial repay
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)),   28_500 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), borrowAmount / 2);

        // check pool state after partial repay
        assertEq(_subsetPool.htp(), 503.711801848228267897 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        // check utilization changes make sense
        assertEq(_subsetPool.poolSize(),              30_003.704723414134980000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          1507.000974733654242290 * 1e18);
        assertEq(_subsetPool.lenderDebt(),            1_503.492337444756410000 * 1e18);
        assertEq(_subsetPool.poolTargetUtilization(), .166838815387959167 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), .050227163232866662 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(),     150.700097473365424229 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(),     _subsetPool.borrowerDebt() / 10);
        assertEq(_subsetPool.exchangeRate(2550),      1.000123490780471166000000000 * 1e27);

        // check bucket state after partial repay
        (lpAccumulator, availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // check borrower info after partial repay
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        1_507.000974733654242290 * 1e18);
        assertEq(pendingDebt, 1_507.000974733654242290 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.001370801704450980 * 1e18);

        // pass time to allow additional interest to accumulate
        skip(864000);

        // find pending debt after interest accumulation
        (, pendingDebt, , ) = _subsetPool.borrowerInfo(address(_borrower));

        // mint additional quote to allow borrower to repay their loan plus interest
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 1_000 * 1e18);

        // borrower repays their remaining loan balance
        emit Repay(address(_borrower), _subsetPool.indexToPrice(2550), pendingDebt);
        _subsetPool.repay(pendingDebt, address(0), address(0));

        // check token balances after fully repay
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(address(_borrower)), 49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)),   30_008.860066920758216978 * 1e18);
        assertEq(_quote.balanceOf(address(_borrower)), 991.139933079241783022 * 1e18);

        // check pool state after fully repay
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        // TODO: check target utilization
        // check utilization changes make sense
        assertEq(_subsetPool.poolSize(),              30_005.377906382528563727 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          0);
        assertEq(_subsetPool.lenderDebt(),            0);
        assertEq(_subsetPool.poolTargetUtilization(), .000000452724663788 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), 0);
        assertEq(_subsetPool.poolMinDebtAmount(),     0);
        assertEq(_subsetPool.exchangeRate(2550),      1.000179263546084285000000000 * 1e27);

        // check bucket state after fully repay
        (lpAccumulator, availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // TODO: check should the inflator reset?
        // check borrower info after fully repay
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(address(_borrower));
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(col.length,  3);
        assertEq(inflator,    1.002606129793188157 * 1e18);
    }

    // TODO: add repay failure checks

}
