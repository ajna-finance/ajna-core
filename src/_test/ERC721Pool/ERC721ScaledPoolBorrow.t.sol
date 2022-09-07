// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

contract ERC721ScaledBorrowTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy collection pool
        _collectionPool = _deployCollectionPool();

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        _subsetPool = _deploySubsetPool(subsetTokenIds);

        address[] memory _poolAddresses = _getPoolAddresses();

        _mintAndApproveQuoteTokens(_poolAddresses, _lender, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_poolAddresses, _borrower, 52);
        _mintAndApproveCollateralTokens(_poolAddresses, _borrower2, 10);
        _mintAndApproveCollateralTokens(_poolAddresses, _borrower3, 13);

        // TODO: figure out how to generally approve quote tokens for the borrowers to handle repays
        // TODO: potentially use _approveQuoteMultipleUserMultiplePool()
        vm.prank(_borrower);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);
        vm.prank(_borrower);
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
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _subsetPool.borrow(5_000 * 1e18, 2551);

        assertEq(_subsetPool.borrowerDebt(), 5_004.807692307692310000 * 1e18);
        (uint256 debt, uint256 pendingDebt, uint256[] memory col, uint256 inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        5_004.807692307692310000 * 1e18);
        assertEq(pendingDebt, 5_010.981808341113791532 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1 * 1e18);

        // borrower pledge additional collateral after some time has passed
        skip(864000);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 51;
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        assertEq(_subsetPool.borrowerDebt(), 5_017.163540992622874208 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        5_017.163540992622874208 * 1e18);
        assertEq(pendingDebt, 5_017.163540992622874208 * 1e18);
        assertEq(col.length,  4);
        assertEq(inflator,    1.002468795894779594 * 1e18);

        // borrower pulls some of their collateral after some time has passed
        skip(864000);
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 1;
        _subsetPool.pullCollateral(tokenIdsToRemove);
        assertEq(_subsetPool.borrowerDebt(), 5_022.733620353117867729 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        5_022.733620353117867729 * 1e18);
        assertEq(pendingDebt, 5_022.733620353117867729 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.003581741626751696 * 1e18);

        // borrower borrows some additional quote after some time has passed
        skip(864000);
        _subsetPool.borrow(1_000 * 1e18, 3000);
        assertEq(_subsetPool.borrowerDebt(), 6_028.452940379879069654 * 1e18);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        6_028.452940379879069654 * 1e18);
        assertEq(pendingDebt, 6_028.452940379879069654 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.004584449182531072 * 1e18);

        // mint additional quote to borrower to enable repayment
        deal(address(_quote), _borrower, 20_000 * 1e18);

        // borrower repays their loan after some additional time
        skip(864000);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        _subsetPool.repay(_borrower, pendingDebt);
        assertEq(_subsetPool.borrowerDebt(), 0);
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(col.length,  3);
        assertEq(inflator,    1.005487742522395296 * 1e18);

    }

    function testMultipleBorrowerInterestAccumulation() external {
        // lender deposits 10000 Quote into 3 buckets
        changePrank(_lender);
        assertEq(_subsetPool.indexToPrice(2550), 3_010.892022197881557845 * 1e18);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        assertEq(_subsetPool.indexToPrice(2551), 2_995.912459898389633881 * 1e18);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);
        skip(2 hours);

        // borrower pledges three NFTs and takes out a loan with TP around 2666
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        uint256 borrowAmount = 8_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, _subsetPool.indexToPrice(2550), borrowAmount);
        _subsetPool.borrow(borrowAmount, 2551);
        skip(4 hours);

        // borrower 2 pledges one NFT and takes out a loan with TP around 2750
        changePrank(_borrower2);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _subsetPool.pledgeCollateral(_borrower2, tokenIdsToAdd);
        borrowAmount = 2_750 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower2, _subsetPool.indexToPrice(2551), borrowAmount);
        _subsetPool.borrow(borrowAmount, 3000);
        skip(4 hours);

        // borrower 3 pledges one NFT and takes out a loan with TP around 2500
        changePrank(_borrower3);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 73;
        _subsetPool.pledgeCollateral(_borrower3, tokenIdsToAdd);
        borrowAmount = 2_500 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower3, _subsetPool.indexToPrice(2551), borrowAmount);
        _subsetPool.borrow(borrowAmount, 3000);
        skip(4 hours);

        // trigger an interest accumulation
        changePrank(_lender);
        _subsetPool.addQuoteToken(1 * 1e18, 2550);

        // check pool and borrower debt to confirm interest has accumulated
        assertEq(_subsetPool.borrowerDebt(), 13_263.563121817930264782 * 1e18);
        (uint256 debt, uint256 pendingDebt, , ) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        8_007.692307692307696000 * 1e18);
        assertEq(pendingDebt, 8_007.692307692307696000 * 1e18);
        (debt, pendingDebt, , ) = _subsetPool.borrowerInfo(_borrower2);
        assertEq(debt,        2_752.644230769230770500 * 1e18);
        assertEq(pendingDebt, 2_752.644230769230770500 * 1e18);
        (debt, pendingDebt, , ) = _subsetPool.borrowerInfo(_borrower3);
        assertEq(debt,        2_502.403846153846155000 * 1e18);
        assertEq(pendingDebt, 2_502.403846153846155000 * 1e18);
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
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // should revert if insufficient quote available before limit price
        vm.expectRevert(IScaledPool.BorrowLimitIndexReached.selector);
        _subsetPool.borrow(21_000 * 1e18, 2551);
    }

    function testBorrowBorrowerUnderCollateralized() external {
        // add initial quote to the pool
        changePrank(_lender);
        assertEq(_subsetPool.indexToPrice(3575), 18.133510183516748631 * 1e18);
        _subsetPool.addQuoteToken(1_000 * 1e18, 3575);

        // borrower pledges some collateral
        changePrank(_borrower);
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 5;
        tokenIdsToAdd[1] = 3;
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // should revert if borrower did not deposit enough collateral
        vm.expectRevert(IScaledPool.BorrowBorrowerUnderCollateralized.selector);
        _subsetPool.borrow(40 * 1e18, 4000);
    }

    function testBorrowPoolUnderCollateralized() external {
        // add initial quote to the pool
        changePrank(_lender);
        assertEq(_subsetPool.indexToPrice(3232), 100.332368143282009890 * 1e18);
        _subsetPool.addQuoteToken(1_000 * 1e18, 3232);

        // should revert if borrow would result in pool under collateralization
        changePrank(_borrower);
        vm.expectRevert(IScaledPool.BorrowPoolUnderCollateralized.selector);
        _subsetPool.borrow(500 * 1e18, 4000);
    }

    function testBorrowAndRepay() external {
        // lender deposits 10000 Quote into 3 buckets
        vm.startPrank(_lender);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2552);

        // check initial token balances
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        assertEq(_quote.balanceOf(address(_subsetPool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            0);

        // check pool state
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        assertEq(_subsetPool.poolSize(),              30_000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          0);
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
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // borrower borrows from the pool
        uint256 borrowAmount = 3_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(_borrower, _subsetPool.indexToPrice(2550), borrowAmount);
        _subsetPool.borrow(borrowAmount, 2551);

        // check token balances after borrow
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            borrowAmount);

        // check pool state after borrow
        assertEq(_subsetPool.htp(), 1_000.961538461538462000 * 1e18);
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        assertEq(_subsetPool.poolSize(),              30_000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          3_002.88461538461538600 * 1e18);
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
        (uint256 debt, uint256 pendingDebt, uint256[] memory col, uint256 inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        3_002.884615384615386000 * 1e18);
        assertEq(pendingDebt, 3_002.884615384615386000 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1 * 1e18);

        // pass time to allow interest to accumulate
        skip(10 days);

        // borrower partially repays half their loan
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, _subsetPool.indexToPrice(2550), borrowAmount / 2);
        _subsetPool.repay(_borrower, borrowAmount / 2);

        // check token balances after partial repay
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)), 28_500 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            borrowAmount / 2);

        // check pool state after partial repay
        assertEq(_subsetPool.htp(), 502.333658244714424687 * 1e18); // HTP should be different than t0 TP recorded in TP queue
        assertEq(_subsetPool.lup(), _subsetPool.indexToPrice(2550));

        // check utilization changes make sense
        assertEq(_subsetPool.poolSize(),              30_003.704723414575110000 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          1507.000974734143274062 * 1e18);
        assertEq(_subsetPool.poolTargetUtilization(), .166838815388013307 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), .050227163232882224 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(),     150.700097473414327406 * 1e18);
        assertEq(_subsetPool.poolMinDebtAmount(),     _subsetPool.borrowerDebt() / 10);
        assertEq(_subsetPool.exchangeRate(2550),      1.000123490780485837000000000 * 1e27);

        // check bucket state after partial repay
        (lpAccumulator, availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // check borrower info after partial repay
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        1_507.000974734143274062 * 1e18);
        assertEq(pendingDebt, 1_507.000974734143274062 * 1e18);
        assertEq(col.length,  3);
        assertEq(inflator,    1.001370801704613834 * 1e18);

        // pass time to allow additional interest to accumulate
        skip(10 days);

        // find pending debt after interest accumulation
        (, pendingDebt, , ) = _subsetPool.borrowerInfo(_borrower);

        // mint additional quote to allow borrower to repay their loan plus interest
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 1_000 * 1e18);

        // borrower repays their remaining loan balance
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, BucketMath.MAX_PRICE, pendingDebt);
        _subsetPool.repay(_borrower, pendingDebt);

        // check token balances after fully repay
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)), 30_008.860066921599064643 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            991.139933078400935357 * 1e18);

        // check pool state after fully repay
        assertEq(_subsetPool.htp(), 0);
        assertEq(_subsetPool.lup(), BucketMath.MAX_PRICE);

        // borrower pulls collateral
        uint256[] memory tokenIdsToRemove = tokenIdsToAdd;
        vm.expectEmit(true, true, false, true);
        emit PullCollateralNFT(_borrower, tokenIdsToRemove);
        _subsetPool.pullCollateral(tokenIdsToRemove);
        assertEq(_subsetPool.pledgedCollateral(), 0);
        assertEq(_collateral.balanceOf(_borrower),            52);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 0);

        // check utilization changes make sense
        assertEq(_subsetPool.poolSize(),              30_005.377906383285317363 * 1e18);
        assertEq(_subsetPool.borrowerDebt(),          0);
        // TODO: LUP=MAX_PRICE is causing a technically correct yet undesirable target utilization
        assertEq(_subsetPool.debtEma(),               116.548760023014994270 * 1e18);
        assertEq(_subsetPool.lupColEma(),             257_438_503.676217090117659874 * 1e18);
        assertEq(_subsetPool.poolTargetUtilization(), .000000452724663788 * 1e18);
        assertEq(_subsetPool.poolActualUtilization(), 0);
        assertEq(_subsetPool.poolMinDebtAmount(),     0);
        assertEq(_subsetPool.exchangeRate(2550),      1.000179263546109511000000000 * 1e27);

        // check bucket state after fully repay
        (lpAccumulator, availableCollateral) = _subsetPool.buckets(2550);
        assertEq(lpAccumulator,       10_000 * 1e27);
        assertEq(availableCollateral, 0);

        // check borrower info after fully repay
        (debt, pendingDebt, col, inflator) = _subsetPool.borrowerInfo(_borrower);
        assertEq(debt,        0);
        assertEq(pendingDebt, 0);
        assertEq(col.length,  0);
    }

    function testScaledPoolRepayRequireChecks() external {
        // add initial quote to the pool
        changePrank(_lender);
        assertEq(_subsetPool.indexToPrice(2550), 3_010.892022197881557845 * 1e18);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2550);
        _subsetPool.addQuoteToken(10_000 * 1e18, 2551);

        // should revert if borrower has no debt
        deal(address(_quote), _borrower, _quote.balanceOf(_borrower) + 10_000 * 1e18);
        changePrank(_borrower);
        vm.expectRevert(IScaledPool.RepayNoDebt.selector);
        _subsetPool.repay(_borrower, 10_000 * 1e18);

        // borrower 1 borrows 1000 quote from the pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);
        _subsetPool.borrow(1_000 * 1e18, 3000);

        assertEq(_borrower, _subsetPool.maxBorrower());

        // borrower 2 borrows 3k quote from the pool and becomes new queue HEAD
        changePrank(_borrower2);
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _subsetPool.pledgeCollateral(_borrower2, tokenIdsToAdd);
        _subsetPool.borrow(3_000 * 1e18, 3000);

        assertEq(_borrower2, _subsetPool.maxBorrower());

        // should revert if amount left after repay is less than the average debt
        changePrank(_borrower);
        vm.expectRevert(IScaledPool.BorrowAmountLTMinDebt.selector);
        _subsetPool.repay(_borrower, 900 * 1e18);

        // should be able to repay loan if properly specified
        vm.expectEmit(true, true, false, true);
        emit Repay(_borrower, _subsetPool.lup(), 1_000.961538461538462000 * 1e18);
        _subsetPool.repay(_borrower, 1_100 * 1e18);
    }

    function testRepayLoanFromDifferentActor() external {
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
        _subsetPool.pledgeCollateral(_borrower, tokenIdsToAdd);

        // borrower borrows from the pool
        _subsetPool.borrow(3_000 * 1e18, 2551);

        // check token balances after borrow
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),              170_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            3_000 * 1e18);

        // pass time to allow interest to accumulate
        skip(10 days);

        // lender partially repays borrower's loan
        changePrank(_lender);
        _subsetPool.repay(_borrower, 1_500 * 1e18);

        // check token balances after partial repay
        assertEq(_subsetPool.pledgedCollateral(), Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_subsetPool)), 3);

        assertEq(_quote.balanceOf(address(_subsetPool)), 28_500 * 1e18);
        assertEq(_quote.balanceOf(_lender),              168_500 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            3_000 * 1e18);
    }
}
