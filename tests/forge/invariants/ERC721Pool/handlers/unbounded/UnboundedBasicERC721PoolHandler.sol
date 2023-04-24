// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { ERC20Pool }                         from 'src/ERC20Pool.sol';
import { ERC20PoolFactory }                  from 'src/ERC20PoolFactory.sol';
import { PoolInfoUtils }                     from 'src/PoolInfoUtils.sol';
import { 
    _borrowFeeRate,
    _depositFeeRate,
    _indexOf,
    MIN_PRICE,
    MAX_PRICE 
}                                            from 'src/libraries/helpers/PoolHelper.sol';
import { Maths }                             from "src/libraries/internal/Maths.sol";

import { UnboundedBasicPoolHandler } from "../../../base/handlers/unbounded/UnboundedBasicPoolHandler.sol";
import { BaseERC721PoolHandler }     from './BaseERC721PoolHandler.sol';

/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
abstract contract UnboundedBasicERC721PoolHandler is UnboundedBasicPoolHandler, BaseERC721PoolHandler {

    using EnumerableSet for EnumerableSet.UintSet;
    
    /*******************************/
    /*** Lender Helper Functions ***/
    /*******************************/

    function _addCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.addCollateral']++;

        (uint256 lpBalanceBeforeAction, ) = _erc721Pool.lenderInfo(bucketIndex_, _actor);

        _collateral.mint(_actor, amount_);
        _collateral.setApprovalForAll(address(_pool), true);
        uint256[] memory tokenIds = new uint256[](amount_);
        for (uint256 i = 0; i < amount_; i++) {
            tokenIds[i] = _collateral.tokenOfOwnerByIndex(_actor, i);
        }

        try _erc721Pool.addCollateral(tokenIds, bucketIndex_, block.timestamp + 1 minutes) {
            // **B5**: when adding collateral: lender deposit time = timestamp of block when deposit happened
            lenderDepositTime[_actor][bucketIndex_] = block.timestamp;
            // **R5**: Exchange rates are unchanged by adding collateral token into a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _erc721Pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction > lpBalanceBeforeAction, "LP balance should increase");
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _removeCollateral(
        uint256 amount_,
        uint256 bucketIndex_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.removeCollateral']++;

        (uint256 lpBalanceBeforeAction, ) = _erc721Pool.lenderInfo(bucketIndex_, _actor);

        try _erc721Pool.removeCollateral(amount_, bucketIndex_) {

            // **R6**: Exchange rates are unchanged by removing collateral token from a bucket
            exchangeRateShouldNotChange[bucketIndex_] = true;

            // Post action condition
            (uint256 lpBalanceAfterAction, ) = _erc721Pool.lenderInfo(bucketIndex_, _actor);
            require(lpBalanceAfterAction < lpBalanceBeforeAction, "LP balance should decrease");

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    /*********************************/
    /*** Borrower Helper Functions ***/
    /*********************************/

    function _pledgeCollateral(
        uint256 amount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.pledgeCollateral']++;

        (uint256 kickTimeBefore, , , , uint256 auctionPrice, ) =_poolInfo.auctionStatus(address(_erc721Pool), _actor);

        // **R1**: Exchange rates are unchanged by pledging collateral
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            exchangeRateShouldNotChange[bucketIndex] = true;
        }

        _collateral.mint(_actor, amount_);
        _collateral.setApprovalForAll(address(_pool), true);
        uint256[] memory tokenIds = new uint256[](amount_);
        for (uint256 i = 0; i < amount_; i++) {
            tokenIds[i] = _collateral.tokenOfOwnerByIndex(_actor, i);
        }

        try _erc721Pool.drawDebt(_actor, 0, 0, tokenIds) {
            (uint256 kickTimeAfter, , , , , ) =_poolInfo.auctionStatus(address(_erc721Pool), _actor);

            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            if (kickTimeBefore != 0 && kickTimeAfter == 0) {
                if (auctionPrice < MIN_PRICE) {
                    collateralBuckets.add(7388);
                } else if (auctionPrice > MAX_PRICE) {
                    collateralBuckets.add(0);
                } else {
                    collateralBuckets.add(_indexOf(auctionPrice));
                }
            }
        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _pullCollateral(
        uint256 amount_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.pullCollateral']++;

        // **R2**: Exchange rates are unchanged by pulling collateral
        for (uint256 bucketIndex = LENDER_MIN_BUCKET_INDEX; bucketIndex <= LENDER_MAX_BUCKET_INDEX; bucketIndex++) {
            exchangeRateShouldNotChange[bucketIndex] = true;
        }

        try _erc721Pool.repayDebt(_actor, 0, amount_, _actor, 7388) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
 
    function _drawDebt(
        uint256 amount_
    ) internal virtual override updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        (uint256 poolDebt, , , ) = _erc721Pool.debtInfo();

        // find bucket to borrow quote token
        uint256 bucket = _erc721Pool.depositIndex(amount_ + poolDebt) - 1;
        uint256 price = _poolInfo.indexToPrice(bucket);

        // Pool doesn't have enough deposits to draw debt
        if (bucket > LENDER_MAX_BUCKET_INDEX) return;

        // calculates collateral required to borrow <amount_> quote tokens, added 1 for roundup such that 0.8 NFT will become 1
        uint256 collateralToPledge = Maths.wdiv(amount_, price) / 1e18 + 1;

        _collateral.mint(_actor, collateralToPledge);
        _collateral.setApprovalForAll(address(_pool), true);
        uint256[] memory tokenIds = new uint256[](collateralToPledge);
        for (uint256 i = 0; i < collateralToPledge; i++) {
            tokenIds[i] = _collateral.tokenOfOwnerByIndex(_actor, i);
        }

        try _erc721Pool.drawDebt(_actor, amount_, 7388, tokenIds) {

            (uint256 interestRate, ) = _erc721Pool.interestRateInfo();

            // **RE10**: Reserves increase by origination fee: max(1 week interest, 0.05% of borrow amount), on draw debt
            increaseInReserves += Maths.wmul(
                amount_, _borrowFeeRate(interestRate)
            );

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }

    function _repayDebt(
        uint256 amountToRepay_
    ) internal updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.repayDebt']++;

        (uint256 kickTimeBefore, , , , uint256 auctionPrice, ) =_poolInfo.auctionStatus(address(_erc721Pool), _actor);

        try _erc721Pool.repayDebt(_actor, amountToRepay_, 0, _actor, 7388) {
            (uint256 kickTimeAfter, , , , , ) =_poolInfo.auctionStatus(address(_erc721Pool), _actor);

            // **CT2**: Keep track of bucketIndex when borrower is removed from auction to check collateral added into that bucket
            if (kickTimeBefore != 0 && kickTimeAfter == 0) {
                if (auctionPrice < MIN_PRICE) {
                    collateralBuckets.add(7388);
                } else if (auctionPrice > MAX_PRICE) {
                    collateralBuckets.add(0);
                } else {
                    collateralBuckets.add(_indexOf(auctionPrice));
                }
            }

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
