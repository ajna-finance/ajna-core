// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import '../../erc20/ERC20Pool.sol';
import '../../erc20/ERC20PoolFactory.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/pool/IPoolErrors.sol';

import '../../libraries/BucketMath.sol';

contract ERC20PoolTransferLPTokensTest is ERC20HelperContract {

    address internal _lender;
    address internal _lender1;
    address internal _lender2;

    function setUp() external {
        _lender  = makeAddr("lender");
        _lender1 = makeAddr("lender1");
        _lender2 = makeAddr("lender2");

        _mintQuoteAndApproveTokens(_lender,  200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender2, 200_000 * 1e18);
    }

    /********************************/
    /*** Transfer LP Tokens Tests ***/
    /********************************/

    function testTransferLPTokensToZeroAddress() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is not set
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);

        // should fail if allowed owner is set to 0x
        changePrank(_lender1);
        _pool.approveLpOwnership(address(0), indexes[0], 1_000 * 1e18);

        changePrank(_lender);
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);
    }

    function testTransferLPTokensToUnallowedAddress() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is set to lender2 address but trying to transfer to lender address
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 1_000 * 1e27);

        changePrank(_lender);
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender, indexes);
    }

    function testTransferLPTokensToInvalidIndex() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 9999;
        indexes[1] = 2550;
        indexes[2] = 2552;

        // should fail since 9999 is not a valid index
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 1_000 * 1e27);

        changePrank(_lender);
        vm.expectRevert(IPoolErrors.TransferLPInvalidIndex.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);
    }

    function testTransferLPTokensGreaterThanBalance() external {
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;

        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, indexes[1]);
        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 30_000 * 1e27);

        changePrank(_lender2);
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);
    }

    function testTransferLPTokensForAllIndexes() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);
        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, indexes[2]);

        // check lenders lp balance
        (uint256 lpBalance, uint256 lastQuoteDeposit) = _pool.lenders(indexes[0], _lender1);
        assertEq(lpBalance, 10_000 * 1e27);
        assertEq(lastQuoteDeposit, _startTime + 1 hours);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender1);
        assertEq(lpBalance, 20_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender1);
        assertEq(lpBalance, 30_000 * 1e27);

        (lpBalance, ) = _pool.lenders(indexes[0], _lender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender2);
        assertEq(lpBalance, 0);

        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 20_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 30_000 * 1e27);

        // transfer LP tokens for all indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(_lender1, _lender2, indexes, 60_000 * 1e27);
        _pool.transferLPTokens(_lender1, _lender2, indexes);

        // check that old token ownership was removed - a new transfer should fail
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);

        // check lenders lp balance
        (lpBalance, ) = _pool.lenders(indexes[0], _lender1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender1);
        assertEq(lpBalance, 0);

        (lpBalance, lastQuoteDeposit) = _pool.lenders(indexes[0], _lender2);
        assertEq(lpBalance, 10_000 * 1e27);
        assertEq(lastQuoteDeposit, _startTime + 1 hours);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender2);
        assertEq(lpBalance, 20_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender2);
        assertEq(lpBalance, 30_000 * 1e27);
    }

    function testTransferLPTokensForTwoIndexes() external {
        uint256[] memory depositIndexes = new uint256[](3);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;

        uint256[] memory transferIndexes = new uint256[](2);
        transferIndexes[0] = 2550;
        transferIndexes[1] = 2552;

        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, depositIndexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, depositIndexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, depositIndexes[2]);

        // check lenders lp balance
        (uint256 lpBalance, ) = _pool.lenders(depositIndexes[0], _lender1);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.lenders(depositIndexes[1], _lender1);
        assertEq(lpBalance, 20_000 * 1e27);
        (lpBalance, ) = _pool.lenders(depositIndexes[2], _lender1);
        assertEq(lpBalance, 30_000 * 1e27);

        (lpBalance, ) = _pool.lenders(depositIndexes[0], _lender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(depositIndexes[1], _lender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(depositIndexes[2], _lender2);
        assertEq(lpBalance, 0);

        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, transferIndexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, transferIndexes[1], 30_000 * 1e27);

        // transfer LP tokens for 2 indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(_lender1, _lender2, transferIndexes, 40_000 * 1e27);
        _pool.transferLPTokens(_lender1, _lender2, transferIndexes);

        // check that old token ownership was removed - transfer with same indexes should fail
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, transferIndexes);

        // check lenders lp balance
        (lpBalance, ) = _pool.lenders(depositIndexes[0], _lender1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(depositIndexes[1], _lender1);
        assertEq(lpBalance, 20_000 * 1e27);
        (lpBalance, ) = _pool.lenders(depositIndexes[2], _lender1);
        assertEq(lpBalance, 0);

        (lpBalance, ) = _pool.lenders(depositIndexes[0], _lender2);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.lenders(depositIndexes[1], _lender2);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(depositIndexes[2], _lender2);
        assertEq(lpBalance, 30_000 * 1e27);
    }

    function testTransferLPTokensToLenderWithLPTokens() external {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);
        changePrank(_lender1);
        _pool.addQuoteToken(10_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(20_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(30_000 * 1e18, indexes[2]);

        skip(1 hours);
        changePrank(_lender2);
        _pool.addQuoteToken(5_000 * 1e18, indexes[0]);
        _pool.addQuoteToken(10_000 * 1e18, indexes[1]);
        _pool.addQuoteToken(15_000 * 1e18, indexes[2]);

        // check lenders lp balance
        (uint256 lpBalance, uint256 lastQuoteDeposit) = _pool.lenders(indexes[0], _lender1);
        assertEq(lpBalance, 10_000 * 1e27);
        assertEq(lastQuoteDeposit, _startTime + 1 hours);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender1);
        assertEq(lpBalance, 20_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender1);
        assertEq(lpBalance, 30_000 * 1e27);

        (lpBalance, lastQuoteDeposit) = _pool.lenders(indexes[0], _lender2);
        assertEq(lpBalance, 5_000 * 1e27);
        assertEq(lastQuoteDeposit, _startTime + 2 hours);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender2);
        assertEq(lpBalance, 10_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender2);
        assertEq(lpBalance, 15_000 * 1e27);

        // set allowed owner to lender2 address
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 20_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 30_000 * 1e27);

        // transfer LP tokens for all indexes
        changePrank(_lender);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(_lender1, _lender2, indexes, 60_000 * 1e27);
        _pool.transferLPTokens(_lender1, _lender2, indexes);

        // check that old token ownership was removed - transfer with same indexes should fail
        vm.expectRevert(IPoolErrors.TransferLPNoAllowance.selector);
        _pool.transferLPTokens(_lender1, _lender2, indexes);

        // check lenders lp balance
        (lpBalance, ) = _pool.lenders(indexes[0], _lender1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender1);
        assertEq(lpBalance, 0);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender1);
        assertEq(lpBalance, 0);

        (lpBalance, lastQuoteDeposit) = _pool.lenders(indexes[0], _lender2);
        assertEq(lpBalance, 15_000 * 1e27);
        assertEq(lastQuoteDeposit, _startTime + 2 hours);
        (lpBalance, ) = _pool.lenders(indexes[1], _lender2);
        assertEq(lpBalance, 30_000 * 1e27);
        (lpBalance, ) = _pool.lenders(indexes[2], _lender2);
        assertEq(lpBalance, 45_000 * 1e27);
    }
}
