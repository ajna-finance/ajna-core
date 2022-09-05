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

    struct BorrowParams {
        address from;
        address borrower;
        uint256 amountToPledge; 
        uint256 amountToBorrow;
        uint256 indexLimit;
        address oldPrev;
        address newPrev;
        uint256 price;
    }

    struct Liquidity {
        uint256 index;  // bucket index
        uint256 amount; // amount to add
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

    function _addLiquidity(AddLiquidity memory liquidity) internal {
        changePrank(liquidity.from);
        for (uint256 i = 0; i < liquidity.amounts.length; ++i) {
            _pool.addQuoteToken(liquidity.amounts[i].amount, liquidity.amounts[i].index);
        }
    }

    function _borrow(BorrowParams memory borrow) internal {
        changePrank(borrow.from);
        _pool.pledgeCollateral(borrow.borrower, borrow.amountToPledge, borrow.oldPrev, borrow.newPrev);

        vm.expectEmit(true, true, false, true);
        emit Borrow(borrow.borrower, borrow.price, 21_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(_pool), borrow.from, 21_000 * 1e18);
        _pool.borrow(borrow.amountToBorrow, borrow.indexLimit, borrow.oldPrev, borrow.newPrev);
    }

    function _assertPoolState(PoolState memory poolState) internal {
        assertEq(_pool.htp(), poolState.htp);
        assertEq(_pool.lup(), poolState.lup);

        assertEq(_pool.poolSize(),              poolState.poolSize);
        assertEq(_pool.borrowerDebt(),          poolState.borrowerDebt);
        assertEq(_pool.poolActualUtilization(), poolState.actualUtilization);
        assertEq(_pool.poolTargetUtilization(), poolState.targetUtilization);
        assertEq(_pool.poolMinDebtAmount(),     poolState.minDebtAmount);
    }
}
