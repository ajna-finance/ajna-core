// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { DSTestPlus }                                         from "../utils/DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }                     from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

import { Maths } from "../../libraries/Maths.sol";

contract ERC721PoolBorrowTest is DSTestPlus {

    address                     internal _NFTCollectionPoolAddress;
    address                     internal _NFTSubsetPoolAddress;
    ERC721Pool                  internal _NFTCollectionPool;
    ERC721Pool                  internal _NFTSubsetPool;
    NFTCollateralToken          internal _collateral;
    QuoteToken                  internal _quote;
    UserWithNFTCollateral       internal _borrower2;
    UserWithNFTCollateral       internal _borrower;
    UserWithQuoteTokenInNFTPool internal _lender;
    uint256[]                   internal _tokenIds;

    function setUp() external {
        _collateral  = new NFTCollateralToken();
        _quote       = new QuoteToken();

        _lender     = new UserWithQuoteTokenInNFTPool();
        _borrower2  = new UserWithNFTCollateral();
        _borrower   = new UserWithNFTCollateral();

        _quote.mint(address(_lender), 200_000 * 1e18);
        _collateral.mint(address(_borrower), 60);
        _collateral.mint(address(_borrower2), 5);

        _NFTCollectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _NFTCollectionPool        = ERC721Pool(_NFTCollectionPoolAddress);

        _tokenIds = new uint256[](4);

        _tokenIds[0] = 1;
        _tokenIds[1] = 5;
        _tokenIds[2] = 50;
        _tokenIds[3] = 61;

        _NFTSubsetPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), _tokenIds, 0.05 * 10**18);
        _NFTSubsetPool        = ERC721Pool(_NFTSubsetPoolAddress);

        // run token approvals for NFT Collection Pool
        _lender.approveToken(_quote, _NFTCollectionPoolAddress, 200_000 * 1e18);
        _borrower.approveToken(_collateral, _NFTCollectionPoolAddress, 1);

        // run token approvals for NFT Subset Pool
        _lender.approveToken(_quote, _NFTSubsetPoolAddress, 200_000 * 1e18);

        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 1);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 5);
        _borrower.approveToken(_collateral, _NFTSubsetPoolAddress, 50);

        _borrower2.approveToken(_collateral, _NFTSubsetPoolAddress, 61);

        // _collateral.setApprovalForAll(_NFTSubsetPoolAddress, true);
    }

    /**
     *  @notice With 1 lender and 1 borrower tests addQuoteToken (subsequently reallocation), addCollateral and borrow.
     *          Borrower reverts:
     *              attempts to borrow more than available quote.
     *              attempts to borrow more than their collateral supports.
     *              attempts to borrow but stop price is exceeded.
     */
    function testBorrowNFTSubset() external {
        // add initial quote tokens to pool
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p4000);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p3010);
        _lender.addQuoteToken(_NFTSubsetPool, address(_lender), 10_000 * 1e18, _p2503);

        // check iniital pool balance
        assertEq(_NFTSubsetPool.totalQuoteToken(),                30_000 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                      0);
        assertEq(_NFTSubsetPool.hpb(),                            _p4000);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),         0);
        assertEq(_NFTSubsetPool.getPendingBucketInterest(_p4000), 0);

        // add iniitial collateral to pool
        vm.prank((address(_borrower)));
        uint[] memory tokens = new uint[](1);
        tokens[0] = 1;
        _NFTSubsetPool.addCollateral(tokens);
        vm.prank((address(_borrower)));
        tokens = new uint[](1);
        tokens[0] = 5;
        _NFTSubsetPool.addCollateral(tokens);
        vm.prank((address(_borrower)));
        tokens = new uint[](1);
        tokens[0] = 50;
        _NFTSubsetPool.addCollateral(tokens);
        assertEq(_NFTSubsetPool.getCollateralDeposited().length, 3);

        // should revert if borrower wants to borrow a greater amount than in pool
        vm.expectRevert("P:B:INSUF_LIQ");
        _borrower.borrow(_NFTSubsetPool, 60_000 * 1e18, _p4000);

        // should revert if limit price exceeded
        vm.expectRevert("B:B:PRICE_LT_LIMIT");
        _borrower.borrow(_NFTSubsetPool, 15_000 * 1e18, _p4000);

        // should revert if insufficient collateral deposited by borrower
        vm.expectRevert("P:B:INSUF_COLLAT");
        _borrower.borrow(_NFTSubsetPool, 15_000 * 1e18, _p3010);

        // borrow from pool
        uint256 borrowAmount = 6_000 * 1e18;
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, borrowAmount);
        _borrower.borrow(_NFTSubsetPool, borrowAmount, _p2503);

        // check bucket balances
        (, , , uint256 deposit, uint256 debt, , , ) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 4_000 * 1e18);
        assertEq(debt,    6_000.000961538461538462 * 1e18);

        // check borrower balance
        (uint256 borrowerDebt,, uint256[] memory collateralDeposited, uint256 collateralEncumbered,,,) = _NFTSubsetPool.getBorrowerInfo(address(_borrower));
        assertEq(borrowerDebt,               6_000.000961538461538462 * 1e18);
        assertEq(collateralDeposited.length, _NFTSubsetPool.getCollateralDeposited().length);
        assertEq(collateralDeposited[0],     1);
        assertEq(collateralDeposited[1],     5);
        assertEq(collateralDeposited[2],     50);
        assertEq(collateralEncumbered,       1.499652441522541316374014587 * 1e27);

        // check pool balances
        assertEq(_NFTSubsetPool.totalQuoteToken(),          24_000 * 1e18);
        assertEq(_NFTSubsetPool.totalDebt(),                6_000.000961538461538462 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(), 2.000463518703181412 * 1e18);
        assertEq(
            _NFTSubsetPool.getEncumberedCollateral(_NFTSubsetPool.totalDebt()),
            _NFTSubsetPool.getEncumberedCollateral(borrowerDebt)
        );
        assertEq(_quote.balanceOf(address(_borrower)),    borrowAmount);
        assertEq(_quote.balanceOf(_NFTSubsetPoolAddress), 24_000 * 1e18);
        assertEq(_NFTSubsetPool.hpb(),                    _p4000);
        assertEq(_NFTSubsetPool.lup(),                    _p4000);

        skip(8200);

        // TODO: execute other fx to accumulatePoolInterest
        // TODO: check pending debt post skip
        // TODO: check borrower debt has increased following the passage of time
        // (uint256 borrowerDebtAfterTime,,,,,,) = _NFTSubsetPool.getBorrowerInfo(address(_borrower));
        // assertGt(borrowerDebtAfterTime, borrowerDebt);

        // Attempt, but fail to borrow from pool if it would result in undercollateralization
        vm.prank((address(_borrower)));
        vm.expectRevert("P:B:INSUF_COLLAT");
        _borrower.borrow(_NFTSubsetPool, 5_000 * 1e18, _p3010);

        // add additional collateral
        // TODO: RAISES THE QUESTION -> How to deal with a pool where the universe of possible collateral has been exhausted

        // borrow remaining amount from LUP, and more, forcing reallocation
        vm.expectEmit(true, true, false, true);
        emit Transfer(_NFTSubsetPoolAddress, address(_borrower), 4_000 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit Borrow(address(_borrower), _p4000, 4_000 * 1e18);
        vm.prank((address(_borrower)));
        _borrower.borrow(_NFTSubsetPool, 4_000 * 1e18, _p3010);

        // check pool state
        assertEq(_NFTSubsetPool.hpb(),                            _p4000);
        assertEq(_NFTSubsetPool.lup(),                            _p4000);
        assertEq(_NFTSubsetPool.totalDebt(),                      10_000.079929684723703272 * 1e18);
        assertEq(_NFTSubsetPool.totalQuoteToken(),                20_000 * 1e18);
        assertEq(_NFTSubsetPool.totalCollateral(),                3 * 1e18);
        assertEq(_NFTSubsetPool.pdAccumulator(),                  55_144_110.464925767261400000 * 1e18);
        assertEq(_NFTSubsetPool.getPoolCollateralization(),       1.200268709864213944 * 1e18);
        assertEq(_NFTSubsetPool.getPoolActualUtilization(),       0.420473335425101563 * 1e18);
        assertEq(_NFTSubsetPool.getPendingPoolInterest(),         0);
        assertEq(_NFTSubsetPool.getPendingBucketInterest(_p4000), 0);

        // check bucket state
        (, , , deposit, debt, , , ) = _NFTSubsetPool.bucketAt(_p4000);
        assertEq(deposit, 0);
        assertEq(debt,    10_000.079929684723703272 * 1e18);
    }

    /**
     *  @notice With 1 lender and 2 borrowers tests addQuoteToken,
     *          addCollateral and borrow on an undercollateralized pool.
     *          Borrower2 reverts: attempts to borrow when pool is undercollateralized.
     */
    function testBorrowNFTCollectionTwoBorrowers() external {}

}
