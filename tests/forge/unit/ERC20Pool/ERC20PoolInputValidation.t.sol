// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/commons/IPoolErrors.sol';

import 'src/ERC20Pool.sol';

contract ERC20PoolBorrowTest is ERC20HelperContract {

    function testValidateAddQuoteTokenInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.addQuoteToken(0, 1000, block.timestamp + 1, false);
        // revert on zero index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.addQuoteToken(1000, 0, block.timestamp + 1, false);
        // revert on index greater than max index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.addQuoteToken(1000, MAX_FENWICK_INDEX + 1, block.timestamp + 1, false);
    }

    function testValidateMoveQuoteTokenInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.moveQuoteToken(0, 1, 2, block.timestamp + 1, false);
        // revert on move to same index
        vm.expectRevert(IPoolErrors.MoveToSameIndex.selector);
        _pool.moveQuoteToken(1000, 1, 1, block.timestamp + 1, false);
        // revert on to zero index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.moveQuoteToken(1000, 1, 0, block.timestamp + 1, false);
        // revert on to index greater than max index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.moveQuoteToken(1000, 1, MAX_FENWICK_INDEX + 1, block.timestamp + 1, false);
    }

    function testValidateRemoveQuoteTokenInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.removeQuoteToken(0, 1000);
        // revert on zero index when enough quote available
        deal(address(_quote), address(_pool), 5000);
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        _pool.removeQuoteToken(1000, 0);
        // revert on index greater than max index
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        _pool.removeQuoteToken(1000, MAX_FENWICK_INDEX + 1);
    }

    function testValidateTakeReservesInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        _pool.takeReserves(0);
    }

    function testValidateDrawDebtInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).drawDebt(address(this), 0, 0, 0);
    }

    function testValidateRepayDebtInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).repayDebt(address(this), 0, 0, address(this), 1);
    }

    function testValidateAddCollateralInput() external tearDown {
        // revert on zero index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        ERC20Pool(address(_pool)).addCollateral(1000 * 1e18, 0, block.timestamp + 1);
        // revert on index greater than max index
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        ERC20Pool(address(_pool)).addCollateral(1000 * 1e18, MAX_FENWICK_INDEX + 1, block.timestamp + 1);
    }

    function testValidateRemoveCollateralInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).removeCollateral(0, 1000);
    }

    function testValidateTakeInput() external tearDown {
        // revert on zero amount
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).take(address(this), 0, address(this), new bytes(0));
    }
}
