// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import { ERC20 }      from "@solmate/tokens/ERC20.sol";

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { DSTestPlus } from "../utils/DSTestPlus.sol";
import { Token }      from "../utils/Tokens.sol";

abstract contract ERC20DSTestPlus is DSTestPlus {

    // ERC20 events
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    // Pool events
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event PledgeCollateral(address indexed borrower_, uint256 amount_);
    event PullCollateral(address indexed borrower_, uint256 amount_);
    event RemoveCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event Repay(address indexed borrower_, uint256 lup_, uint256 amount_);

    /*****************/
    /*** Utilities ***/
    /*****************/

    struct AddLiquidity {
        address from;        // lender address
        Liquidity[] amounts; // liquidities to add
    }

    struct BorrowSpecs {
        address from;
        address borrower;
        uint256 pledgeAmount; 
        uint256 borrowAmount;
        uint256 indexLimit;
        address oldPrev;
        address newPrev;
        uint256 price;
    }

    struct PledgeSpecs {
        address from;
        address borrower;
        uint256 amount; 
        address oldPrev;
        address newPrev;
    }

    struct PullSpecs {
        address from;
        uint256 amount; 
        address oldPrev;
        address newPrev;
    }

    struct RepaySpecs {
        address from;
        address borrower;
        uint256 repayAmount; 
        address oldPrev;
        address newPrev;
        uint256 price;
    }

    struct Liquidity {
        uint256 index;  // bucket index
        uint256 amount; // amount to add
    }

    struct LenderLPs {
        address    lender;
        BucketLP[] bucketLPs;
    }

    struct BucketLP {
        uint256 index;
        uint256 balance;
        uint256 time;
    }

    struct BucketState {
        uint256 index;
        uint256 LPs;
        uint256 collateral;
    }

    struct BorrowerState {
        address borrower;
        uint256 debt;
        uint256 pendingDebt;
        uint256 collateral;
        uint256 inflator;
    }

    struct PoolState {
        uint256 htp;
        uint256 lup;
        uint256 poolSize;
        uint256 borrowerDebt;
        uint256 actualUtilization;
        uint256 targetUtilization;
        uint256 minDebtAmount;
    }

    function assertERC20Eq(ERC20 erc1_, ERC20 erc2_) internal {
        assertEq(address(erc1_), address(erc2_));
    }

}

// TODO: merge this contract with parent ERC20DSTestPlus
abstract contract ERC20HelperContract is ERC20DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    Token     internal _collateral;
    Token     internal _quote;
    ERC20Pool internal _pool;

    constructor() {
        _collateral = new Token("Collateral", "C");
        _quote      = new Token("Quote", "Q");
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
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

    function _addLiquidity(AddLiquidity memory specs_) internal {
        changePrank(specs_.from);
        for (uint256 i = 0; i < specs_.amounts.length; ++i) {
            _pool.addQuoteToken(specs_.amounts[i].amount, specs_.amounts[i].index);
        }
    }

    function _borrow(BorrowSpecs memory specs_) internal {
        changePrank(specs_.from);
        if (specs_.pledgeAmount != 0) _pool.pledgeCollateral(specs_.borrower, specs_.pledgeAmount, specs_.oldPrev, specs_.newPrev);

        vm.expectEmit(true, true, false, true);
        emit Borrow(specs_.borrower, specs_.price, specs_.borrowAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), specs_.from, specs_.borrowAmount);
        _pool.borrow(specs_.borrowAmount, specs_.indexLimit, specs_.oldPrev, specs_.newPrev);
    }

    function _pledgeCollateral(PledgeSpecs memory specs_) internal {
        changePrank(specs_.from);
        _pool.pledgeCollateral(specs_.borrower, specs_.amount, specs_.oldPrev, specs_.newPrev);
    }

    function _pullCollateral(PullSpecs memory specs_) internal {
        changePrank(specs_.from);
        _pool.pullCollateral(specs_.amount, specs_.oldPrev, specs_.newPrev);
    }

    function _repay(RepaySpecs memory specs_) internal {
        changePrank(specs_.from);
        
        vm.expectEmit(true, true, false, true);
        emit Repay(specs_.borrower, specs_.price, specs_.repayAmount);
        vm.expectEmit(true, true, false, true);
        emit Transfer(specs_.from, address(_pool), specs_.repayAmount);
        _pool.repay(specs_.borrower, specs_.repayAmount, specs_.oldPrev, specs_.newPrev);
    }

    function _assertPool(PoolState memory state_) internal {
        assertEq(_pool.htp(), state_.htp);
        assertEq(_pool.lup(), state_.lup);

        assertEq(_pool.poolSize(),              state_.poolSize);
        assertEq(_pool.borrowerDebt(),          state_.borrowerDebt);
        assertEq(_pool.poolActualUtilization(), state_.actualUtilization);
        assertEq(_pool.poolTargetUtilization(), state_.targetUtilization);
        assertEq(_pool.poolMinDebtAmount(),     state_.minDebtAmount);
    }

    function _assertLPs(LenderLPs memory specs_) internal {
        for (uint256 i = 0; i < specs_.bucketLPs.length; ++i) {
            (uint256 lpBalance, uint256 time) = _pool.bucketLenders(specs_.bucketLPs[i].index, specs_.lender);
            assertEq(lpBalance, specs_.bucketLPs[i].balance);
            assertEq(time,      specs_.bucketLPs[i].time);
        }
    }

    function _assertBuckets(BucketState[] memory state_) internal {
        for (uint256 i = 0; i < state_.length; ++i) {
            (uint256 lpAccumulator, uint256 availableCollateral) = _pool.buckets(state_[i].index);
            assertEq(lpAccumulator,       state_[i].LPs);
            assertEq(availableCollateral, state_[i].collateral);
        }
    }

    function _assertBorrower(BorrowerState memory state_) internal {
        (uint256 debt, uint256 pendingDebt, uint256 col, uint256 inflator) = _pool.borrowerInfo(state_.borrower);
        assertEq(debt,        state_.debt);
        assertEq(pendingDebt, state_.pendingDebt);
        assertEq(col,         state_.collateral);
        assertEq(inflator,    state_.inflator);
    }
}
