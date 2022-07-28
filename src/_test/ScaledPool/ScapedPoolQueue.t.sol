// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ScaledPool }        from "../../ScaledPool.sol";
import { ScaledPoolFactory } from "../../ScaledPoolFactory.sol";

import { BucketMath }        from "../../libraries/BucketMath.sol";
import { Maths }             from "../../libraries/Maths.sol";

import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateralInScaledPool, UserWithQuoteTokenInScaledPool } from "../utils/Users.sol";

contract ScaledQueueTest is DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address                        internal _poolAddress;
    CollateralToken                internal _collateral;
    ScaledPool                     internal _pool;
    QuoteToken                     internal _quote;
    UserWithCollateralInScaledPool internal _borrower;
    UserWithCollateralInScaledPool internal _borrower2;
    UserWithCollateralInScaledPool internal _borrower3;
    UserWithCollateralInScaledPool internal _borrower4;
    UserWithCollateralInScaledPool internal _borrower5;
    UserWithCollateralInScaledPool internal _borrower6;
    UserWithQuoteTokenInScaledPool internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ScaledPoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18 );
        _pool        = ScaledPool(_poolAddress);

        _borrower   = new UserWithCollateralInScaledPool();
        _borrower2  = new UserWithCollateralInScaledPool();
        _borrower3  = new UserWithCollateralInScaledPool();
        _borrower4  = new UserWithCollateralInScaledPool();
        _borrower5  = new UserWithCollateralInScaledPool();
        _borrower6  = new UserWithCollateralInScaledPool();
        _lender     = new UserWithQuoteTokenInScaledPool();

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

    function testAddLoanToQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrow max possible from hdp
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0), _r3);

        // check queue head was set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    /**
     *  @notice With 1 lender and 1 borrower test borrowing and avoidance of self referential ordering.
     *          Reverts:
     *              Borrow references themself instead of the correct queue state.
     */
    function testBorrowerSelfRefLoanQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.getHighestThresholdPrice());

        // should revert if the borrower references themself and not the correct queue ordering
        vm.expectRevert("B:U:PNT_SELF_REF");
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(_borrower), _r3);
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and update of queue ordering on subsequent borrows.
     */
    function testMoveLoanInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        _borrower3.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower3.borrow(_pool, 10_000 * 1e18, 2551,  address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower3 -> *borrower*
        _borrower.repay(_pool, 10_000 * 1e18, address(_borrower2), address(_borrower3), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead())); 
    }

    /**
     *  @notice With 1 lender and 2 borrowers test borrowing and updating the loanQueueHead.
     */
    function testMoveLoanToHeadInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrower becomes head
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // borrower2 replaces borrower as head
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower replaces borrower2 as head
        _borrower.borrow(_pool, 10_000 * 1e18, 2551, address(_borrower2), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(_borrower2));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    // TODO: finish implementing
    function testMoveToSameLocation() public {

    }

    // FIXME: this test is currently broken: AMT_LT_AVG_DEBT
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
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3 );

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD)
        _borrower.repay(_pool, 15_000.000961538461538462 * 1e18, address(_borrower2), address(0), _r3);

        // check that borrower 1 has been removed from the queue, and queue head was updated to borrower 2
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(thresholdPrice, 0);
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        (, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(0));
    }

    // FIXME: this test is currently broken: AMT_LT_AVG_DEBT
    // TODO: write test with radius of 0
    // TODO: write test with decimal radius
    // TODO: write test with radius larger than queue
    function testRadiusInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2551, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        _borrower3.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower3.borrow(_pool, 10_000 * 1e18, 2551, address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> *borrower4*
        _borrower4.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower4.borrow(_pool, 5_000 * 1e18, 2551, address(0), address(_borrower3), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower4));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> *borrower5*
        _borrower5.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower5.borrow(_pool, 2_000 * 1e18, 2551, address(0), address(_borrower4), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower5));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));


        // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> borrower5 -> *borrower6*
        _borrower6.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);

        // newPrev passed in is incorrect & radius is too small, revert
        vm.expectRevert("B:S:SRCH_RDS_FAIL");
        _borrower6.borrow(_pool, 1_000 * 1e18, 2551, address(0), address(_borrower), _r1);

        // newPrev passed in is incorrect & radius supports correct placement
        _borrower6.borrow(_pool, 1_000 * 1e18, 2551, address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower6));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        (thresholdPrice, next) = _pool.loans(address(_borrower4));
        assertEq(address(next), address(_borrower5));

        (thresholdPrice, next) = _pool.loans(address(_borrower5));
        assertEq(address(next), address(_borrower6));

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(_borrower3));
    }

    // TODO: test with multiple borrowers and update of threshold prices causing queue reordering
    function testUpdateLoanQueueAddCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // borrower 1 borrows and becomes initial HEAD
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3);

        // check queue head and threshold price were set correctly
        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.addCollateral(_pool, 11 * 1e18, address(0), address(0), _r3);

        (debt, , collateral, ) = _pool.borrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    function testUpdateLoanQueueRemoveCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.removeCollateral(_pool, 11 * 1e18, address(0), address(0), _r3);

        (debt, , collateral, ) = _pool.borrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    // TODO: finish implementing
    function testWrongOrder() public {

    }

    function testGetHighestThresholdPrice() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2549);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2550);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, 2551);

        assertEq(0, _pool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2551, address(0), address(0), _r3);

        (uint256 debt, , uint256 collateral, ) = _pool.borrowerInfo(address(_borrower));

        // check queue head and threshold price were set correctly
        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.getHighestThresholdPrice());
    }



}
