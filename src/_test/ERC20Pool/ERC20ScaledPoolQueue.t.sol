// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { DSTestPlus }                  from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC20ScaledQueueTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _borrower4;
    address internal _borrower5;
    address internal _borrower6;
    address internal _lender;

    CollateralToken internal _collateral;
    QuoteToken      internal _quote;
    ERC20Pool       internal _pool;

    function setUp() external {
        _collateral = new CollateralToken();
        _quote      = new QuoteToken();
        _pool       = ERC20Pool(new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18));

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _borrower4 = makeAddr("borrower4");
        _borrower5 = makeAddr("borrower5");
        _borrower6 = makeAddr("borrower6");
        _lender    = makeAddr("lender");

        deal(address(_collateral), _borrower,  100 * 1e18);
        deal(address(_collateral), _borrower2, 100 * 1e18);
        deal(address(_collateral), _borrower3, 100 * 1e18);
        deal(address(_collateral), _borrower4, 100 * 1e18);
        deal(address(_collateral), _borrower5, 100 * 1e18);
        deal(address(_collateral), _borrower6, 100 * 1e18);

        deal(address(_quote), _lender,    300_000 * 1e18);
        deal(address(_quote), _borrower,  100 * 1e18);
        deal(address(_quote), _borrower3, 100 * 1e18);

        vm.startPrank(_borrower);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 300_000 * 1e18);

        changePrank(_borrower2);
        _collateral.approve(address(_pool), 100 * 1e18);

        changePrank(_borrower3);
        _collateral.approve(address(_pool), 100 * 1e18);
        _quote.approve(address(_pool), 300_000 * 1e18);

        changePrank(_borrower4);
        _collateral.approve(address(_pool), 100 * 1e18);

        changePrank(_borrower5);
        _collateral.approve(address(_pool), 100 * 1e18);

        changePrank(_borrower6);
        _collateral.approve(address(_pool), 100 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_pool), 300_000 * 1e18);

        _pool.addQuoteToken(50_000 * 1e18, 2549);
        _pool.addQuoteToken(50_000 * 1e18, 2550);
        _pool.addQuoteToken(50_000 * 1e18, 2551);

        assertEq(0, _pool.htp());
    }

    /**
     *  @notice With 1 lender and 1 borrower test adding collateral and borrowing.
     */
    function testAddLoanToQueue() public {
        // borrow max possible from hdp
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(50_000 * 1e18, 2551, address(0), address(0));

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
        // borrow and insert into the Queue
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(50_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.htp());

        // should revert if the borrower references themself and not the correct queue ordering
        vm.expectRevert("B:U:PNT_SELF_REF");
        _pool.borrow(50_000 * 1e18, 2551, address(0), address(_borrower));
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and update of queue ordering on subsequent borrows.
     */
    function testMoveLoanInQueue() public {
        // *borrower(HEAD)*
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        changePrank(_borrower2);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        changePrank(_borrower3);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(10_000 * 1e18, 2551,  address(0), address(_borrower));

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower3 -> *borrower*
        changePrank(_borrower);
        _pool.repay(10_000 * 1e18, address(_borrower2), address(_borrower3));

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead())); 
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and subsequent movement to bottom of the queue.
     */
   function testMoveToBottom() public {
        // borrower deposits some collateral and draws debt
        changePrank(_borrower);
        _pool.pledgeCollateral(40 * 1e18, address(0), address(0));
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(0));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 deposits slightly less collateral and draws the same debt, producing a higher TP
        changePrank(_borrower2);
        _pool.pledgeCollateral(39 * 1e18, address(0), address(_borrower));
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(0));
        assertEq(address(_pool.loanQueueHead()), address(_borrower2));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 769.970414201183432308 * 1e18);

        // borrower2 deposits some collateral, reducing their TP, pushing it to the end of the queue
        _pool.pledgeCollateral(42 * 1e18, address(0), address(_borrower));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 370.726495726495726667 * 1e18);
        assertEq(next, address(0));

        // borrower2 draws more debt, but should still be at the end of queue; should revert passing wrong oldPrev
        vm.expectRevert("B:U:OLDPREV_WRNG");
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(_borrower));

        _pool.borrow(30_000 * 1e18, 2551, address(_borrower), address(_borrower));
        assertEq(address(_pool.loanQueueHead()), address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 741.452991452991453333 * 1e18);
        assertEq(next, address(0));

        // confirm rest of queue is in the correct order
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);
        assertEq(next, address(_borrower2));
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and updating the loanQueueHead.
     */
    function testMoveLoanToHeadInQueue() public {
         // borrower becomes head
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // borrower2 replaces borrower as head
        changePrank(_borrower2);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower replaces borrower2 as head
        changePrank(_borrower);
        _pool.borrow(10_000 * 1e18, 2551, address(_borrower2), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(_borrower2));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    /**
     *  @notice With 1 lender and 3 borrowers test borrowing that changes TP, but doesn't change queue order
     */
    function testMoveToSameLocation() public {
        // borrower deposits some collateral and draws debt
        changePrank(_borrower);
        _pool.pledgeCollateral(40 * 1e18, address(0), address(0));
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(0));
        (uint256 thresholdPrice, ) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 draws slightly more debt producing a higher TP
        changePrank(_borrower2);
        _pool.pledgeCollateral(40 * 1e18, address(0), address(0));
        _pool.borrow(31_000 * 1e18, 2551, address(0), address(0));
        (thresholdPrice, ) = _pool.loans(address(_borrower2));
        assertEq(thresholdPrice, 775.745192307692308050 * 1e18);

        // borrower3 draws slightly more debt producing a higher TP
        changePrank(_borrower3);
        _pool.pledgeCollateral(40 * 1e18, address(0), address(0));
        _pool.borrow(32_000 * 1e18, 2551, address(0), address(0));
        (thresholdPrice, ) = _pool.loans(address(_borrower3));
        assertEq(thresholdPrice, 800.769230769230769600 * 1e18);

        // borrower2 adds collateral, decreasing their TP, but maintaining their same position in queue
        changePrank(_borrower2);
        _pool.pledgeCollateral(0.1 * 1e18, address(_borrower3), address(_borrower3));
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
        // *borrower(HEAD)*
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 2551, address(0), address(0));

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        changePrank(_borrower2);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(20_000 * 1e18, 2551, address(0), address(0));

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        ( , uint256 pendingDebt, , ) = _pool.borrowerInfo(address(_borrower));

        // borrower2(HEAD)
        changePrank(_borrower);
        _pool.repay(pendingDebt, address(_borrower2), address(0));

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
    function testUpdateLoanQueuePledgeCollateral() public {
        // borrower 1 borrows and becomes initial HEAD
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 2551, address(0), address(0));

        // check queue head and threshold price were set correctly
        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _pool.pledgeCollateral(11 * 1e18, address(0), address(0));

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
    function testUpdateLoanQueuePullCollateral() public {
        // *borrower(HEAD)*
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(15_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _pool.pullCollateral(11 * 1e18, address(0), address(0));

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
        // borrower deposits some collateral and draws debt
        changePrank(_borrower);
        _pool.pledgeCollateral(40 * 1e18, address(0), address(0));
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(0));
        (uint256 thresholdPrice, ) = _pool.loans(address(_borrower));
        assertEq(thresholdPrice, 750.721153846153846500 * 1e18);

        // borrower2 successfully deposits slightly less collateral
        changePrank(_borrower2);
        _pool.pledgeCollateral(39.9 * 1e18, address(0), address(_borrower));

        // borrower2 draws the same debt, producing a higher TP, but supplies the wrong order
        vm.expectRevert("B:U:QUE_WRNG_ORD_P");
        _pool.borrow(30_000 * 1e18, 2551, address(0), address(_borrower));
    }

    /**
     *  @notice With 1 lender and 1 borrower test borrowing and check threshold price is correctly set.
     */
    function testGetHighestThresholdPrice() public {
        // borrow and insert into the Queue
        changePrank(_borrower);
        _pool.pledgeCollateral(51 * 1e18, address(0), address(0));
        _pool.borrow(50_000 * 1e18, 2551, address(0), address(0));

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.htp());
    }

}
