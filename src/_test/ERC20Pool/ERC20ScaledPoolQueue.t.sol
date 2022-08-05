// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20ScaledQueueTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithCollateral internal _borrower2;
    UserWithCollateral internal _borrower3;
    UserWithCollateral internal _borrower4;
    UserWithCollateral internal _borrower5;
    UserWithCollateral internal _borrower6;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18 );
        _pool        = ERC20Pool(_poolAddress);

        _borrower   = new UserWithCollateral();
        _borrower2  = new UserWithCollateral();
        _borrower3  = new UserWithCollateral();
        _borrower4  = new UserWithCollateral();
        _borrower5  = new UserWithCollateral();
        _borrower6  = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _collateral.mint(address(_borrower2), 100 * 1e18);
        _collateral.mint(address(_borrower3), 100 * 1e18);
        _collateral.mint(address(_borrower4), 100 * 1e18);
        _collateral.mint(address(_borrower5), 100 * 1e18);
        _collateral.mint(address(_borrower6), 100 * 1e18);
        _quote.mint(address(_lender), 300_000 * 1e18);
        _quote.mint(address(_borrower), 100 * 1e18);
        _quote.mint(address(_borrower3), 100 * 1e18);

        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower2.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower3.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower4.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower5.approveToken(_collateral, address(_pool), 100 * 1e18);
        _borrower6.approveToken(_collateral, address(_pool), 100 * 1e18);

        _borrower.approveToken(_quote, address(_pool), 300_000 * 1e18);
        _borrower3.approveToken(_quote, address(_pool), 300_000 * 1e18);
        _lender.approveToken(_quote, address(_pool), 300_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower test adding collateral and borrowing.
     */
    function testAddLoanToQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrow max possible from hdp
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0));

        // check queue head was set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    /**
     *  @notice With 1 lender and 1 borrower test borrowing and avoidance of self referential ordering.
     *          Reverts:
     *              Borrower references themself instead of the correct queue state.
     */
    function testBorrowerSelfRefLoanQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.htp());

        // should revert if the borrower references themself and not the correct queue ordering
        vm.expectRevert("B:U:PNT_SELF_REF");
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(_borrower));
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and update of queue ordering on subsequent borrows.
     */
    function testMoveLoanInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        _borrower3.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower3.borrow(_pool, 10_000 * 1e18, 2551,  address(0), address(_borrower));

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower3 -> *borrower*
        _borrower.repay(_pool, 10_000 * 1e18, address(_borrower2), address(_borrower3));

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead())); 
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and subsequent movement to bottom of the queue.
     */
   function testMoveToBottom() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());

        // borrower deposits some collateral and draws debt
        _borrower.addCollateral(_pool, 40 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(0));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 deposits slightly less collateral and draws the same debt, producing a higher TP
        _borrower2.addCollateral(_pool, 39 * 1e18, address(0), address(_borrower));
        _borrower2.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(0));
        assertEq(address(_pool.loanQueueHead()), address(_borrower2));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 769.970414201183432308 * 1e18);

        // borrower2 deposits some collateral, reducing their TP, pushing it to the end of the queue
        _borrower2.addCollateral(_pool, 42 * 1e18, address(0), address(_borrower));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 370.726495726495726667 * 1e18);
        assertEq(next, address(0));

        // borrower2 draws more debt, but should still be at the end of queue; should revert passing wrong oldPrev
        vm.expectRevert("B:U:OLDPREV_WRNG");
        _borrower2.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(_borrower));

        _borrower2.borrow(_pool, 30_000 * 1e18, 2551, address(_borrower), address(_borrower));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 741.452991452991453333 * 1e18);
        assertEq(next, address(0));

        assertEq(address(_borrower), address(0x70BEce5a3D1a6eFBC54e1A134cfF3b47EF346bbE));
        assertEq(address(_borrower2), address(0xB4FFCD625FefD541b77925c7A37A55f488bC69d9));

        // confirm rest of queue is in the correct order
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);
        assertEq(next, address(_borrower2));
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and updating the loanQueueHead.
     */
    function testMoveLoanToHeadInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrower becomes head
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // borrower2 replaces borrower as head
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower replaces borrower2 as head
        _borrower.borrow(_pool, 10_000 * 1e18, 2551, address(_borrower2), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(_borrower2));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    /**
     *  @notice With 1 lender and 3 borrowers test borrowing that changes TP, but doesn't change queue order
     */
    function testMoveToSameLocation() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());

        // borrower deposits some collateral and draws debt
        _borrower.addCollateral(_pool, 40 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(0));
        (uint256 thresholdPrice, ) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 draws slightly more debt producing a higher TP
        _borrower2.addCollateral(_pool, 40 * 1e18, address(0), address(0));
        _borrower2.borrow(_pool, 31_000 * 1e18, 2551, address(0), address(0));
        (thresholdPrice, ) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 775.745192307692308050 * 1e18);

        // borrower3 draws slightly more debt producing a higher TP
        _borrower3.addCollateral(_pool, 40 * 1e18, address(0), address(0));
        _borrower3.borrow(_pool, 32_000 * 1e18, 2551, address(0), address(0));
        (thresholdPrice, ) = _pool.loans(address(_borrower3));
        assertEq(thresholdPrice, 800.769230769230769600 * 1e18);

        // borrower2 adds collateral, decreasing their TP, but maintaining their same position in queue
        _borrower2.addCollateral(_pool, 0.1 * 1e18, address(_borrower3), address(_borrower3));
        (thresholdPrice, ) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 773.810665643583349676 * 1e18);

        // confirm queue is in the correct order
        assertEq(address(_pool.loanQueueHead()), address(_borrower3));

        (, address next) = _pool.loans(address(_borrower3));
        assertEq(next, address(_borrower2));

        (, next) = _pool.loans(address(_borrower2));
        assertEq(next, address(_borrower));

        (, next) = _pool.loans(address(_borrower));
        assertEq(next, address(0));
    }

    // TODO: write test where we remove the head (oldPrev_ == 0)
    // TODO: write test for removal during/after liquidation
    /**
     *  @notice With 1 lender and 2 borrowers test borrowing, with subsequent repayment and removal of one of the loans.
     */
    function testRemoveLoanInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        ( , uint256 pendingDebt, , ) = _pool.borrowerInfo(address(_borrower));

        // borrower2(HEAD)
        _borrower.repay(_pool, pendingDebt, address(_borrower2), address(0));

        // check that borrower 1 has been removed from the queue, and queue head was updated to borrower 2
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(thresholdPrice, 0);
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        (, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(0));
    }

    // TODO: test with multiple borrowers and update of threshold prices causing queue reordering
    /**
     *  @notice With 1 lender and 1 borrower test adding collateral, borrowing, and adding additional collateral. 
     *  Check that loan queue updates, and threshold price shifts on each action.
     */
    function testUpdateLoanQueueAddCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrower 1 borrows and becomes initial HEAD
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0));

        // check queue head and threshold price were set correctly
        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.addCollateral(_pool, 11 * 1e18, address(0), address(0));

        (debt, , collateral, ) = _pool.borrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    /**
     *  @notice With 1 lender and 1 borrower test adding collateral, borrowing, and removing collateral. 
     *  Check that loan queue updates on each action.
     */
    function testUpdateLoanQueueRemoveCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.removeCollateral(_pool, 11 * 1e18, address(0), address(0));

        (debt, , collateral, ) = _pool.borrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    /**
     *  @notice With 1 lender and 2 borrower test borrowing and proper ordering in params.
     *          Reverts:
     *              Borrower supplies the wrong order when borrowing themself instead of the correct queue state.
     */
    function testWrongOrder() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());

        // borrower deposits some collateral and draws debt
        _borrower.addCollateral(_pool, 40 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(0));
        (uint256 thresholdPrice, ) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 successfully deposits slightly less collateral
        _borrower2.addCollateral(_pool, 39.9 * 1e18, address(0), address(_borrower));

        // borrower2 draws the same debt, producing a higher TP, but supplies the wrong order
        vm.expectRevert("B:U:QUE_WRNG_ORD_P");
        _borrower2.borrow(_pool, 30_000 * 1e18, 2551, address(0), address(_borrower));
    }

    /**
     *  @notice With 1 lender and 1 borrower test borrowing and check threshold price is correctly set.
     */
    function testGetHighestThresholdPrice() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0));
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.htp());
    }

}
