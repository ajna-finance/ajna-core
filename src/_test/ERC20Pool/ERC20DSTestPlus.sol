// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { DSTestPlus } from '../utils/DSTestPlus.sol';
import { Token }      from '../utils/Tokens.sol';

import { ERC20Pool }        from '../../erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from '../../erc20/ERC20PoolFactory.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/IPoolFactory.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';

abstract contract ERC20DSTestPlus is DSTestPlus {

    // Pool events
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event PledgeCollateral(address indexed borrower_, uint256 amount_);

    event Transfer(address indexed from, address indexed to, uint256 value);

    /*****************/
    /*** Utilities ***/
    /*****************/

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _assertTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, to, amount / _pool.quoteTokenScale());
    }

    function _addCollateral(
        address from,
        uint256 amount,
        uint256 index
    ) internal returns (uint256) {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AddCollateral(from, index, amount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), amount);
        return ERC20Pool(address(_pool)).addCollateral(amount, index);
    }

    function _moveCollateral(
        address from,
        uint256 amount,
        uint256 fromIndex, 
        uint256 toIndex,
        uint256 lpRedeemFrom,
        uint256 lpRedeemTo
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit MoveCollateral(from, fromIndex, toIndex, amount);
        (uint256 lpbFrom, uint256 lpbTo) = ERC20Pool(address(_pool)).moveCollateral(amount, fromIndex, toIndex);
        assertEq(lpbFrom, lpRedeemFrom);
        assertEq(lpbTo,   lpRedeemTo);
    }

    function _pledgeCollateral(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit PledgeCollateral(borrower, amount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), amount / ERC20Pool(address(_pool)).collateralScale());
        ERC20Pool(address(_pool)).pledgeCollateral(borrower, amount);
    }

    function _removeAllCollateral(
        address from,
        uint256 amount,
        uint256 index,
        uint256 lpRedeem
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, true, true);
        emit RemoveCollateral(from, index, amount);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), from, amount);
        (uint256 collateralRemoved, uint256 lpAmount) = ERC20Pool(address(_pool)).removeAllCollateral(index);
        assertEq(collateralRemoved, amount);
        assertEq(lpAmount, lpRedeem);
    }

    function _transferLpTokens(
        address operator,
        address from,
        address to,
        uint256 lpBalance,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectEmit(true, true, true, true);
        emit TransferLPTokens(from, to, indexes, lpBalance);
        _pool.transferLPTokens(from, to, indexes);
    }


    /**********************/
    /*** Revert asserts ***/
    /**********************/

    function _assertAddCollateralBankruptcyBlockRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('BucketBankruptcyBlock()'));
        ERC20Pool(address(_pool)).addCollateral(amount, index);
    }

    function _assertDeployWith0xAddressRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.DeployWithZeroAddress.selector);
        ERC20PoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertDeployWithInvalidRateRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.PoolInterestRateInvalid.selector);
        ERC20PoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertDeployMultipleTimesRevert(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.PoolAlreadyExists.selector);
        ERC20PoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertMoveCollateralInsufficientLPsRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLPs.selector);
        ERC20Pool(address(_pool)).moveCollateral(amount, fromIndex, toIndex);
    }

    function _assertMoveCollateralToSamePriceRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.MoveToSamePrice.selector);
        ERC20Pool(address(_pool)).moveCollateral(amount, fromIndex, toIndex);
    }

    function _assertMoveInsufficientCollateralRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC20Pool(address(_pool)).moveCollateral(amount, fromIndex, toIndex);
    }

    function _assertRemoveAllCollateralNoClaimRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        ERC20Pool(address(_pool)).removeAllCollateral(index);
    }

    function _assertTransferInvalidIndexRevert(
        address operator,
        address from,
        address to,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.transferLPTokens(from, to, indexes);
    }

    function _assertTransferNoAllowanceRevert(
        address operator,
        address from,
        address to,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.NoAllowance.selector);
        _pool.transferLPTokens(from, to, indexes);
    }

}

abstract contract ERC20HelperContract is ERC20DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    uint  internal _anonBorrowerCount = 0;
    Token internal _collateral;
    Token internal _quote;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _collateral = new Token("Collateral", "C");
        _quote      = new Token("Quote", "Q");
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils  = new PoolInfoUtils();
        _startTime  = block.timestamp;
    }

    /**
     *  @dev Creates debt for an anonymous non-player borrower not otherwise involved in the test.
     **/
    function _anonBorrowerDrawsDebt(uint256 collateralAmount, uint256 loanAmount, uint256 limitIndex) internal {
        _anonBorrowerCount += 1;
        address borrower = makeAddr(string(abi.encodePacked("anonBorrower", _anonBorrowerCount)));
        vm.stopPrank();
        _mintCollateralAndApproveTokens(borrower,  collateralAmount);
        _pledgeCollateral(
            {
                from:     borrower,
                borrower: borrower,
                amount:   collateralAmount
            }
        );
        _pool.borrow(loanAmount, limitIndex);
    }

    function _mintQuoteAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
    }

    function _mintCollateralAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_collateral), operator_, mintAmount_);

        vm.prank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
        vm.prank(operator_);
        _quote.approve(address(_pool), type(uint256).max);

    }
}