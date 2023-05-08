// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import { Maths }                        from 'src/libraries/internal/Maths.sol';
import { PositionManager }              from 'src/PositionManager.sol';
import { RewardsManager }               from 'src/RewardsManager.sol';
import { IPositionManagerOwnerActions } from 'src/interfaces/position/IPositionManagerOwnerActions.sol';
import { _priceAt, _isCollateralized, _borrowFeeRate }  from 'src/libraries/helpers/PoolHelper.sol';

import { BasePositionsHandler }    from './unbounded/BasePositionsHandler.sol';
import { UnboundedRewardsHandler } from './unbounded/UnboundedRewardsHandler.sol';

import { BaseHandler }    from '../../base/handlers/unbounded/BaseHandler.sol';
import { ReservePoolHandler } from '../../base/handlers/ReservePoolHandler.sol';
import { PositionsHandler } from './PositionsHandler.sol';


contract RewardsHandler is UnboundedRewardsHandler, ReservePoolHandler, PositionsHandler {

    constructor(
        address rewards_,
        address positions_,
        address pool_,
        address ajna_,
        address quote_,
        address collateral_,
        address poolInfo_,
        uint256 numOfActors_,
        address testContract_
    ) PositionsHandler(positions_, pool_, ajna_, quote_, collateral_, poolInfo_, numOfActors_, testContract_) {

        // Rewards manager
        _rewards = RewardsManager(rewards_);

    }

    /*******************************/
    /*** Rewards Test Functions ***/
    /*******************************/

    function stake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.stake']++;
        // Pre action
        uint256 tokenId = _preStake(bucketIndex_, amountToAdd_);
        
        // Action phase
        _stake(tokenId);
    }

    function unstake(
        uint256 actorIndex_,
        uint256 bucketIndex_,
        uint256 amountToAdd_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BRewardsHandler.unstake']++;
        // Pre action
        uint256 tokenId = _preUnstake(bucketIndex_, amountToAdd_);
        
        // Action phase
        _unstake(tokenId);


        // Post action
        // check token was transferred from rewards contract to actor
        assertEq(_positions.ownerOf(tokenId), _actor);
    }


    /*******************************/
    /*** Rewards Tests Functions ***/
    /*******************************/

    function _preStake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256) {

        (uint256 tokenId, uint256[] memory indexes) = _preMemorializePositions(bucketIndex_, amountToAdd_);
        
        _memorializePositions(tokenId, indexes);
        
        return tokenId;
    }

    function _preUnstake(
        uint256 bucketIndex_,
        uint256 amountToAdd_
    ) internal returns (uint256 tokenId_) {

        // Only way to check if the actor has a NFT position or a staked position is tracking events
        // Create a staked position
        tokenId_ = _preStake(bucketIndex_, amountToAdd_);
        _stake(tokenId_);

        //TODO: Perform multiple randomized reserve auctions to ensure staked position has rewards over multiple epochs 
        // trigger reserve auction
        _kickReserveAuction(); 

        uint256 boundedAmount = _preTakeReserves(amountToAdd_);
        _takeReserves(boundedAmount);
    }

    /*******************************/
    /***   Overriden Functions   ***/
    /*******************************/

    function _constrictTakeAmount(uint256 amountToTake_) internal view override returns(uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToTake_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
    }

    function drawDebt(
        uint256 actorIndex_,
        uint256 amountToBorrow_,
        uint256 skippedTime_
    ) external useRandomActor(actorIndex_) useTimestamps skipTime(skippedTime_) {
        numberOfCalls['BBasicHandler.drawDebt']++;

        // Prepare test phase
        uint256 boundedAmount = _preDrawDebt(amountToBorrow_);
        
        // Action phase
        _drawDebt(boundedAmount);

        // Cleanup phase
        _auctionSettleStateReset(_actor);
    }

    function _preDrawDebt(
        uint256 amountToBorrow_
    ) internal override returns (uint256 boundedAmount_) {
        boundedAmount_ = constrictToRange(amountToBorrow_, MIN_QUOTE_AMOUNT, MAX_QUOTE_AMOUNT);

        // Pre Condition
        // 1. borrower's debt should exceed minDebt
        // 2. pool needs sufficent quote token to draw debt
        // 3. drawDebt should not make borrower under collateralized

        // 1. borrower's debt should exceed minDebt
        (uint256 debt, uint256 collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);
        (uint256 minDebt, , , ) = _poolInfo.poolUtilizationInfo(address(_pool));

        if (boundedAmount_ < minDebt) boundedAmount_ = minDebt + 1;

        // 2. pool needs sufficent quote token to draw debt
        uint256 poolQuoteBalance = _quote.balanceOf(address(_pool));

        if (boundedAmount_ > poolQuoteBalance) {
            _addQuoteToken(boundedAmount_ * 2, LENDER_MAX_BUCKET_INDEX);
        }

        // 3. check if drawing of addition debt will make borrower undercollateralized
        // recalculate lup with new amount to be borrowed and check borrower collateralization at new lup
        (uint256 currentPoolDebt, , , ) = _pool.debtInfo();
        uint256 nextPoolDebt = currentPoolDebt + boundedAmount_;
        uint256 newLup = _priceAt(_pool.depositIndex(nextPoolDebt));
        (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

        // repay debt if borrower becomes undercollateralized with new debt at new lup
        if (!_isCollateralized(debt + boundedAmount_, collateral, newLup, _pool.poolType())) {
            _repayDebt(debt);

            (debt, collateral, ) = _poolInfo.borrowerInfo(address(_pool), _actor);

            require(debt == 0, "borrower has debt");
        }
    }

    function _drawDebt(
        uint256 amount_
    ) internal virtual override updateLocalStateAndPoolInterest {
        numberOfCalls['UBBasicHandler.drawDebt']++;

        (uint256 poolDebt, , , ) = _pool.debtInfo();

        // find bucket to borrow quote token
        uint256 bucket = _pool.depositIndex(amount_ + poolDebt) - 1;
        uint256 price = _poolInfo.indexToPrice(bucket);
        uint256 collateralToPledge = ((amount_ * 1e18 + price / 2) / price) * 101 / 100 + 1;

        try _erc20Pool.drawDebt(_actor, amount_, 7388, collateralToPledge) {

            (uint256 interestRate, ) = _pool.interestRateInfo();

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

        try _erc20Pool.repayDebt(_actor, amountToRepay_, 0, _actor, 7388) {

        } catch (bytes memory err) {
            _ensurePoolError(err);
        }
    }
}
