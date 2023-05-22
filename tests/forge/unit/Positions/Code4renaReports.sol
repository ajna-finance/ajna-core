// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "forge-std/console.sol";

import {Base64} from "@base64-sol/base64.sol";

import "../PositionManager.t.sol";

contract Code4renaReports is PositionManagerERC20PoolHelperContract {

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
}