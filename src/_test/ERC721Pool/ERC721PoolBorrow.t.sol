// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc20/interfaces/IERC20Pool.sol';

import '../../base/interfaces/IPool.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';

abstract contract ERC721PoolBorrowTest is ERC721HelperContract {
    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    // Called by setUp method to set the _pool which tests will use
    function createPool() external virtual returns (ERC721Pool);

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy collection pool
        _pool = this.createPool();

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 52);
        _mintAndApproveCollateralTokens(_borrower2, 10);
        _mintAndApproveCollateralTokens(_borrower3, 13);

        vm.prank(_borrower);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }
}

contract ERC721SubsetPoolBorrowTest is ERC721PoolBorrowTest {
    function createPool() external override returns (ERC721Pool) {
        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        return _deploySubsetPool(subsetTokenIds);
    }

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    function testBorrowLimitReached() external {

        // lender deposits 10000 Quote into 3 buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // borrower deposits three NFTs into the subset pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // should revert if insufficient quote available before limit price
        _assertBorrowLimitIndexRevert(
            {
                from:       _borrower,
                amount:     21_000 * 1e18,
                indexLimit: 2551
            }
        );
    }

    function testBorrowBorrowerUnderCollateralized() external {
        // add initial quote to the pool
        _addLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  3575,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // borrower pledges some collateral
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 5;
        tokenIdsToAdd[1] = 3;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // should revert if borrower did not deposit enough collateral
        _assertBorrowBorrowerUnderCollateralizedRevert(
            {
                from:       _borrower,
                amount:     40 * 1e18,
                indexLimit: 4000
            }
        );
    }

    function testBorrowPoolUnderCollateralized() external {
        // add initial quote to the pool
        _addLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  3232,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // should revert if borrow would result in pool under collateralization
        _assertBorrowBorrowerUnderCollateralizedRevert(
            {
                from:       _borrower,
                amount:     500,
                indexLimit: 4000
            }
        );
    }

    function testBorrowAndRepay() external {

        // lender deposits 10000 Quote into 3 buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // check initial token balances
        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            0);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check initial bucket state
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // borrower deposits three NFTs into the subset pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        // borrower borrows from the pool
        uint256 borrowAmount = 3_000 * 1e18;
        _borrow(
            {
                from:       _borrower,
                amount:     borrowAmount,
                indexLimit: 2551,
                newLup:     PoolUtils.indexToPrice(2550)
            }
        );

        // check token balances after borrow
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      borrowAmount);

        // check pool state after borrow
        _assertPool(
            PoolState({
                htp:                  1_000.961538461538462000 * 1e18,
                lup:                  PoolUtils.indexToPrice(2550),
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    Maths.wad(3),
                encumberedCollateral: 0.997340520100278804 * 1e18,
                poolDebt:             3_002.88461538461538600 * 1e18,
                actualUtilization:    0.100096153846153846 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        3_002.88461538461538600 * 1e18 / 10,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // check bucket state after borrow
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );

        // check borrower info after borrow
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              3_002.884615384615386000 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_010.892022197881557845 * 1e18,
                borrowerCollateralization: 3.007999714779824033 * 1e18
            }
        );

        // pass time to allow interest to accumulate
        skip(10 days);

        // borrower partially repays half their loan
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   borrowAmount / 2,
                repaid:   borrowAmount / 2,
                newLup:   PoolUtils.indexToPrice(2550)
            }
        );

        // check token balances after partial repay
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 28_500 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      borrowAmount / 2);

        // check pool state after partial repay
        _assertPool(
            PoolState({
                htp:                  503.022258079721182348 * 1e18,
                lup:                  PoolUtils.indexToPrice(2550),
                poolSize:             30_003.520235392247040000 * 1e18,
                pledgedCollateral:    Maths.wad(3),
                encumberedCollateral: 0.500516446164039921 * 1e18,
                poolDebt:             1507.000974734143274062 * 1e18,
                actualUtilization:    0.050227472073642885 * 1e18,
                targetUtilization:    0.166838815388013307 * 1e18,
                minDebtAmount:        150.700097473414327406 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        // check bucket state after partial repay
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_001.17341179741568 * 1e18,
                exchangeRate: 1.000117341179741568 * 1e27
            }
        );

        // check borrower info after partial repay
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              1_507.000974734143274062 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_006.770336295505368176 * 1e18,
                borrowerCollateralization: 5.993809040625961846 * 1e18
            }
        );

        // pass time to allow additional interest to accumulate
        skip(10 days);

        // find pending debt after interest accumulation
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              1_508.860066921599065131 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowerMompFactor:        3_006.770336295505368176 * 1e18,
                borrowerCollateralization: 5.986423966420065589 * 1e18
            }
        );

        // mint additional quote to allow borrower to repay their loan plus interest
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 1_000 * 1e18);

        // borrower repays their remaining loan balance
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   1_508.860066921599065131 * 1e18,
                repaid:   1_508.860066921599065131 * 1e18,
                newLup:   BucketMath.MAX_PRICE
            }
        );

        // check token balances after fully repay
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 30_008.860066921599065131 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      991.139933078400934869 * 1e18);

        // borrower pulls collateral from pool
        _pullCollateral(
            {
                from:   _borrower,
                amount: 3
            }
        );

        // check pool state after fully repay
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             30_005.105213052294392423 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    0.000000452724663788 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 10 days
            })
        );
        _assertEMAs(
            {
                debtEma:   116.548760023014994270 * 1e18,
                lupColEma: 257_438_503.676217090117659874 * 1e18
            }
        );

        // check bucket state after fully repay
        _assertBucket(
            {
                index:        2550,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_001.70173768409813 * 1e18,
                exchangeRate: 1.000170173768409813 * 1e27
            }
        );
        // check borrower info after fully repay
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
    }

    function testPoolRepayRequireChecks() external {
        // add initial quote to the pool
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );

        deal(address(_quote), _borrower, _quote.balanceOf(_borrower) + 10_000 * 1e18);
        // should revert if borrower has no debt
        _assertRepayNoDebtRevert(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   10_000 * 1e18
            }
        );

        // borrower 1 borrows 1000 quote from the pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     1_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertLoans(
            {
                noOfLoans: 1,
                maxBorrower: _borrower,
                maxThresholdPrice: 333.653846153846154 * 1e18
            }
        );

        // borrower 2 borrows 3k quote from the pool and becomes new queue HEAD
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     3_000 * 1e18,
                indexLimit: 3_000,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        _assertLoans(
            {
                noOfLoans: 2,
                maxBorrower: _borrower2,
                maxThresholdPrice: 3_002.884615384615386 * 1e18
            }
        );

        // should be able to repay loan if properly specified
        _repay(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   1_100 * 1e18,
                repaid:   1_000.961538461538462000 * 1e18,
                newLup:   _lup()
            }
        );
    }


    function testRepayLoanFromDifferentActor() external {
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // borrower deposits three NFTs into the subset pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        // borrower borrows from the pool
        _borrow(
            {
                from:       _borrower,
                amount:     3_000 * 1e18,
                indexLimit: 2_551,
                newLup:     3_010.892022197881557845 * 1e18
            }
        );

        // check token balances after borrow
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        170_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_000 * 1e18);

        // pass time to allow interest to accumulate
        skip(10 days);

        // lender partially repays borrower's loan
        _repay(
            {
                from:     _lender,
                borrower: _borrower,
                amount:   1_500 * 1e18,
                repaid:   1_500 * 1e18,
                newLup:   3_010.892022197881557845 * 1e18
            }
        );

        // check token balances after partial repay
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 28_500 * 1e18);
        assertEq(_quote.balanceOf(_lender),        168_500 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_000 * 1e18);
    }
}

contract ERC721CollectionPoolBorrowTest is ERC721PoolBorrowTest {
    uint internal _anonBorrowerCount = 0;

    function createPool() external override returns (ERC721Pool) {
        return _deployCollectionPool();
    }

    /**
     *  @dev Creates debt for an anonymous non-player borrower not otherwise involved in the test.
     **/
    function _anonBorrowerDrawsDebt(uint256 loanAmount) internal {
        _anonBorrowerCount += 1;
        address borrower = makeAddr(string(abi.encodePacked("anonBorrower", _anonBorrowerCount)));
        vm.stopPrank();
        _mintAndApproveCollateralTokens(borrower, 1);
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = _collateral.totalSupply();
        _pledgeCollateral(
            {
                from:     borrower,
                borrower: borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _pool.borrow(loanAmount, 7_777);
    }

    function testMinBorrowAmountCheck() external {
        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(20_000 * 1e18, 2550);

        // 10 borrowers draw debt
        for (uint i=0; i<10; ++i) {
            _anonBorrowerDrawsDebt(1_200 * 1e18);
        }
        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // should revert if borrower attempts to borrow more than minimum amount
        _assertBorrowMinDebtRevert(
            {
                from:       _borrower,
                amount:     100 * 1e18,
                indexLimit: 7_777
            }
        );
    }

    function testMinRepayAmountCheck() external {
        // add initial quote to the pool
        changePrank(_lender);
        _pool.addQuoteToken(20_000 * 1e18, 2550);

        // 9 other borrowers draw debt
        for (uint i=0; i<9; ++i) {
            _anonBorrowerDrawsDebt(1_200 * 1e18);
        }

        // borrower 1 borrows 1000 quote from the pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _pool.borrow(1_000 * 1e18, 3000);
        (, uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(loansCount, 10);

        // should revert if amount left after repay is less than the average debt
        _assertRepayMinDebtRevert(
            {
                from:     _borrower,
                borrower: _borrower,
                amount:   900 * 1e18
            }
        );
    }
}