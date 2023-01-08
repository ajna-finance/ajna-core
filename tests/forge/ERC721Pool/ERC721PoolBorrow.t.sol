// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract, ERC721FuzzyHelperContract } from './ERC721DSTestPlus.sol';

import 'src/ERC721Pool.sol';

import 'src/libraries/internal/Maths.sol';

import { MAX_PRICE, _priceAt } from 'src/libraries/helpers/PoolHelper.sol';

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

    function testBorrowLimitReached() external tearDown {

        // lender deposits 10000 Quote into 3 buckets
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
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

    function testBorrowBorrowerUnderCollateralized() external tearDown {
        // add initial quote to the pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  3575
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

    function testBorrowPoolUnderCollateralized() external tearDown {
        // add initial quote to the pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  3232
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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
            }
        );

        // check initial token balances
        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),            0);

        // check pool state
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
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
                newLup:     _priceAt(2550)
            }
        );

        // check token balances after borrow
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      borrowAmount);

        // check pool state after borrow
        _assertPool(
            PoolParams({
                htp:                  1_000.961538461538462000 * 1e18,
                lup:                  _priceAt(2550),
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
                borrowert0Np:              1_051.009615384615385100 * 1e18,
                borrowerCollateralization: 3.007999714779824033 * 1e18
            }
        );

        // pass time to allow interest to accumulate
        skip(10 days);

        // borrower partially repays half their loan
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    borrowAmount / 2,
            amountRepaid:     borrowAmount / 2,
            collateralToPull: 0,
            newLup:           _priceAt(2550)
        });

        // check token balances after partial repay
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 28_500 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      borrowAmount / 2);

        // check pool state after partial repay
        _assertPool(
            PoolParams({
                htp:                  503.022258079721182348 * 1e18,
                lup:                  _priceAt(2550),
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
                borrowert0Np:              1_051.009615384615385100 * 1e18,
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
                borrowert0Np:              1_051.009615384615385100 * 1e18,
                borrowerCollateralization: 5.986423966420065589 * 1e18
            }
        );

        // mint additional quote to allow borrower to repay their loan plus interest
        deal(address(_quote), _borrower,  _quote.balanceOf(_borrower) + 1_000 * 1e18);

        // check collateral token balances before full repay
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        // borrower repays their debt and pulls collateral from the pool
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    type(uint256).max,
            amountRepaid:     1_508.860066921599065131 * 1e18,
            collateralToPull: 3,
            newLup:           MAX_PRICE
        });

        // check token balances after fully repay
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_008.860066921599065131 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      991.139933078400934869 * 1e18);

        // check pool state after fully repay
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             30_005.105213052294390000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    0.166838815388013307 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 20 days
            })
        );
        _assertEMAs(
            {
                debtEma:   142.074529848655991542 * 1e18,
                lupColEma: 851.567601449557349751 * 1e18
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
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
    }

    function testPoolRepayRequireChecks() external tearDown {
        // add initial quote to the pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
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
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    1_100 * 1e18,
            amountRepaid:     1_000.961538461538462000 * 1e18,
            collateralToPull: 0,
            newLup:           _lup()
        });
    }


    function testRepayLoanFromDifferentActor() external tearDown {
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
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
        _repayDebt({
            from:             _lender,
            borrower:         _borrower,
            amountToRepay:    1_500 * 1e18,
            amountRepaid:     1_500 * 1e18,
            collateralToPull: 0,
            newLup:           3_010.892022197881557845 * 1e18
        });

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

        _drawDebtNoLupCheck(
            {
                from:           borrower,
                borrower:       borrower,
                amountToBorrow: loanAmount,
                limitIndex:     7_777,
                tokenIds:       tokenIdsToAdd
            }
        );
    }

    function testMinBorrowAmountCheck() external tearDown {
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

    function testMinRepayAmountCheck() external tearDown {
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

        _drawDebtNoLupCheck(
            {
                from:           _borrower,
                borrower:       _borrower,
                amountToBorrow: 1_000 * 1e18,
                limitIndex:     3000,
                tokenIds:       tokenIdsToAdd
            }
        );

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

contract ERC721PoolBorrowFuzzyTest is ERC721FuzzyHelperContract {

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
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 52);
        _mintAndApproveCollateralTokens(_borrower2, 10);
        _mintAndApproveCollateralTokens(_borrower3, 13);

        vm.prank(_borrower);
        _quote.approve(address(_pool), 200_000 * 1e18);
    }

    function testDrawRepayDebtFuzzy(uint256 numIndexes, uint256 mintAmount_) external tearDown {
        numIndexes = bound(numIndexes, 3, 7); // number of indexes to add liquidity to
        mintAmount_ = bound(mintAmount_, 1 * 1e18, 1_000 * 1e18);

        // lender adds liquidity to random indexes
        changePrank(_lender);
        uint256[] memory indexes = new uint256[](numIndexes);
        for (uint256 i = 0; i < numIndexes; ++i) {
            deal(address(_quote), _lender, mintAmount_);
            indexes[i] = _randomIndexWithMinimumPrice(5000); // setting a minimum price for collateral prevents exceeding memory and gas limits

            _addLiquidity({
                from:    _lender,
                amount:  mintAmount_,
                index:   indexes[i],
                lpAward: mintAmount_ * 1e9,
                newLup:  _calculateLup(address(_pool), 0)
            });

            _assertBucket({
                index:      indexes[i],
                lpBalance:  mintAmount_ * 1e9,
                collateral: 0,
                deposit:    mintAmount_,
                exchangeRate: 1e27
            });
        }

        // borrower draw a random amount of debt
        changePrank(_borrower);
        uint256 limitIndex = _findLowestIndexPrice(indexes);
        uint256 borrowAmount = Maths.wdiv(mintAmount_, Maths.wad(3));
        uint256[] memory tokenIdsToAdd = _NFTTokenIdsToAdd(_borrower, _requiredCollateralNFT(Maths.wdiv(mintAmount_, Maths.wad(3)), limitIndex));

        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: borrowAmount,
            limitIndex:     limitIndex,
            tokenIds:       tokenIdsToAdd,
            newLup:         _calculateLup(address(_pool), borrowAmount)
        });

        // check buckets after borrow
        for (uint256 i = 0; i < numIndexes; ++i) {
            _assertBucket({
                index:        indexes[i],
                lpBalance:    mintAmount_ * 1e9,
                collateral:   0,
                deposit:      mintAmount_,
                exchangeRate: 1e27
            });
        }

        // check borrower info
        (uint256 debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        assertGt(debt, borrowAmount); // check that initial fees accrued

        // check pool state
        (uint256 minDebt, , uint256 poolActualUtilization, uint256 poolTargetUtilization) = _poolUtils.poolUtilizationInfo(address(_pool));
        _assertPool(
            PoolParams({
                htp:                  Maths.wdiv(debt, Maths.wad(tokenIdsToAdd.length)),
                lup:                  _poolUtils.lup(address(_pool)),
                poolSize:             (indexes.length * mintAmount_),
                pledgedCollateral:    Maths.wad(tokenIdsToAdd.length),
                encumberedCollateral: Maths.wdiv(debt, _poolUtils.lup(address(_pool))),
                poolDebt:             debt,
                actualUtilization:    poolActualUtilization,
                targetUtilization:    poolTargetUtilization,
                minDebtAmount:        minDebt,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        assertLt(_htp(), _poolUtils.lup(address(_pool)));
        assertGt(minDebt, 0);
        assertEq(_poolUtils.lup(address(_pool)), _calculateLup(address(_pool), debt));

        // pass time to allow interest to accumulate
        skip(1 days);

        // repay all debt and withdraw collateral
        (debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        deal(address(_quote), _borrower, debt);
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    debt,
            amountRepaid:     debt,
            collateralToPull: tokenIdsToAdd.length,
            newLup:           _calculateLup(address(_pool), 0)
        });

        // check that deposit and exchange rate have increased as a result of accrued interest
        for (uint256 i = 0; i < numIndexes; ++i) {
            (, uint256 deposit, , uint256 lpAccumulator, , uint256 exchangeRate) = _poolUtils.bucketInfo(address(_pool), indexes[i]);

            // check that only deposits above the htp earned interest
            if (indexes[i] <= _poolUtils.priceToIndex(Maths.wdiv(debt, Maths.wad(tokenIdsToAdd.length)))) {
                assertGt(deposit, mintAmount_);
                assertGt(exchangeRate, 1e27);
            } else {
                assertEq(deposit, mintAmount_);
                assertEq(exchangeRate, 1e27);
            }

            assertEq(lpAccumulator, mintAmount_ * 1e9);
            _assertBucket({
                index:        indexes[i],
                lpBalance:    mintAmount_ * 1e9,
                collateral:   0,
                deposit:      deposit,
                exchangeRate: exchangeRate
            });
        }

        // check borrower state after repayment
        (debt, , ) = _poolUtils.borrowerInfo(address(_pool), address(_borrower));
        assertEq(debt, 0);

        // check pool state
        assertEq(_htp(), 0);
        assertEq(_poolUtils.lup(address(_pool)), MAX_PRICE);
    }

}
