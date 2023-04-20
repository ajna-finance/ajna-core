// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolTransferLPTest is ERC20HelperContract {

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

        changePrank(_lender2);
        address[] memory transferors = new address[](1);
        transferors[0] = _lender;
        _pool.approveLPTransferors(transferors);
    }

    /*************************/
    /*** Transfer LP Tests ***/
    /*************************/

    function testTransferLPToZeroAddress() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is not set
        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  indexes
        });

        // should fail if allowed owner is set to 0x
        changePrank(_lender1);
        uint256[] memory approveIndexes = new uint256[](1);
        approveIndexes[0] = 2550;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 * 1e18;
        _pool.increaseLPAllowance(address(0), approveIndexes, amounts);

        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  indexes
        });
    }

    function testTransferLPToUnallowedAddress() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is set to lender2 address but trying to transfer to lender address
        changePrank(_lender1);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000 * 1e18;
        amounts[1] = 1_000 * 1e18;
        amounts[2] = 1_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender,
            indexes:  indexes
        });
    }

    function testTransferLPToInvalidIndex() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 9999;
        indexes[1] = 2550;
        indexes[2] = 2552;

        // should fail since 9999 is not a valid index
        changePrank(_lender1);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1_000 * 1e18;
        amounts[1] = 1_000 * 1e18;
        amounts[2] = 1_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        _assertTransferInvalidIndexRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  indexes
        });
    }

    function testTransferLPGreaterThanBalance() external tearDown {
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  indexes[1]
        });

        // set allowed owner to lender2 address
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 30_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        // only the lender's available balance should be transferred to the new owner
        _transferLP({
            operator:  _lender2,
            from:      _lender1,
            to:        _lender2,
            indexes:   indexes,
            lpBalance: 30_000 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });
    }

    function testTransferLPToSameOwner() external {
        uint256[] memory indexes = new uint256[](1);
        indexes[0] = 2550;

        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });

        changePrank(_lender1);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000 * 1e18;
        _pool.increaseLPAllowance(_lender1, indexes, amounts);
        address[] memory transferors = new address[](1);
        transferors[0] = _lender;
        _pool.approveLPTransferors(transferors);

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 1 hours
        });

        // should revert if trying to transfer LP to same address
        _assertTransferToSameOwnerRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender1,
            indexes:  indexes
        });
    }

    function testIncreaseDecreaseLPWithInvalidInput() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 30_000 * 1e18;

        // increase allowance should revert for invalid input
        vm.expectRevert(IPoolErrors.InvalidAllowancesInput.selector);
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        // decrease allowance should revert for invalid input
        vm.expectRevert(IPoolErrors.InvalidAllowancesInput.selector);
        _pool.decreaseLPAllowance(_lender2, indexes, amounts);
    }

    function testTransferLPForAllIndexes() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 30_000 * 1e18,
            index:  indexes[2]
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[2],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // set allowed owner to lender2 address
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 20_000 * 1e18;
        amounts[2] = 30_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        // transfer LP for all indexes
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender2,
            indexes:   indexes,
            lpBalance: 60_000 * 1e18
        });

        // check that old token ownership was removed - a new transfer should fail
        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  indexes
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[2],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
    }

    function testTransferLPForTwoIndexes() external tearDown {
        uint256[] memory depositIndexes = new uint256[](3);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;

        uint256[] memory transferIndexes = new uint256[](2);
        transferIndexes[0] = 2550;
        transferIndexes[1] = 2552;

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  depositIndexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  depositIndexes[1]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 30_000 * 1e18,
            index:  depositIndexes[2]
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[0],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[2],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[2],
            lpBalance:   0,
            depositTime: 0
        });

        // set allowed owner to lender2 address
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 30_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, transferIndexes, amounts);

        // transfer LP for 2 indexes
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender2,
            indexes:   transferIndexes,
            lpBalance: 40_000 * 1e18
        });

        // check that old token ownership was removed - transfer with same indexes should fail
        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  transferIndexes
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[0],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[1],
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       depositIndexes[2],
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       depositIndexes[2],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime
        });
    }

    function testTransferLPToLenderWithLP() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 30_000 * 1e18,
            index:  indexes[2]
        });

        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender2,
            amount: 5_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender2,
            amount: 10_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   _lender2,
            amount: 15_000 * 1e18,
            index:  indexes[2]
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime + 2 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[1],
            lpBalance:   20_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime + 2 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[2],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[2],
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime + 2 hours
        });

        // set allowed owner to lender2 address
        changePrank(_lender1);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 20_000 * 1e18;
        amounts[2] = 30_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[1],
            lpAllowance: 20_000 * 1e18
        });

        // transfer LP for all indexes
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender2,
            indexes:   indexes,
            lpBalance: 60_000 * 1e18
        });

        // check that old token ownership was removed - transfer with same indexes should fail
        _assertTransferNoAllowanceRevert({
            operator: _lender,
            from:     _lender1,
            to:       _lender2,
            indexes:  indexes
        });
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[1],
            lpAllowance: 0
        });

        // check lenders lp balance
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   15_000 * 1e18,
            depositTime: _startTime + 2 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[1],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   30_000 * 1e18,
            depositTime: _startTime + 2 hours
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[2],
            lpBalance:   0,
            depositTime: _startTime + 1 hours
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[2],
            lpBalance:   45_000 * 1e18,
            depositTime: _startTime + 2 hours
        });
    }

    function testTransferLPApproveRevokeTransferors() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  indexes[1]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 30_000 * 1e18,
            index:  indexes[2]
        });
        // set allowed owner to lender2 address
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 20_000 * 1e18;
        amounts[2] = 30_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit IncreaseLPAllowance(_lender1, _lender2, indexes, amounts);
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        assertTrue(_pool.approvedTransferors(_lender2, _lender));

        // revoke transferor
        changePrank(_lender2);
        address[] memory transferors = new address[](1);
        transferors[0] = _lender;
        vm.expectEmit(true, true, false, true);
        emit RevokeLPTransferors(_lender2, transferors);
        _pool.revokeLPTransferors(transferors);
        assertFalse(_pool.approvedTransferors(_lender2, _lender));

        // transfer initiated by lender should fail as it is no longer an approved transferor
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.TransferorNotApproved.selector);
        _pool.transferLP(_lender1, _lender2, indexes);

        // reapprove transferor
        changePrank(_lender2);
        vm.expectEmit(true, true, false, true);
        emit ApproveLPTransferors(_lender2, transferors);
        _pool.approveLPTransferors(transferors);
        assertTrue(_pool.approvedTransferors(_lender2, _lender));

        // transfer LP for all indexes
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender2,
            indexes:   indexes,
            lpBalance: 60_000 * 1e18
        });
    }

    function testTransferLPAllowances() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;
        // set allowed owner to lender2 address
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 10_000 * 1e18;
        amounts[1] = 20_000 * 1e18;
        amounts[2] = 30_000 * 1e18;

        changePrank(_lender1);
        vm.expectEmit(true, true, false, true);
        emit IncreaseLPAllowance(_lender1, _lender2, indexes, amounts);
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        // check allowance after increasing allowance
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[0],
            lpAllowance: 10_000 * 1e18
        });

        // decrease allowance at two indexes
        indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;
        amounts = new uint256[](2);
        amounts[0] = 5_000 * 1e18;
        amounts[1] = 5_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit DecreaseLPAllowance(_lender1, _lender2, indexes, amounts);
        _pool.decreaseLPAllowance(_lender2, indexes, amounts);

        // check allowances after decreasing allowance
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[0],
            lpAllowance: 5_000 * 1e18
        });
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[1],
            lpAllowance: 15_000 * 1e18
        });

        // revoke allowance at two indexes
        indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;
        amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        vm.expectEmit(true, true, false, true);
        emit RevokeLPAllowance(_lender1, _lender2, indexes);
        _pool.revokeLPAllowance(_lender2, indexes);

        // check allowance after revoking allowance
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[0],
            lpAllowance: 0
        });
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[1],
            lpAllowance: 0
        });

        // approve a previously revoked index
        indexes = new uint256[](1);
        indexes[0] = 2550;
        amounts = new uint256[](1);
        amounts[0] = 5_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit IncreaseLPAllowance(_lender1, _lender2, indexes, amounts);
        _pool.increaseLPAllowance(_lender2, indexes, amounts);

        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender2,
            index:       indexes[0],
            lpAllowance: 5000 * 1e18
        });
    }

    function testTransferPartialLP() external tearDown {
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;

        _addInitialLiquidity({
            from:   _lender1,
            amount: 10_000 * 1e18,
            index:  indexes[0]
        });
        _addInitialLiquidity({
            from:   _lender1,
            amount: 20_000 * 1e18,
            index:  indexes[1]
        });

        // set transfer allowances for lender and lender2
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 5_000 * 1e18;
        amounts[1] = 10_000 * 1e18;
        _pool.increaseLPAllowance(_lender2, indexes, amounts);
        amounts = new uint256[](2);
        amounts[0] = 1_000 * 1e18;
        amounts[1] = 2_000 * 1e18;
        _pool.increaseLPAllowance(_lender, indexes, amounts);

        // lender 2 approves lender as transferor of LP
        changePrank(_lender2);
        address[] memory transferors = new address[](1);
        transferors[0] = _lender;
        _pool.approveLPTransferors(transferors);

        // lender transfers allowed LP from lender1
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender,
            indexes:   indexes,
            lpBalance: 3_000 * 1e18
        });
        _assertLpAllowance({
            owner:       _lender1,
            spender:     _lender,
            index:       indexes[0],
            lpAllowance: 0
        });

        // lender transfers allowed LP from lender1 to lender2
        _transferLP({
            operator:  _lender,
            from:      _lender1,
            to:        _lender2,
            indexes:   indexes,
            lpBalance: 15_000 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       indexes[0],
            lpBalance:   1_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[0],
            lpBalance:   4_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[0],
            lpBalance:   5_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       indexes[1],
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       indexes[1],
            lpBalance:   8_000 * 1e18,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender2,
            index:       indexes[1],
            lpBalance:   10_000 * 1e18,
            depositTime: _startTime
        });
    }
}
