// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { PositionManagerERC20PoolHelperContract } from '../PositionManager.t.sol';

import "@std/console.sol";

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

    function testMoveLiquidity_from_LP_report_98() external {
        // generate a new address
        address testAddress1 = makeAddr("testAddress1");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintQuoteAndApproveManagerTokens(testAddress1, 10_000 * 1e18);

        _addInitialLiquidity({
            from:   testAddress1,
            amount: 2_500 * 1e18,
            index:  mintIndex
        });

        uint256 tokenId1 = _mintNFT(testAddress1, testAddress1, address(_pool));

        // allow position manager to take ownership of the position of testAddress1
        changePrank(testAddress1);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2_500 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize positions of testAddress1
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId1, address(_pool), indexes
        );
        changePrank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        // check from and to positions before move
        (uint256 fromLp, uint256 fromDepositTime) = _positionManager.getPositionInfo(tokenId1, mintIndex);
        (uint256 toLp,   uint256 toDepositTime)   = _positionManager.getPositionInfo(tokenId1, moveIndex);
        assertEq(fromLp, 2_500 * 1e18);
        assertEq(toLp,   0);
        assertEq(fromDepositTime, block.timestamp);
        assertEq(toDepositTime,   0);

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId1, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );

        // move liquidity called by testAddress1 owner
        vm.expectEmit(true, true, true, true);
        emit MoveLiquidity(testAddress1, tokenId1, mintIndex, moveIndex, 2_500 * 1e18, 2_500 * 1e18);
        changePrank(address(testAddress1));
        _positionManager.moveLiquidity(moveLiquidityParams);

        // check from and to positions after move
        // from position should have 0 LP and 0 deposit time (FROM Position struct is deleted)
        (fromLp, fromDepositTime) = _positionManager.getPositionInfo(tokenId1, mintIndex);
        (toLp,   toDepositTime)   = _positionManager.getPositionInfo(tokenId1, moveIndex);
        assertEq(fromLp, 0);
        assertEq(toLp,   2_500 * 1e18);
        assertEq(fromDepositTime, 0);
        assertEq(toDepositTime,   block.timestamp);
    }

    function testMoveLiquidity_revert_on_less_LP_moved_report_503() external {
        // generate a new address
        address testAddress1 = makeAddr("testAddress1");
        address testAddress2 = makeAddr("testAddress2");
        uint256 mintIndex    = 2550;
        uint256 moveIndex    = 2551;
        _mintQuoteAndApproveManagerTokens(testAddress1, 1_000_000_000 * 1e18);
        _mintQuoteAndApproveManagerTokens(testAddress2, 1_000_000_000 * 1e18);
        _mintCollateralAndApproveTokens(testAddress1,  1000000000000000000 * 1e18);

        _addInitialLiquidity({
            from:   testAddress1,
            amount: 2_500 * 1e18,
            index:  mintIndex
        });
        _addInitialLiquidity({
            from:   testAddress2,
            amount: 200000000 * 1e18,
            index:  mintIndex
        });
        _addCollateral({
            from:    testAddress1,
            amount:  883976901103343226.563974622543668416 * 1e18,
            index:   2550,
            lpAward: 2661558999339261844678.534720637400665211 * 1e18
        });

        uint256 tokenId1 = _mintNFT(testAddress1, testAddress1, address(_pool));

        // allow position manager to take ownership of the position of testAddress1
        changePrank(testAddress1);
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = mintIndex;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3661558999339261844678 * 1e18;
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);

        // memorialize positions of testAddress1
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId1, address(_pool), indexes
        );
        changePrank(testAddress1);
        _positionManager.memorializePositions(memorializeParams);

        _removeAllCollateral({
            from:     testAddress2,
            amount:   66425.497336169705758544 * 1e18,
            index:    2550,
            lpRedeem: 200000000 * 1e18
        });

        // check from and to positions before move
        (uint256 fromLp, uint256 fromDepositTime) = _positionManager.getPositionInfo(tokenId1, mintIndex);
        (uint256 toLp,   uint256 toDepositTime)   = _positionManager.getPositionInfo(tokenId1, moveIndex);
        assertEq(fromLp, 2661558999339261847178.534720637400665211 * 1e18);
        assertEq(toLp,   0);
        assertEq(fromDepositTime, block.timestamp);
        assertEq(toDepositTime,   0);

        // construct move liquidity params
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId1, address(_pool), mintIndex, moveIndex, block.timestamp + 30
        );

        // move liquidity called by testAddress1 owner
        // This protects LP owner of losing LP because position manager tried to move 2661558999339261847178.534720637400665211 memorialized LP
        // but the amount of LP that can be moved (constrained by available max quote token) is only 200002500
        changePrank(address(testAddress1));
        vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
        _positionManager.moveLiquidity(moveLiquidityParams);
    }

    /**
    *  @notice Simulates the effect of the described vulnerability where a user
    *          can exponentially increase the value of their position by:
    *          1- only approving the `PositionManager` for a min amount of their position
    *          2- invoking 'memorializePositions' on their position's respective NFT
    *          3- repeating these steps until their respective position's Pool lp balance is 0
    *  @dev    This test case can be implemented and run from the ajna-core/tests/forge directory
    */
    function testMemorializePositionsWithMinApproval_report_256() external {
        uint256 intialLPBalance;
        uint256 finalLPBalance;

        address testsAddress = makeAddr("testsAddress");
        uint256 mintAmount = 10000 * 1e18;

        _mintQuoteAndApproveManagerTokens(testsAddress, mintAmount);

        // Call pool contract directly to add quote tokens
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        _addInitialLiquidity({
            from: testsAddress,
            amount: 3_000 * 1e18,
            index: indexes[0]
        });
        _addInitialLiquidity({
            from: testsAddress,
            amount: 3_000 * 1e18,
            index: indexes[1]
        });
        _addInitialLiquidity({
            from: testsAddress,
            amount: 3_000 * 1e18,
            index: indexes[2]
        });

        // Mint an NFT to later memorialize existing positions into.
        uint256 tokenId = _mintNFT(testsAddress, testsAddress, address(_pool));

        // Pool lp balances before.
        (uint256 poolLPBalanceIndex1, ) = _pool.lenderInfo(
            indexes[0],
            testsAddress
        );
        (uint256 poolLPBalanceIndex2, ) = _pool.lenderInfo(
            indexes[1],
            testsAddress
        );
        (uint256 poolLPBalanceIndex3, ) = _pool.lenderInfo(
            indexes[2],
            testsAddress
        );

        console.log("\n Pool lp balances before:");
        console.log("bucket %s: %s", indexes[0], poolLPBalanceIndex1);
        console.log("bucket %s: %s", indexes[1], poolLPBalanceIndex2);
        console.log("bucket %s: %s", indexes[2], poolLPBalanceIndex3);

        intialLPBalance =
            poolLPBalanceIndex1 +
            poolLPBalanceIndex2 +
            poolLPBalanceIndex3;

        // PositionManager lp balances before.
        (uint256 managerLPBalanceIndex1, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[0]
        );
        (uint256 managerLPBalanceIndex2, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[1]
        );
        (uint256 managerLPBalanceIndex3, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[2]
        );

        console.log("\n PositionManger lp balances before:");
        console.log("bucket %s: %s", indexes[0], managerLPBalanceIndex1);
        console.log("bucket %s: %s", indexes[1], managerLPBalanceIndex1);
        console.log("bucket %s: %s", indexes[2], managerLPBalanceIndex1);

        console.log(
            "\n <--- Repeatedly invoke memorializePositions with a min allowance set for each tx --->"
        );

        // Approve the PositionManager for only 1 token in each bucket.
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 * 1e18;
        amounts[1] = 1 * 1e18;
        amounts[2] = 1 * 1e18;

        // Continuosly invoke memorializePositions with the min allowance
        // until Pool lp balance is 0.
        while (
            poolLPBalanceIndex1 != 0 &&
            poolLPBalanceIndex2 != 0 &&
            poolLPBalanceIndex3 != 0
        ) {
            // Increase manager allowance.
            _pool.increaseLPAllowance(
                address(_positionManager),
                indexes,
                amounts
            );

            // Memorialize quote tokens into minted NFT.
            IPositionManagerOwnerActions.MemorializePositionsParams
                memory memorializeParams = IPositionManagerOwnerActions
                    .MemorializePositionsParams(tokenId, address(_pool), indexes);
            try _positionManager.memorializePositions(memorializeParams) { } catch { }

            // Get new Pool lp balances.
            (poolLPBalanceIndex1, ) = _pool.lenderInfo(
                indexes[0],
                testsAddress
            );
            (poolLPBalanceIndex2, ) = _pool.lenderInfo(
                indexes[1],
                testsAddress
            );
            (poolLPBalanceIndex3, ) = _pool.lenderInfo(
                indexes[2],
                testsAddress
            );
        }

        // Pool lp balances after.
        console.log("\n Pool lp balances after:");
        console.log("bucket %s: %s", indexes[0], poolLPBalanceIndex1);
        console.log("bucket %s: %s", indexes[1], poolLPBalanceIndex2);
        console.log("bucket %s: %s", indexes[2], poolLPBalanceIndex3);

        // PositionManager lp balances after.
        (managerLPBalanceIndex1, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[0]
        );
        (managerLPBalanceIndex2, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[1]
        );
        (managerLPBalanceIndex3, ) = _positionManager.getPositionInfo(
            tokenId,
            indexes[2]
        );

        console.log("\n PositionManger lp balances after:");
        console.log("bucket %s: %s", indexes[0], managerLPBalanceIndex1);
        console.log("bucket %s: %s", indexes[1], managerLPBalanceIndex1);
        console.log("bucket %s: %s \n", indexes[2], managerLPBalanceIndex1);

        finalLPBalance =
            managerLPBalanceIndex1 +
            managerLPBalanceIndex2 +
            managerLPBalanceIndex3;

        // Assert that the initial and ending balances are equal.
        assertEq(intialLPBalance, finalLPBalance);
    }

    function testMemorializePositionsExploitation_report_217() external {
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        _mintQuoteAndApproveManagerTokens(alice, 10000 * 1e18);
        _mintQuoteAndApproveManagerTokens(bob, 10000 * 1e18);

        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 3_000 * 1e18;
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        // alice and bob add liquidity
        _addInitialLiquidity({
            from:   alice,
            amount: amounts[0],
            index:  indexes[0]
        });

        _addInitialLiquidity({
            from:   bob,
            amount: amounts[0],
            index:  indexes[0]
        });
        
        // alice and bob mint NFT
        uint256 tokenIdAlice = _mintNFT(alice, alice, address(_pool));
        uint256 tokenIdBob = _mintNFT(bob, bob, address(_pool));

        // Alice

        // alice memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParamsAlice = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenIdAlice, address(_pool), indexes
        );

        // alice allow position manager to take ownership of the position
        changePrank(alice);
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        _positionManager.memorializePositions(memorializeParamsAlice);

        // check memorialization success for Alice
        assertEq(_positionManager.getLP(tokenIdAlice, indexes[0]), 3000 * 1e18);

        // Bob

        // bob memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParamsBob = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenIdBob, address(_pool), indexes
        );

        // bob memorialize quote tokens into minted NFT but with allowance of 1000e18 instead of 3000e18
        uint256[] memory allowanceAmountsBob = new uint256[](1);
        allowanceAmountsBob[0] = 1_000 * 1e18;
        changePrank(bob);
        _pool.increaseLPAllowance(address(_positionManager), indexes, allowanceAmountsBob);
        vm.expectRevert(IPositionManagerErrors.AllowanceTooLow.selector);
        _positionManager.memorializePositions(memorializeParamsBob);
        
        // check memorialization success for Bob
        assertEq(_positionManager.getLP(tokenIdBob, indexes[0]), 0); // bob LP balance not inflated

        // bob memorialize one more time to inflate even more LP balance in position manager
        _pool.increaseLPAllowance(address(_positionManager), indexes, allowanceAmountsBob);
        vm.expectRevert(IPositionManagerErrors.AllowanceTooLow.selector);
        _positionManager.memorializePositions(memorializeParamsBob);
        
        // check memorialization success for Bob
        assertEq(_positionManager.getLP(tokenIdBob, indexes[0]), 0); // bob LP balance not inflated
        
        // bob cannot redeem as no LP memorialized
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenIdBob, address(_pool), indexes
        );
        _pool.approveLPTransferors(transferors);

        vm.expectRevert(IPositionManagerErrors.RemovePositionFailed.selector);
        _positionManager.redeemPositions(reedemParams);

        (uint256 lpBalanceBobAfter,) = _pool.lenderInfo(indexes[0], bob);
        console.log("Balance of Bob: ", lpBalanceBobAfter);

        // alice redeem NFT and get nothing
        changePrank(alice);
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenIdAlice, address(_pool), indexes
        );

        _pool.approveLPTransferors(transferors);
        _positionManager.redeemPositions(reedemParams);

        (uint256 lpBalanceAliceAfter,) = _pool.lenderInfo(indexes[0], alice);
        console.log("Balance of Alice: ", lpBalanceAliceAfter);

        // Bob and Alice LP balances are the same as initial 
        assertEq(lpBalanceBobAfter,   3_000 * 1e18); 
        assertEq(lpBalanceAliceAfter, 3_000 * 1e18);
    }


    function testMoveLiquidityWithDebtInPool() external {
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

        // testMinter memorialize positions _i9_91, _i9_81 and _i9_52
        uint256 tokenId = _mintNFT(testMinter, testMinter, address(_pool));
        uint256[] memory indexes1 = new uint256[](3);
        indexes1[0] = _i9_91;
        indexes1[1] = _i9_81;
        indexes1[2] = _i9_52;
        uint256[] memory amounts1 = new uint256[](3);
        amounts1[0] = 2_000 * 1e18;
        amounts1[1] = 5_000 * 1e18;
        amounts1[2] = 30_000 * 1e18;
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

        _assertPool(
            PoolParams({
                htp:                  9.719336538461538466 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             83_000.0* 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 1_001.780542767698891702 * 1e18,
                poolDebt:             9_738.605048076923081414 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        486.930252403846154071 * 1e18,
                loans:                2,
                maxBorrower:          address(testBorrowerTwo),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        _assertBucketAssets({
            index: _i9_81,
            lpBalance: 5_000.0 * 1e18,
            collateral: 0,
            deposit: 5_000.0 * 1e18,
            exchangeRate: 1e18
        });

        uint256 preMoveUpState = vm.snapshot();

        // Move positiion upwards from _i9_81 to _i9_91
        changePrank(testMinter);
        IPositionManagerOwnerActions.MoveLiquidityParams memory moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_81, _i9_91, block.timestamp + 5 hours
        );
        _positionManager.moveLiquidity(moveLiquidityParams);

        vm.revertTo(preMoveUpState);

        uint256 preMoveDownState = vm.snapshot();

        // Move positiion downwards from _i9_91 to _i9_81
        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_91, _i9_81, block.timestamp + 5 hours
        );
        _positionManager.moveLiquidity(moveLiquidityParams);

        vm.revertTo(preMoveDownState);

        // Move positiion below LUP downwards from _i9_91 to _i9_52

        _assertBucketAssets({
            index: _i9_81,
            lpBalance: 5_000.0 * 1e18,
            collateral: 0,
            deposit: 5_000.0 * 1e18,
            exchangeRate: 1e18
        });

        _assertBucketAssets({
            index: _i9_52,
            lpBalance: 40_000.0 * 1e18,
            collateral: 0,
            deposit: 40_000.0 * 1e18,
            exchangeRate: 1e18
        });

        moveLiquidityParams = IPositionManagerOwnerActions.MoveLiquidityParams(
            tokenId, address(_pool), _i9_81, _i9_52, block.timestamp + 5 hours
        );
        _positionManager.moveLiquidity(moveLiquidityParams);

        _assertBucketAssets({
            index: _i9_81,
            lpBalance: 0 * 1e18,
            collateral: 0,
            deposit: 0 * 1e18,
            exchangeRate: 1e18
        });

        _assertBucketAssets({
            index: _i9_52,
            lpBalance: 44_999.315068493150685000 * 1e18,
            collateral: 0,
            deposit: 44_999.315068493150685000 * 1e18,
            exchangeRate: 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  9.719336538461538466 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             82_999.315068493150685000 * 1e18,
                pledgedCollateral:    1_002.0 * 1e18,
                encumberedCollateral: 1_001.780542767698891702 * 1e18,
                poolDebt:             9_738.605048076923081414 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        486.930252403846154071 * 1e18,
                loans:                2,
                maxBorrower:          address(testBorrowerTwo),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
    }

    /**
        Code4arena 196: The buyer of the the NFT position can be front-run by the seller
        https://github.com/code-423n4/2023-05-ajna-findings/issues/196
        Alice owns a position that is worth 10 eth
        Alice mints an NFT to represent her position
        Alice offers her nft on a secondary market for 9 eth
        Bob sees the good deal and makes a transaction to buy the position for 9 eth
        Alice front-runs Bob and calls redeemPositions()
        Alice no has the 10 eth worth of lp
        Bob's transaction completes and he gets a worthless NFT
        Alice gets Bobs 9 eth

        Fixed by recording block of last redeem and revert if same as transfer block.
     */
    function testRedeemBeforeTransfer_report_196() external {
        // generate addresses and set test params
        address alice = makeAddr("alice");
        address bob   = makeAddr("bob");
        uint256 mintAmount = 50_000 * 1e18;
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;
        uint256[] memory aliceRedeemIndex = new uint256[](1);
        aliceRedeemIndex[0] = 2550;
        uint256[] memory bobRedeemIndex = new uint256[](1);
        bobRedeemIndex[0] = 2551;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 15_000 * 1e18;
        amounts[1] = 10_000 * 1e18;
        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        // add initial liquidity
        _mintQuoteAndApproveManagerTokens(alice, mintAmount);

        _addInitialLiquidity({
            from:   alice,
            amount: 15_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   alice,
            amount: 10_000 * 1e18,
            index:  2551
        });

        uint256 tokenId = _mintNFT(alice, alice, address(_pool));
        assertEq(_positionManager.ownerOf(tokenId), alice);

        // alice memorialize positions
        _pool.increaseLPAllowance(address(_positionManager), indexes, amounts);
        _pool.approveLPTransferors(transferors);
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId, address(_pool), indexes
        );
        _positionManager.memorializePositions(memorializeParams);

        // alice redeems positions from a bucket before transferring NFT to bob
        _pool.approveLPTransferors(transferors);
        IPositionManagerOwnerActions.RedeemPositionsParams memory reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), aliceRedeemIndex
        );
        _positionManager.redeemPositions(reedemParams);

        // alice transfer NFT to bob in the same block as redeem, transfer should fail
        _positionManager.approve(address(this), tokenId);
        vm.expectRevert(IPositionManagerErrors.TransferLockedByRedeem.selector);
        _positionManager.safeTransferFrom(alice, bob, tokenId);

        // alice transfer NFT to bob after 15 minutes lock period since last redeem
        skip(16 minutes);
        _positionManager.safeTransferFrom(alice, bob, tokenId);

        // bob owns position NFT
        assertEq(_positionManager.ownerOf(tokenId), bob);

        // bob redeems positions
        changePrank(bob);
        _pool.approveLPTransferors(transferors);
        reedemParams = IPositionManagerOwnerActions.RedeemPositionsParams(
            tokenId, address(_pool), bobRedeemIndex
        );
        _positionManager.redeemPositions(reedemParams);

        // bob should be able to burn NFT in same block as redeem
        IPositionManagerOwnerActions.BurnParams memory burnParams = IPositionManagerOwnerActions.BurnParams(
            tokenId, address(_pool)
        );
        _positionManager.burn(burnParams);

        // check balances, alice should have LP in bucket 2550, bob should have LP in bucket 2551
        _assertLenderLpBalance({
            lender:      alice,
            index:       2550,
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      bob,
            index:       2551,
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
    }
}
