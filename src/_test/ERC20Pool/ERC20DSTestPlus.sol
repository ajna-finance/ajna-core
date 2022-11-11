// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { DSTestPlus } from '../utils/DSTestPlus.sol';
import { Token }      from '../utils/Tokens.sol';

import { ERC20Pool }        from '../../erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from '../../erc20/ERC20PoolFactory.sol';

import '../../base/interfaces/IPool.sol';
import '../../base/interfaces/IPoolFactory.sol';
import '../../base/PoolInfoUtils.sol';

import '../../libraries/Maths.sol';

abstract contract ERC20DSTestPlus is DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

    mapping(address => EnumerableSet.UintSet) bidderDepositedIndex;
    EnumerableSet.AddressSet bidders;

    // Pool events
    event AddCollateral(address indexed actor_, uint256 indexed price_, uint256 amount_);
    event PledgeCollateral(address indexed borrower_, uint256 amount_);

    event Transfer(address indexed from, address indexed to, uint256 value);

    /*****************/
    /*** Utilities ***/
    /*****************/

    function repayDebt(
        address borrower
    ) internal {
        changePrank(borrower);
        uint256 borrowerT0debt;
        uint256 borrowerCollateral;
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);

        // calculate current pool Inflator
        (uint256 poolInflatorSnapshot, uint256 lastInflatorSnapshotUpdate) = _pool.inflatorInfo();

        uint256 elapsed = block.timestamp - lastInflatorSnapshotUpdate;
        uint256 factor = PoolUtils.pendingInterestFactor(_pool.interestRate(), elapsed);

        uint256 currentPoolInflator = Maths.wmul(poolInflatorSnapshot, factor);

        // Calculate current debt of borrower
        uint256 currentDebt = Maths.wmul(currentPoolInflator, borrowerT0debt);

        // mint quote tokens to borrower address equivalent to the current debt
        deal(_pool.quoteTokenAddress(), borrower, currentDebt);

        // repay current debt ( all debt )
        if (currentDebt > 0) {
            _pool.repay(borrower, currentDebt);
        }

        // pull borrower's all collateral  
        _pullCollateral(borrower, borrowerCollateral);

        // check borrower state after repay of loan and pull collateral
        (borrowerT0debt, borrowerCollateral, ) = _pool.borrowerInfo(borrower);
        assertEq(borrowerT0debt,     0);
        assertEq(borrowerCollateral, 0);
    }

    function redeemLendersLp(
        address lender,
        EnumerableSet.UintSet storage indexes
    ) internal {
        changePrank(lender);

        // Redeem all lps of lender from all buckets as quote token and collateral token
        for(uint j = 0; j < indexes.length(); j++ ){
            uint256 bucketIndex = indexes.at(j);
            (, uint256 bucketQuote, uint256 bucketCollateral, , ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);
            (uint256 lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);

            // redeem LP for quote token if available
            uint256 lpRedeemed;
            if(lenderLpBalance != 0 && bucketQuote != 0) {
                (, lpRedeemed) = _pool.removeQuoteToken(type(uint256).max, bucketIndex);
                lenderLpBalance -= lpRedeemed;
            }

            // redeem LP for collateral if available
            if(lenderLpBalance != 0 && bucketCollateral != 0) {
                (, lpRedeemed) = ERC20Pool(address(_pool)).removeAllCollateral(bucketIndex);
                lenderLpBalance -= lpRedeemed;
            }

            // confirm the redemption amount returned by removal methods is correct
            assertEq(lenderLpBalance, 0);
            // confirm the user actually has 0 LPB in the bucket
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
            assertEq(lenderLpBalance, 0);
        }
    }

    function validateEmpty(
        EnumerableSet.UintSet storage buckets
    ) internal {
        for(uint256 i = 0; i < buckets.length(); i++){
            uint256 bucketIndex = buckets.at(i);
            (, uint256 quoteTokens, uint256 collateral, uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // Checking if all bucket lps are redeemed
            assertEq(bucketLps, 0);
            assertEq(quoteTokens, 0);
            assertEq(collateral, 0);
        }
        ( , uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        (uint256 debt, , ) = _pool.debtInfo();
        assertEq(debt, 0);
        assertEq(loansCount, 0);
        assertEq(_pool.pledgedCollateral(), 0);
    }

    modifier tearDown {
        _;
        for(uint i = 0; i < borrowers.length(); i++ ){
            repayDebt(borrowers.at(i));
        }
        
        for(uint i = 0; i < lenders.length(); i++ ){
            redeemLendersLp(lenders.at(i), lendersDepositedIndex[lenders.at(i)]);
        }

        for(uint i = 0; i < bidders.length(); i++ ){
            redeemLendersLp(bidders.at(i), bidderDepositedIndex[bidders.at(i)]);
        }
        validateEmpty(bucketsUsed);
    }
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

        // Add for tearDown
        bidders.add(from);
        bidderDepositedIndex[from].add(index);
        bucketsUsed.add(index); 

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

        bidderDepositedIndex[from].add(toIndex);
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

        borrowers.add(borrower);
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

        for(uint256 i = 0; i < indexes.length ;i++ ){
            if(lenders.contains(from)){
                lenders.add(to);
                lendersDepositedIndex[to].add(indexes[i]);
            }
            else{
                bidders.add(to);
                bidderDepositedIndex[to].add(indexes[i]);
            }
        }
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

    function _assertDepositLockedByAuctionDebtRevert(
        address operator,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.RemoveDepositLockedByAuctionDebt.selector);
        _pool.removeQuoteToken(amount, index);
    }

}

abstract contract ERC20HelperContract is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;

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
        borrowers.add(borrower);
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