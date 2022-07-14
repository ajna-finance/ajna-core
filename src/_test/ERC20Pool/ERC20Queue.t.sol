
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from "../../erc20/ERC20Pool.sol";
import { ERC20PoolFactory } from "../../erc20/ERC20PoolFactory.sol";

import { Maths }      from "../../libraries/Maths.sol";

import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

import { DSTestPlus } from "../utils/DSTestPlus.sol";

contract LoanQueueTest is DSTestPlus {

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
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
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

    function testAddLoanToQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // borrow max possible from hdp
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    function testGetHighestThresholdPrice() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        assertEq(0, _pool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, ,uint256 collateral, , , , ) = _pool.getBorrowerInfo(address(_borrower));

        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.getHighestThresholdPrice());
    }

    function testBorrowerSelfRefLoanQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        assertEq(0, _pool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, ,uint256 collateral, , , , ) = _pool.getBorrowerInfo(address(_borrower));

        (, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral), _pool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        vm.expectRevert("B:U:PNT_SELF_REF");
        _borrower.borrow(_pool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r3);
    }


    function testMoveLoanToHeadInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // borrower becomes head
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // borrower2 replaces borrower as head
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower replaces borrower2 as head
        _borrower.borrow(_pool, 10_000 * 1e18, 2_000 * 1e18, address(_borrower2), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(_borrower2));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
    }

    function testMoveLoanInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        _borrower3.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower3.borrow(_pool, 10_000 * 1e18, 2_000 * 1e18,  address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower3 -> *borrower*
        _borrower.repay(_pool, 10_000 * 1e18, address(_borrower2), address(_borrower3), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead())); 
    }

    function testupdateLoanQueueRemoveCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, , uint256 collateral,,,,) = _pool.getBorrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.removeCollateral(_pool, 11 * 1e18, address(0), address(0), _r3);

        (debt, , collateral,,,,) = _pool.getBorrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    function testupdateLoanQueueAddCollateral() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, , uint256 collateral,,,,) = _pool.getBorrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));

        _borrower.addCollateral(_pool, 11 * 1e18, address(0), address(0), _r3);

        (debt, , collateral,,,,) = _pool.getBorrowerInfo(address(_borrower));
        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral));
    }

    // TODO: write test where we remove the head (oldPrev_ == 0)
    // TODO: write test for removal during/after liquidation
    function testRemoveLoanInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3 );

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD)
        _borrower.repay(_pool, 15_000.000961538461538462 * 1e18, address(_borrower2), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(thresholdPrice, 0);
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        (, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(0));
    }

    // TODO: write test with radius of 0 
    // TODO: write test with decimal radius
    // TODO: write test with radius larger than queue
    function testRadiusInQueue() public {
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_pool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower.borrow(_pool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _pool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_pool.loanQueueHead()));

        // *borrower2(HEAD)* -> borrower
        _borrower2.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower2.borrow(_pool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> *borrower3*
        _borrower3.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower3.borrow(_pool, 10_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> *borrower4*
        _borrower4.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower4.borrow(_pool, 5_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower3), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower4));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> *borrower5*
        _borrower5.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
        _borrower5.borrow(_pool, 2_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower4), _r3);

        (thresholdPrice, next) = _pool.loans(address(_borrower5));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_pool.loanQueueHead()));


       // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> borrower5 -> *borrower6*
       _borrower6.addCollateral(_pool, 51 * 1e18, address(0), address(0), _r3);
       // newPrev passed in is incorrect & radius is too small, revert
       vm.expectRevert("B:S:SRCH_RDS_FAIL");
       _borrower6.borrow(_pool, 1_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r1);

       // newPrev passed in is incorrect & radius supports correct placement
       _borrower6.borrow(_pool, 1_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r2);

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





}