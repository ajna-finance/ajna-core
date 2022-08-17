// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }                             from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

contract ERC721ScaledBorrowTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                     internal _collectionPoolAddress;
    address                     internal _subsetPoolAddress;
    NFTCollateralToken          internal _collateral;
    ERC721Pool                  internal _collectionPool;
    ERC721Pool                  internal _subsetPool;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower;
    UserWithNFTCollateral       internal _borrower2;
    UserWithNFTCollateral       internal _borrower3;
    UserWithQuoteTokenInNFTPool internal _lender;
    UserWithQuoteTokenInNFTPool internal _lender2;

    function setUp() external {
        // deploy token and user contracts; mint tokens
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _borrower   = new UserWithNFTCollateral();
        _borrower2  = new UserWithNFTCollateral();
        _borrower3  = new UserWithNFTCollateral();
        _lender     = new UserWithQuoteTokenInNFTPool();
        _lender2    = new UserWithQuoteTokenInNFTPool();

        _collateral.mint(address(_borrower), 52);
        _collateral.mint(address(_borrower2), 10);
        _collateral.mint(address(_borrower3), 13);
        _quote.mint(address(_lender), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _collectionPool        = ERC721Pool(_collectionPoolAddress);

        _borrower.approveCollection(_collateral, address(_collectionPool));
        _borrower2.approveCollection(_collateral, address(_collectionPool));
        _borrower3.approveCollection(_collateral, address(_collectionPool));

        _borrower.approveQuoteToken(_quote, address(_collectionPool), 200_000 * 1e18);
        _borrower2.approveQuoteToken(_quote, address(_collectionPool), 200_000 * 1e18);
        _borrower3.approveQuoteToken(_quote,   address(_collectionPool), 200_000 * 1e18);
        _lender.approveToken(_quote,   address(_collectionPool), 200_000 * 1e18);

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

        _borrower.approveCollection(_collateral, address(_subsetPool));
        _borrower2.approveCollection(_collateral, address(_subsetPool));
        _borrower3.approveCollection(_collateral, address(_subsetPool));

        _borrower.approveQuoteToken(_quote, address(_subsetPool), 200_000 * 1e18);
        _borrower2.approveQuoteToken(_quote,   address(_subsetPool), 200_000 * 1e18);
        _borrower3.approveQuoteToken(_quote,   address(_subsetPool), 200_000 * 1e18);
        _lender.approveToken(_quote,   address(_subsetPool), 200_000 * 1e18);
    }

    /**************************************/
    /*** ERC721 Subset Tests ***/
    /**************************************/

    function testMultipleBorrowWithInterestAccumulation() external {

    }

    function testBorrowLimitReached() external {

    }

    function testBorrowBorrowerUnderCollateralized() external {

    }

    function testBorrowPoolUnderCollateralized() external {

    }

    function testBorrowAndRepay() external {
        // lender deposits 10000 Quote into 3 buckets
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2550);
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2551);
        _lender.addQuoteToken(_subsetPool, 10_000 * 1e18, 2552);

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
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _borrower.pledgeCollateral(_subsetPool, tokenIdsToAdd, address(0), address(0));

        // borrower borrows from the pool
        uint256 borrowAmount = 3_000 * 1e18;
        emit Borrow(address(_borrower), _subsetPool.indexToPrice(2550), borrowAmount);
        _borrower.borrow(_subsetPool, borrowAmount, 2551, address(0), address(0));

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
        _borrower.repay(_subsetPool, borrowAmount / 2, address(0), address(0));

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
        _quote.mint(address(_borrower), 1_000 * 1e18);

        // borrower repays their remaining loan balance
        emit Repay(address(_borrower), _subsetPool.indexToPrice(2550), pendingDebt);
        _borrower.repay(_subsetPool, pendingDebt, address(0), address(0));

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
