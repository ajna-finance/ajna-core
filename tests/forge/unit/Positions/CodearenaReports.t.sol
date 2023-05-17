// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { PositionManagerERC20PoolHelperContract } from '../PositionManager.t.sol';

import 'src/interfaces/position/IPositionManager.sol';
import 'src/PositionManager.sol';
import 'src/libraries/helpers/SafeTokenNamer.sol';
import 'src/libraries/helpers/PoolHelper.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';

contract PositionManagerCodeArenaTest is PositionManagerERC20PoolHelperContract {

    function testMoveLiquidityInBankruptBucket_LP_report_179_494() external {
        address testMinter      = makeAddr("testMinter");
        address testMinter2     = makeAddr("testMinter2");
        address testBorrower    = makeAddr("testBorrower");
        address testBorrowerTwo = makeAddr("testBorrowerTwo");

        /************************/
        /*** Setup Pool State ***/
        /************************/

        _mintCollateralAndApproveTokens(testBorrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(testBorrowerTwo, 1_000 * 1e18);

        _mintQuoteAndApproveManagerTokens(testMinter, 500_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(testMinter2, 500_000 * 1e18);

        // add initial liquidity
        _addInitialLiquidity({
            from:   testMinter,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   testMinter,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });
        // minter 2 adds liquidity 
        _addInitialLiquidity({
            from:   testMinter2,
            amount: 10_000 * 1e18,
            index:  _i9_52
        });

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     testBorrower,
            borrower: testBorrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       testBorrower,
            amount:     19.25 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     testBorrowerTwo,
            borrower: testBorrowerTwo,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       testBorrowerTwo,
            amount:     7_980 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        _borrow({
            from:       testBorrowerTwo,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /****************************/
        /*** Memorialize Position ***/
        /****************************/

        // testMinter memorialize positions _i9_91 and _i9_52
        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        uint256[] memory indexes1 = new uint256[](2);
        indexes1[0] = _i9_91;
        indexes1[1] = _i9_52;
        uint256[] memory amounts1 = new uint256[](2);
        amounts1[0] = 2_000 * 1e18;
        amounts1[1] = 30_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes1, amounts1);

        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);
        _pool.approveLPTransferors(transferors);

        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, address(_pool), indexes1
        );
        _positionManager.memorializePositions(memorializeParams);

        // testMinter2 memorialize position _i9_52
        uint256 tokenId2 = _mintNFT(testMinter2, testMinter2, address(_pool));
        uint256[] memory indexes2 = new uint256[](1);
        indexes2[0] = _i9_52;
        uint256[] memory amounts2 = new uint256[](1);
        amounts2[0] = 10_000 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes2, amounts2);

        _pool.approveLPTransferors(transferors);

        memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId2, address(_pool), indexes2
        );
        _positionManager.memorializePositions(memorializeParams);

        /*************************/
        /*** Bucket Bankruptcy ***/
        /*************************/

        // Skip to make borrower undercollateralized
        skip(100 days);

        // minter kicks borrower
        _kick({
            from:           testMinter,
            borrower:       testBorrowerTwo,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        // take entire collateral
        _take({
            from:            testMinter,
            borrower:        testBorrowerTwo,
            maxCollateral:   1_000 * 1e18,
            bondChange:      6.531114528261135360 * 1e18,
            givenAmount:     653.111452826113536000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _settle({
            from:        testMinter,
            borrower:    testBorrowerTwo,
            maxDepth:    10,
            settledDebt: 9_891.935520844277346922 * 1e18
        });

        // bucket is insolvent, balances are reset
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        assertTrue(_positionManager.isPositionBucketBankrupt(tokenId, _i9_91));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, _i9_52));

        /******************/
        /*** Report 494 ***/
        /******************/

        // testMinter2 moves liquidity from healthy deposit _i9_52 to bankrupt _i9_91 deposit
        assertEq(_positionManager.getLP(tokenId2, _i9_91), 0);
        assertEq(_positionManager.getLP(tokenId2, _i9_52), 10_000 * 1e18);

        changePrank(testMinter2);
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId2, address(_pool), _i9_52, _i9_91, block.timestamp + 5 hours
        );
        vm.expectRevert(IPoolErrors.BucketBankruptcyBlock.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // skip time to avoid move in same block as bucket bankruptcy
        skip(1 hours);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // report 494: testMinter2 position at _i9_91 should not be bankrupt
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId2, _i9_91));
        assertEq(_positionManager.getLP(tokenId2, _i9_91), 10_000 * 1e18);

        /******************/
        /*** Report 179 ***/
        /******************/

        // check bankrupt position _i9_91
        assertTrue(_positionManager.isPositionBucketBankrupt(tokenId, _i9_91));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, _i9_52));

        assertEq(_positionManager.getLP(tokenId, _i9_91), 0);
        assertEq(_positionManager.getLP(tokenId, _i9_52), 30_000 * 1e18);

        changePrank(testMinter);

        // testMinter1 moves liquidity from bankrupt _i9_91 deposit to healthy deposit _i9_52
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_91, _i9_52, block.timestamp + 5 hours
        );
        // call reverts as cannot move from bankrupt bucket
        vm.expectRevert(IPositionManagerErrors.BucketBankrupt.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);

        // testMinter1 moves liquidity from healthy deposit _i9_52 to bankrupt _i9_91
        // _i9_52 should remain with 0 LP, _i9_91 should have 30_000
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_52, _i9_91, block.timestamp + 5 hours
        );
        _positionManager.moveLiquidity(moveLiquidityParams);
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, _i9_91));
        assertFalse(_positionManager.isPositionBucketBankrupt(tokenId, _i9_52));

        // report 179: testMinter1 position at _i9_91 should contain only moved LP (without LP before bankruptcy)
        assertEq(_positionManager.getLP(tokenId, _i9_91), 30_000 * 1e18);
        assertEq(_positionManager.getLP(tokenId, _i9_52), 0);
    }

}
