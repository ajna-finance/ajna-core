
// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { Maths }      from "../../libraries/Maths.sol";

import { NFTCollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { DSTestPlus } from "../utils/DSTestPlus.sol";

contract LoanQueueTest is DSTestPlus {

    address                     internal _sPoolAddress;
    ERC721Pool                  internal _sPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower;
    UserWithNFTCollateral       internal _borrower2;
    UserWithNFTCollateral       internal _borrower3;
    UserWithNFTCollateral       internal _borrower4;
    UserWithNFTCollateral       internal _borrower5;
    UserWithNFTCollateral       internal _borrower6;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    //TODO: write tests for NFT collection pool
    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _lender     = new UserWithQuoteTokenInNFTPool();
        _borrower   = new UserWithNFTCollateral();
        _borrower2   = new UserWithNFTCollateral();
        _borrower3   = new UserWithNFTCollateral();
        _borrower4   = new UserWithNFTCollateral();
        _borrower5   = new UserWithNFTCollateral();
        _borrower6   = new UserWithNFTCollateral();

        _collateral.mint(address(_borrower), 2);
        _collateral.mint(address(_borrower2), 1);
        _collateral.mint(address(_borrower3), 1);
        _collateral.mint(address(_borrower4), 1);
        _collateral.mint(address(_borrower5), 1);
        _collateral.mint(address(_borrower6), 1);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _quote.mint(address(_borrower), 100 * 1e18);
        _quote.mint(address(_borrower3), 100 * 1e18);

        // deploy NFT subset pool
        _tokenIds = new uint256[](7);
        _tokenIds[0] = 1;
        _tokenIds[1] = 2;
        _tokenIds[2] = 3;
        _tokenIds[3] = 4;
        _tokenIds[4] = 5;
        _tokenIds[5] = 6;
        _tokenIds[6] = 7;

        _sPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), _tokenIds, 0.05 * 10**18);
        _sPool        = ERC721Pool(_sPoolAddress);

        // run token approvals for NFT Subset Pool
        _lender.approveToken(_quote, address(_sPool), 200_000 * 1e18);
        _quote.approve(address(_borrower), 300_000 * 1e18);
        _quote.approve(address(_borrower3), 300_000 * 1e18);
        _quote.approve(address(_borrower4), 300_000 * 1e18);
        _quote.approve(address(_borrower5), 300_000 * 1e18);
        _quote.approve(address(_borrower6), 300_000 * 1e18);

        _borrower.approveToken(_collateral, address(_sPool), 1);
        _borrower.approveToken(_collateral, address(_sPool), 2);
        _borrower2.approveToken(_collateral, address(_sPool), 3);
        _borrower3.approveToken(_collateral, address(_sPool), 4);
        _borrower4.approveToken(_collateral, address(_sPool), 5);
        _borrower5.approveToken(_collateral, address(_sPool), 6);
        _borrower6.approveToken(_collateral, address(_sPool), 7);
    }

    function testAddLoanToQueue() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        // borrow and insert into the Queue
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
    }

    function testGetHighestThresholdPriceSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        assertEq(0, _sPool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 50_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, , uint[] memory collateral, , , , ) = _sPool.getBorrowerInfo(address(_borrower));

        (, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral.length), _sPool.getHighestThresholdPrice());
    }

    function testBorrowerSelfRefLoanQueueSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        assertEq(0, _sPool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, ,uint[] memory collateral, , , , ) = _sPool.getBorrowerInfo(address(_borrower));

        (, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(Maths.wdiv(debt, collateral.length), _sPool.getHighestThresholdPrice());

        // borrow and insert into the Queue
        vm.expectRevert("B:U:PNT_SELF_REF");
        _borrower.borrow(_sPool, 10_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r3);
    }


    function testMoveLoanToHeadInQueueSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        // borrower becomes head
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 thresholdPrice, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));

        // borrower2 replaces borrower as head
        _borrower2.addCollateral(_sPool, 3, address(0), address(0), _r3);
        _borrower2.borrow(_sPool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (thresholdPrice, next) = _sPool.loans(address(_borrower2));
        assertEq(address(next), address(_borrower));
        assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

        //borrower replaces borrower2 as head
        _borrower.borrow(_sPool, 10_000 * 1e18, 2_000 * 1e18, address(_borrower2), address(0), _r3);

        (thresholdPrice, next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(_borrower2));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
    }

    function testupdateLoanQueueRemoveCollateralSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.addCollateral(_sPool, 2, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, , uint[] memory collateral,,,,) = _sPool.getBorrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral.length));

        _borrower.removeCollateral(_sPool, 1, address(0), address(0), _r3);

        (debt, , collateral,,,,) = _sPool.getBorrowerInfo(address(_borrower));
        (thresholdPrice, next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral.length));
    }

    function testupdateLoanQueueAddCollateralSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p2807);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p12_66);

        // *borrower(HEAD)*
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

        (uint256 debt, , uint[] memory collateral,,,,) = _sPool.getBorrowerInfo(address(_borrower));
        (uint256 thresholdPrice, address next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral.length));

        _borrower.addCollateral(_sPool, 2, address(0), address(0), _r3);

        (debt, , collateral,,,,) = _sPool.getBorrowerInfo(address(_borrower));
        (thresholdPrice, next) = _sPool.loans(address(_borrower));
        assertEq(address(next), address(0));
        assertEq(address(_borrower), address(_sPool.loanQueueHead()));
        assertEq(thresholdPrice, Maths.wdiv(debt, collateral.length));
    }


    //// TODO: write test with radius of 0 
    //// TODO: write test with decimal radius
    //// TODO: write test with radius larger than queue
    function testRadiusInQueueSPool() public {
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p50159);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p49910);
        _lender.addQuoteToken(_sPool, 50_000 * 1e18, _p10016);

        // *borrower(HEAD)*
        _borrower.addCollateral(_sPool, 1, address(0), address(0), _r3);
        _borrower.borrow(_sPool, 15_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

       (uint256 thresholdPrice, address next) = _sPool.loans(address(_borrower));
       assertEq(address(next), address(0));
       assertEq(address(_borrower), address(_sPool.loanQueueHead()));

       // *borrower2(HEAD)* -> borrower
       _borrower2.addCollateral(_sPool, 3, address(0), address(0), _r3);
       _borrower2.borrow(_sPool, 20_000 * 1e18, 2_000 * 1e18, address(0), address(0), _r3);

       (thresholdPrice, next) = _sPool.loans(address(_borrower2));
       assertEq(address(next), address(_borrower));
       assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

       // borrower2(HEAD) -> borrower -> *borrower3*
       _borrower3.addCollateral(_sPool, 4, address(0), address(0), _r3);
       _borrower3.borrow(_sPool, 10_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r3);

        (thresholdPrice, next) = _sPool.loans(address(_borrower3));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> *borrower4*
        _borrower4.addCollateral(_sPool, 5, address(0), address(0), _r3);
        _borrower4.borrow(_sPool, 5_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower3), _r3);

        (thresholdPrice, next) = _sPool.loans(address(_borrower4));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

        // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> *borrower5*
        _borrower5.addCollateral(_sPool, 6, address(0), address(0), _r3);
        _borrower5.borrow(_sPool, 2_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower4), _r3);

        (thresholdPrice, next) = _sPool.loans(address(_borrower5));
        assertEq(address(next), address(0));
        assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

      //  // borrower2(HEAD) -> borrower -> borrower3 -> borrower4 -> borrower5 -> *borrower6*
      //  _borrower6.addCollateral(_sPool, 7, address(0), address(0), _r3);

      //  // newPrev passed in is incorrect & radius is too small, revert
      //  vm.expectRevert("B:S:SRCH_RDS_FAIL");
      //  _borrower6.borrow(_sPool, 1_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r1);

      //  // newPrev passed in is incorrect & radius supports correct placement
      //  _borrower6.borrow(_sPool, 1_000 * 1e18, 2_000 * 1e18, address(0), address(_borrower), _r2);

      //  (thresholdPrice, next) = _sPool.loans(address(_borrower6));
      //  assertEq(address(next), address(0));
      //  assertEq(address(_borrower2), address(_sPool.loanQueueHead()));

      //  (thresholdPrice, next) = _sPool.loans(address(_borrower4));
      //  assertEq(address(next), address(_borrower5));

      //  (thresholdPrice, next) = _sPool.loans(address(_borrower5));
      //  assertEq(address(next), address(_borrower6));

      //  (thresholdPrice, next) = _sPool.loans(address(_borrower));
      //  assertEq(address(next), address(_borrower3));

    }





}