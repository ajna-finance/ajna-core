// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import '../../erc721/ERC721Pool.sol';
import '../../erc721/ERC721PoolFactory.sol';

import '../../erc721/interfaces/IERC721Pool.sol';
import '../../erc721/interfaces/pool/IERC721PoolErrors.sol';
import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';
import '../../libraries/Maths.sol';
import '../../libraries/PoolUtils.sol';

contract ERC721PoolCollateralTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](5);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  52);
        _mintAndApproveCollateralTokens(_borrower2, 53);
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    function testPledgeCollateralSubset() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
    }

    function testPledgeCollateralNotInSubset() external {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        _assertPledgeCollateralNotInSubsetRevert(
            {
                from:     _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
    }

    function testPledgeCollateralInSubsetFromDifferentActor() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerInflator:          0,
                borrowerCollateralization: 1 * 1e18,
                borrowerPendingDebt:       0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerInflator:          0,
                borrowerCollateralization: 1 * 1e18,
                borrowerPendingDebt:       0
            }
        );

        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(1));

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1 * 1e18,
                borrowerMompFactor:        0,
                borrowerInflator:          1 * 1e18,
                borrowerCollateralization: 1 * 1e18,
                borrowerPendingDebt:       0
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowerMompFactor:        0,
                borrowerInflator:          0,
                borrowerCollateralization: 1 * 1e18,
                borrowerPendingDebt:       0
            }
        );
    }

    function testPullCollateral() external {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 3;

        // should fail if trying to pull collateral by an address without pledged collateral
        _assertPullInsufficientCollateralRevert(
            {
                from:     _lender,
                tokenIds: tokenIdsToRemove
            }
        );

        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(4));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(address(_pool)), 4);

        // should fail if trying to pull collateral by an address that pledged different collateral
        _assertPullTokenRevert(
            {
                from:     _borrower2,
                tokenIds: tokenIdsToRemove
            }
        );

        tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        _pullCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(), Maths.wad(2));

        assertEq(_collateral.balanceOf(_borrower),      51);
        assertEq(_collateral.balanceOf(address(_pool)), 2);

        // should fail if borrower tries to pull again same NFTs
        _assertPullInsufficientCollateralRevert(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );
    }

    // TODO: finish implementing
    function testPullCollateralNotInPool() external {
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

        // should revert if borrower attempts to remove collateral not in pool
        uint256[] memory tokenIdsToRemove = new uint256[](1);
        tokenIdsToRemove[0] = 51;
        _assertPullNotDepositedCollateralRevert(
            {
                from: _borrower,
                tokenIds: tokenIdsToRemove
            }
        );

        // borrower should be able to remove collateral in the pool
        tokenIdsToRemove = new uint256[](3);
        tokenIdsToRemove[0] = 1;
        tokenIdsToRemove[1] = 3;
        tokenIdsToRemove[2] = 5;

        _pullCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );
    }

    function testPullCollateralPartiallyEncumbered() external {
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
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
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );

        // check initial token balances
        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      0);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  BucketMath.MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                borrowerDebt:         0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
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
                amount:     3_000 * 1e18,
                indexLimit: 2_551,
                newLup:     PoolUtils.indexToPrice(2550)
            }
        );

        // check token balances after borrow
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_000 * 1e18);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  1_000.961538461538462 * 1e18,
                lup:                  PoolUtils.indexToPrice(2550),
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    Maths.wad(3),
                encumberedCollateral: 0.997340520100278804 * 1e18,
                borrowerDebt:         3_002.884615384615386 * 1e18,
                actualUtilization:    0.100096153846153846 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // remove some unencumbered collateral
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;

        // borrower removes some of their deposted NFTS from the pool
        _pullCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );

        // check token balances after remove
        assertEq(_collateral.balanceOf(_borrower),      51);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_000 * 1e18);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  3_002.884615384615386000 * 1e18,
                lup:                  PoolUtils.indexToPrice(2550),
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    Maths.wad(1),
                encumberedCollateral: 0.997340520100278804 * 1e18,
                borrowerDebt:         3_002.884615384615386 * 1e18,
                actualUtilization:    0.300288461538461539 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

    }

    function testPullCollateralOverlyEncumbered() external {

        // lender deposits 10000 Quote into 3 buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
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
                index:  2550,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check collateralization after pledge
        assertEq(PoolUtils.encumberance(_pool.borrowerDebt(), _lup()), 0);

        // borrower borrows some quote
        _borrow(
            {
                from:       _borrower,
                amount:     9_000 * 1e18,
                indexLimit: 2_551,
                newLup:     PoolUtils.indexToPrice(2550)
            }
        );

        // check collateralization after borrow
        assertEq(PoolUtils.encumberance(_pool.borrowerDebt(), _lup()), 2.992021560300836411 * 1e18);

        // should revert if borrower attempts to pull more collateral than is unencumbered
        uint256[] memory tokenIdsToRemove = new uint256[](2);
        tokenIdsToRemove[0] = 3;
        tokenIdsToRemove[1] = 5;
        _assertPullInsufficientCollateralRevert(
            {
                from:     _borrower,
                tokenIds: tokenIdsToRemove
            }
        );
    }

    function testAddRemoveCollateral() external {

        // lender adds some liquidity
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1692,
                newLup: BucketMath.MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1530,
                newLup: BucketMath.MAX_PRICE
            }
        );

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 5;

        // add three tokens to a single bucket
        _addCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIds,
                index:    1530
            }
        );

        // should revert if the actor does not have any LP to remove a token
        tokenIds = new uint256[](1);
        tokenIds[0] = 1;

        _assertRemoveCollateralInsufficientLPsRevert(
            {
                from:     _borrower2,
                tokenIds: tokenIds,
                index:    1530
            }
        );

        // should revert if we try to remove a token from a bucket with no collateral
        changePrank(_borrower);
        tokenIds[0] = 1;
        _assertRemoveInsufficientCollateralRevert(
            {
                from:     _borrower,
                tokenIds: tokenIds,
                index:    1692
            }
        );

        // remove one token
        tokenIds[0] = 5;
        _removeCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIds,
                index:    1530,
                lpRedeem: 487_616.252661175041981841 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    497_616.252661175041981841 * 1e27,
                collateral:   Maths.wad(1),
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       1530,
                lpBalance:   487_616.252661175041981841 * 1e27,
                depositTime: 0
            }
        );

        // remove another token
        tokenIds[0] = 1;
        _removeCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIds,
                index:    1530,
                lpRedeem: 487_616.252661175041981841 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       1530,
                lpBalance:   0,
                depositTime: 0
            }
        );

        // lender removes quote token
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   10_000 * 1e18,
                index:    1530,
                newLup:   BucketMath.MAX_PRICE,
                lpRedeem: 10_000 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
    }
}
