// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { DSTestPlus } from '../../utils/DSTestPlus.sol';
import { Token }      from '../../utils/Tokens.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { IERC20PoolEvents } from 'src/interfaces/pool/erc20/IERC20PoolEvents.sol';

import 'src/interfaces/pool/IPool.sol';
import 'src/interfaces/pool/IPoolFactory.sol';
import 'src/libraries/helpers/PoolHelper.sol';
import 'src/PoolInfoUtils.sol';

import 'src/libraries/internal/Maths.sol';

abstract contract ERC20DSTestPlus is DSTestPlus, IERC20PoolEvents {

    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;

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
        (uint256 poolInflator, uint256 lastInflatorUpdate) = _pool.inflatorInfo();

        uint256 elapsed = block.timestamp - lastInflatorUpdate;
        (uint256 interestRate, ) = _pool.interestRateInfo();
        uint256 factor = PoolCommons.pendingInterestFactor(interestRate, elapsed);

        uint256 currentPoolInflator = Maths.wmul(poolInflator, factor);

        // Calculate current debt of borrower, rounding up to token precision
        uint256 currentDebt = Maths.ceilWmul(currentPoolInflator, borrowerT0debt);
        uint256 tokenDebt   = _roundUpToScale(currentDebt, ERC20Pool(address(_pool)).quoteTokenScale());

        // mint quote tokens to borrower address equivalent to the current debt
        deal(_pool.quoteTokenAddress(), borrower, currentDebt);

        // repay current debt and pull all collateral if any
        if (tokenDebt != 0 || borrowerCollateral != 0) {
            _repayDebtNoLupCheck(borrower, borrower, tokenDebt, currentDebt, borrowerCollateral);
        }

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
        for (uint j = 0; j < indexes.length(); j++) {
            uint256 bucketIndex = indexes.at(j);
            (, uint256 bucketQuote, uint256 bucketCollateral, , ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);
            (uint256 lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);

            uint256 lpRedeemed;

            // redeem LP for quote token if available
            if (lenderLpBalance != 0 && bucketQuote != 0) {
                (, lpRedeemed) = _pool.removeQuoteToken(type(uint256).max, bucketIndex);
                lenderLpBalance -= lpRedeemed;
            }

            // redeem LP for collateral if available
            if (lenderLpBalance != 0 && bucketCollateral != 0) {
                (, lpRedeemed) = ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, bucketIndex);
                lenderLpBalance -= lpRedeemed;
            }

            // confirm the user actually has 0 LPB in the bucket
            (lenderLpBalance, ) = _pool.lenderInfo(bucketIndex, lender);
            assertEq(lenderLpBalance, 0);
        }
    }

    function validateCollateral(
        EnumerableSet.UintSet    storage buckets,
        EnumerableSet.AddressSet storage borrowers
    ) internal {
        uint256 bucketCollateral = 0;
        for (uint256 i = 0; i < buckets.length(); i++) {
            (, , uint256 collateral, , ,) = _poolUtils.bucketInfo(address(_pool), buckets.at(i));
            bucketCollateral += collateral;
        }

        uint256 pledgedCollateral = 0;
        for (uint i = 0; i < borrowers.length(); i++) {
            (, uint256 collateral,) = _poolUtils.borrowerInfo(address(_pool), borrowers.at(i));
            pledgedCollateral += collateral;
        }

        assertEq(_pool.pledgedCollateral(), pledgedCollateral);
        uint256 scale                         = ERC20Pool(address(_pool)).collateralScale();
        uint256 collateralBalanceDenormalized = IERC20(_pool.collateralAddress()).balanceOf(address(_pool));
        uint256 collateralBalanceNormalized   = collateralBalanceDenormalized * scale;
        assertEq(collateralBalanceNormalized, bucketCollateral + pledgedCollateral);
    }

    function redeemBankruptBucketCollateral(
        EnumerableSet.UintSet storage buckets,
        address lender
    ) internal {
        //  skip some time to pass bucket bankruptcy block
        skip(1 hours);

        for (uint256 i = 0; i < buckets.length(); i++) {
            uint256 bucketIndex = buckets.at(i);
            (, uint256 quoteTokens, uint256 collateral, uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);
            if (bucketLps == 0 && quoteTokens == 0 && collateral != 0) {
                changePrank(lender);

                // mint and approve collateral tokens
                deal(_pool.collateralAddress(), lender, 1 * 1e18);
                IERC20(_pool.collateralAddress()).approve(address(_pool), type(uint256).max);
                
                // add collateral to get some lps.
                ERC20Pool(address(_pool)).addCollateral(1 * 1e18, bucketIndex, block.timestamp + 10 minutes);

                // remove all collateral
                ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, bucketIndex);
            }
        }
    }

    function validateEmpty(
        EnumerableSet.UintSet storage buckets
    ) internal {
        for (uint256 i = 0; i < buckets.length(); i++) {
            uint256 bucketIndex = buckets.at(i);
            (, uint256 quoteTokens, uint256 collateral, uint256 bucketLps, ,) = _poolUtils.bucketInfo(address(_pool), bucketIndex);

            // Checking if all bucket lps are redeemed
            assertEq(bucketLps, 0);
            assertEq(quoteTokens, 0);
            assertEq(collateral, 0);
        }
        ( , uint256 loansCount, , , ) = _poolUtils.poolLoansInfo(address(_pool));
        (uint256 debt, , uint256 t0DebtInAuction ,) = _pool.debtInfo();
        assertEq(debt, 0);
        assertEq(t0DebtInAuction, 0);
        assertEq(loansCount, 0);
        assertEq(_pool.pledgedCollateral(), 0);
    }

    modifier tearDown {
        _;
        validateCollateral(bucketsUsed, borrowers);

        // Skip time to make all auctioned borrowers settleable
        skip(73 hours);

        // Settle any auctions and then repay debt
        for (uint i = 0; i < borrowers.length(); i++) {
            address borrower = borrowers.at(i);
            (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower);
            if (kickTime != 0) {
                changePrank(borrower);
                _pool.settle(borrower, bucketsUsed.length() + 1);

                // Settle again if not settled, this can happen when less reserves calculated with DEPOSIT_BUFFER and borrower is not fully settled
                (,,, kickTime,,,,,) = _pool.auctionInfo(borrower);
                if (kickTime != 0) {
                    _pool.settle(borrower, bucketsUsed.length() + 1);
                }
            }
            repayDebt(borrower);
        }

        // Lenders pull all liquidity and collateral from buckets
        for (uint i = 0; i < lenders.length(); i++) {
            redeemLendersLp(lenders.at(i), lendersDepositedIndex[lenders.at(i)]);
        }

        //  Redeem all collateral in bankrupt buckets
        if (lenders.length() != 0) redeemBankruptBucketCollateral(bucketsUsed, lenders.at(0));

        validateEmpty(bucketsUsed);
    }

    /*****************************/
    /*** Actor actions asserts ***/
    /*****************************/

    function _assertQuoteTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal override {
        vm.expectEmit(true, true, false, true);

        uint256 transferAmount = Maths.ceilDiv(amount, _pool.quoteTokenScale());
        emit Transfer(from, to, transferAmount);
    }

    function _assertQuoteTokenTransferEventDrawDebt(
        address from,
        address to,
        uint256 amount
    ) internal {
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, to, amount / _pool.quoteTokenScale());
    }

    function _assertCollateralTokenTransferEvent(
        address from,
        address to,
        uint256 amount
    ) internal override {
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, to, amount / ERC20Pool(address(_pool)).collateralScale());
    }

    function _addCollateral(
        address from,
        uint256 amount,
        uint256 index,
        uint256 lpAward
    ) internal returns (uint256) {
        uint256 collateralScale = ERC20Pool(address(_pool)).collateralScale();
        uint256 roundedAmount   = (amount / collateralScale) * collateralScale;
        changePrank(from);

        vm.expectEmit(true, true, false, true);
        emit AddCollateral(from, index, roundedAmount, lpAward);
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), roundedAmount / collateralScale);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index); 

        return ERC20Pool(address(_pool)).addCollateral(amount, index, type(uint256).max);
    }

    function _addCollateralWithoutCheckingLP(
        address from,
        uint256 amount,
        uint256 index
    ) internal returns (uint256) {
        uint256 collateralScale = ERC20Pool(address(_pool)).collateralScale();
        uint256 roundedAmount   = (amount / collateralScale) * collateralScale;
        changePrank(from);

        // CAUTION: this does not actually check topics 1 and 2 as it should
        vm.expectEmit(true, true, false, false);
        emit AddCollateral(from, index, roundedAmount, 0);
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), roundedAmount / collateralScale);

        // Add for tearDown
        lenders.add(from);
        lendersDepositedIndex[from].add(index);
        bucketsUsed.add(index);

        return ERC20Pool(address(_pool)).addCollateral(amount, index, type(uint256).max);
    }

    function _borrow(
        address from,
        uint256 amount,
        uint256 indexLimit,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit DrawDebt(from, amount, 0, newLup);
        _assertQuoteTokenTransferEvent(address(_pool), from, amount);

        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);

        // Add for tearDown
        borrowers.add(from);
    }

    function _drawDebt(
        address from,
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256 collateralToPledge,
        uint256 newLup
    ) internal {
        uint256 collateralScale = ERC20Pool(address(_pool)).collateralScale();
        changePrank(from);

        if (newLup != 0) {
            vm.expectEmit(true, true, false, true);
            emit DrawDebt(from, amountToBorrow, (collateralToPledge / collateralScale) * collateralScale, newLup);
        }

        // pledge collateral
        if (collateralToPledge != 0) {
            vm.expectEmit(true, true, false, true);
            emit Transfer(from, address(_pool), collateralToPledge / collateralScale);
        }

        // borrow quote
        if (amountToBorrow != 0) {
            _assertQuoteTokenTransferEventDrawDebt(address(_pool), from, amountToBorrow);
        }

        ERC20Pool(address(_pool)).drawDebt(borrower, amountToBorrow, limitIndex, collateralToPledge);

        // add for tearDown
        borrowers.add(borrower);
    }

    // Used when lup can't be known in advance
    function _drawDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToBorrow,
        uint256 limitIndex,
        uint256 collateralToPledge
    ) internal {
        _drawDebt(from, borrower, amountToBorrow, limitIndex, collateralToPledge, 0);
    }

    function _pledgeCollateral(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit DrawDebt(borrower, 0, amount, _poolUtils.lup(address(_pool)));
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), amount / ERC20Pool(address(_pool)).collateralScale());

        // call out to drawDebt w/ amountToBorrow == 0
        ERC20Pool(address(_pool)).drawDebt(borrower, 0, 0, amount);

        // add for tearDown
        borrowers.add(borrower);
    }

    function _pledgeCollateralAndSettleAuction(
        address from,
        address borrower,
        uint256 amount,
        uint256 collateral
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AuctionSettle(borrower, collateral);
        vm.expectEmit(true, true, false, true);
        emit DrawDebt(borrower, 0, amount, _poolUtils.lup(address(_pool)));
        vm.expectEmit(true, true, false, true);
        emit Transfer(from, address(_pool), amount / ERC20Pool(address(_pool)).collateralScale());

        // call out to drawDebt w/ amountToBorrow == 0
        ERC20Pool(address(_pool)).drawDebt(borrower, 0, 0, amount);

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
        emit RemoveCollateral(from, index, amount, lpRedeem);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(_pool), from, amount);
        (uint256 collateralRemoved, uint256 lpAmount) = ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, index);
        assertEq(collateralRemoved, amount);
        assertEq(lpAmount, lpRedeem);
    }

    function _repayAndSettleAuction(
        address from,
        address borrower,
        uint256 amount,
        uint256 repaid,
        uint256 collateral,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit AuctionSettle(borrower, collateral);
        vm.expectEmit(true, true, false, true);
        emit RepayDebt(borrower, repaid, 0, newLup);
        _assertQuoteTokenTransferEvent(from, address(_pool), repaid);
        ERC20Pool(address(_pool)).repayDebt(borrower, amount, 0, borrower, MAX_FENWICK_INDEX);
    }

    function _repayDebt(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull,
        uint256 newLup
    ) internal {
        changePrank(from);

        if (newLup != 0) {
            vm.expectEmit(true, true, false, true);
            emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
        }

        // repay checks
        if (amountToRepay != 0) {
            _assertQuoteTokenTransferEvent(from, address(_pool), amountRepaid);
        }

        // pull checks
        if (collateralToPull != 0) {
            _assertCollateralTokenTransferEvent(address(_pool), from, collateralToPull);
        }

        ERC20Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull, borrower, MAX_FENWICK_INDEX);
    }

    function _repayDebtAndPullToRecipient(
        address from,
        address borrower,
        address recipient,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull,
        uint256 newLup
    ) internal {
        changePrank(from);
        vm.expectEmit(true, true, false, true);
        emit RepayDebt(borrower, amountRepaid, collateralToPull, newLup);
        _assertCollateralTokenTransferEvent(address(_pool), recipient, collateralToPull);
        ERC20Pool(address(_pool)).repayDebt(borrower, amountToRepay, collateralToPull, recipient, MAX_FENWICK_INDEX);
    }

    function _repayDebtNoLupCheck(
        address from,
        address borrower,
        uint256 amountToRepay,
        uint256 amountRepaid,
        uint256 collateralToPull
    ) internal {
        _repayDebt(from, borrower, amountToRepay, amountRepaid, collateralToPull, 0);
    }

    function _transferLP(
        address operator,
        address from,
        address to,
        uint256 lpBalance,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectEmit(true, true, true, true);
        emit TransferLP(from, to, indexes, lpBalance);
        _pool.transferLP(from, to, indexes);

        for (uint256 i = 0; i < indexes.length ;i++ ){
            if (lenders.contains(from)){
                lenders.add(to);
                lendersDepositedIndex[to].add(indexes[i]);
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
        ERC20Pool(address(_pool)).addCollateral(amount, index, type(uint256).max);
    }

    function _assertAddCollateralAtIndex0Revert(
        address from,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        ERC20Pool(address(_pool)).addCollateral(amount, 0, type(uint256).max);
    }

    function _assertAddCollateralDustRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        ERC20Pool(address(_pool)).addCollateral(amount, index, type(uint256).max);
    }

    function _assertAddCollateralExpiredRevert(
        address from,
        uint256 amount,
        uint256 index,
        uint256 expiry
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.TransactionExpired.selector);
        ERC20Pool(address(_pool)).addCollateral(amount, index, expiry);
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

    function _assertTokenDecimalsNotCompliant(
        address poolFactory,
        address collateral,
        address quote,
        uint256 interestRate
    ) internal {
        vm.expectRevert(IPoolFactory.DecimalsNotCompliant.selector);
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
        address deployed = ERC20PoolFactory(poolFactory).deployedPools(
            keccak256("ERC20_NON_SUBSET_HASH"),
            collateral,
            quote
        );
        vm.expectRevert(
            abi.encodeWithSelector(bytes4(keccak256("PoolAlreadyExists(address)")),
            deployed)
        );
        ERC20PoolFactory(poolFactory).deployPool(collateral, quote, interestRate);
    }

    function _assertPullInsufficientCollateralRevert(
        address from,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientCollateral.selector);
        ERC20Pool(address(_pool)).repayDebt(from, 0, amount, from, MAX_FENWICK_INDEX);
    }

    function _assertPullLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        ERC20Pool(address(_pool)).repayDebt(from, 0, amount, from, indexLimit);
    }

    function _assertRepayLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        ERC20Pool(address(_pool)).repayDebt(from, amount, 0, from, indexLimit);
    }

    function _assertRepayNoDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoDebt.selector);
        ERC20Pool(address(_pool)).repayDebt(borrower, amount, 0, borrower, MAX_FENWICK_INDEX);
    }

    function _assertPullBorrowerNotSenderRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerNotSender.selector);
        ERC20Pool(address(_pool)).repayDebt(borrower, 0, amount, borrower, MAX_FENWICK_INDEX);
    }

    function _assertRepayAuctionActiveRevert(
        address from,
        uint256 maxAmount
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AuctionActive.selector);
        ERC20Pool(address(_pool)).repayDebt(from, maxAmount, 0, from, MAX_FENWICK_INDEX);
    }

    function _assertRepayMinDebtRevert(
        address from,
        address borrower,
        uint256 amount
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        ERC20Pool(address(_pool)).repayDebt(borrower, amount, 0, borrower, MAX_FENWICK_INDEX);
    }

    function _assertRemoveAllCollateralNoClaimRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.NoClaim.selector);
        ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, index);
    }

    function _assertRemoveAllCollateralAuctionNotClearedRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, index);
    }

    function _assertRemoveCollateralDustRevert(
        address from,
        uint256 amount,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.DustAmountNotExceeded.selector);
        ERC20Pool(address(_pool)).removeCollateral(amount, index);
    }

    function _assertRemoveAllCollateralInsufficientLPRevert(
        address from,
        uint256 index
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InsufficientLP.selector);
        ERC20Pool(address(_pool)).removeCollateral(type(uint256).max, index);
    }

    function _assertTransferInvalidIndexRevert(
        address operator,
        address from,
        address to,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.InvalidIndex.selector);
        _pool.transferLP(from, to, indexes);
    }

    function _assertTransferNoAllowanceRevert(
        address operator,
        address from,
        address to,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.NoAllowance.selector);
        _pool.transferLP(from, to, indexes);
    }

    function _assertTransferToSameOwnerRevert(
        address operator,
        address from,
        address to,
        uint256[] memory indexes
    ) internal {
        changePrank(operator);
        vm.expectRevert(IPoolErrors.TransferToSameOwner.selector);
        _pool.transferLP(from, to, indexes);
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

    function _assertBorrowAuctionActiveRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AuctionActive.selector);
        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);
    }

    function _assertBorrowBorrowerNotSenderRevert(
        address from,
        address borrower,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerNotSender.selector);
        ERC20Pool(address(_pool)).drawDebt(borrower, amount, indexLimit, 0);
    }

    function _assertBorrowLimitIndexRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LimitIndexExceeded.selector);
        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);
    }

    function _assertBorrowBorrowerUnderCollateralizedRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.BorrowerUnderCollateralized.selector);
        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);
    }

    function _assertBorrowInvalidAmountRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.InvalidAmount.selector);
        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);
    }

    function _assertBorrowMinDebtRevert(
        address from,
        uint256 amount,
        uint256 indexLimit
    ) internal override {
        changePrank(from);
        vm.expectRevert(IPoolErrors.AmountLTMinDebt.selector);
        ERC20Pool(address(_pool)).drawDebt(from, amount, indexLimit, 0);
    }

    function _assertLupBelowHTPRevert(
        address from,
        uint256 amount,
        uint256 fromIndex,
        uint256 toIndex
    ) internal {
        changePrank(from);
        vm.expectRevert(IPoolErrors.LUPBelowHTP.selector);
        ERC20Pool(address(_pool)).moveQuoteToken(amount, fromIndex, toIndex, type(uint256).max, false);
    }

}

abstract contract ERC20HelperContract is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    uint  internal _anonBorrowerCount = 0;
    Token internal _collateral;
    Token internal _quote;

    ERC20PoolFactory internal _poolFactory;

    constructor() {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        _collateral  = new Token("Collateral", "C");
        _quote       = new Token("Quote", "Q");
        _poolFactory = new ERC20PoolFactory(_ajna);
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils   = new PoolInfoUtils();
        _startTime   = block.timestamp;
    }

    /**
     *  @dev Creates debt for an anonymous non-player borrower not otherwise involved in the test.
     **/
    function _anonBorrowerDrawsDebt(uint256 collateralAmount, uint256 loanAmount, uint256 limitIndex) internal {
        _anonBorrowerCount += 1;
        address borrower = makeAddr(string(abi.encodePacked("anonBorrower", _anonBorrowerCount)));
        _mintCollateralAndApproveTokens(borrower,  collateralAmount);
        _drawDebtNoLupCheck(
            {
                from:               borrower,
                borrower:           borrower,
                amountToBorrow:     loanAmount,
                limitIndex:         limitIndex,
                collateralToPledge: collateralAmount
            }
        );
    }

    function _mintQuoteAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        changePrank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        _collateral.approve(address(_pool), type(uint256).max);
    }

    function _mintCollateralAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_collateral), operator_, mintAmount_);

        changePrank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_pool), type(uint256).max);
    }

}

abstract contract ERC20FuzzyHelperContract is ERC20DSTestPlus {

    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    uint  internal _anonBorrowerCount = 0;
    Token internal _collateral;
    Token internal _quote;

    ERC20PoolFactory internal _poolFactory;

    constructor() {
        _collateral  = new Token("Collateral", "C");
        _quote       = new Token("Quote", "Q");
        _poolFactory = new ERC20PoolFactory(_ajna);
        _pool        = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(_quote), 0.05 * 10**18));
        _poolUtils   = new PoolInfoUtils();
        _startTime   = block.timestamp;
    }

    function _mintQuoteAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_quote), operator_, mintAmount_);

        changePrank(operator_);
        _quote.approve(address(_pool), type(uint256).max);
        _collateral.approve(address(_pool), type(uint256).max);
    }

    function _mintCollateralAndApproveTokens(address operator_, uint256 mintAmount_) internal {
        deal(address(_collateral), operator_, mintAmount_);

        changePrank(operator_);
        _collateral.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_pool), type(uint256).max);
    }
}
