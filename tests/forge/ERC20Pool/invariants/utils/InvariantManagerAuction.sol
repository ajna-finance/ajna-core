// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import "forge-std/console.sol";
import '@std/Test.sol';
import '@std/Vm.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';

uint256 constant LENDER_MIN_BUCKET_INDEX = 2570;
uint256 constant LENDER_MAX_BUCKET_INDEX = 2590;

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;

function constrictToRange(
    uint256 x,
    uint256 min,
    uint256 max
) pure returns (uint256 result) {
    require(max >= min, "MAX_LESS_THAN_MIN");

    uint256 size = max - min;

    if (size == 0) return min;            // Using max would be equivalent as well.
    if (max != type(uint256).max) size++; // Make the max inclusive.

    // Ensure max is inclusive in cases where x != 0 and max is at uint max.
    if (max == type(uint256).max && x != 0) x--; // Accounted for later.

    if (x < min) x += size * (((min - x) / size) + 1);

    result = min + ((x - min) % size);

    // Account for decrementing x to make max inclusive.
    if (max == type(uint256).max && x != 0) result++;
}


/**
 *  @dev this contract manages multiple lenders
 *  @dev methods in this contract are called in random order
 *  @dev randomly selects a lender contract to make a txn
 */ 
contract InvariantActorManagerAuction is Test{
    address   internal _pool;
    address   internal _quote;
    address   internal _collateral;
    address   internal _poolInfo;
    address   internal _actor;
    uint256   internal _bucketLender;
    uint256   internal _bucketBorrower;
    address[] public   _actors;

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) {
        _pool       = pool;
        _quote      = quote;
        _collateral = collateral;
        _poolInfo   = poolInfo;
        _actors     = _getActors(numOfActors);
    }

    // Returns a voters address array with N voters 
    function _getActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actors = new address[](noOfActors_);
        for(uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actors[i] = actor;

            vm.startPrank(actor);
            Token(_quote).mint(actor, 1e40);
            Token(_quote).approve(_pool, 1e40);
            Token(_collateral).mint(actor, 1e40);
            Token(_collateral).approve(_pool, 1e40);
            vm.stopPrank();
        }
        return actors;
}

    modifier useRandomActor(uint256 actorIndex) {
        address actor = _actors[constrictToRange(actorIndex, 0, _actors.length - 1)];
        _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier useRandomBucketLender(uint256 bucketIndex) {
        _bucketLender  = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
        _;
    }

    modifier useRandomBucketBorrower(uint256 bucketIndex) {
        _bucketBorrower  = constrictToRange(bucketIndex, BORROWER_MIN_BUCKET_INDEX, BORROWER_MAX_BUCKET_INDEX);
        _;
    }

    function _addQuoteToken(uint256 amount, uint256 bucket) internal {
        ERC20Pool(_pool).addQuoteToken(amount, bucket);
    }

    function addQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) external useRandomActor(actorIndex) useRandomBucketLender(bucketIndex) {
        console.log("M: Add");
        amount = constrictToRange(amount, 1, 1000000 * 1e18);
        _addQuoteToken(amount, _bucketLender);
    }

    function _removeQuoteToken(uint256 amount, uint256 bucket) internal {
        ERC20Pool(_pool).removeQuoteToken(amount, bucket);
    }

    function removeQuoteToken(uint256 actorIndex, uint256 amount, uint256 bucketIndex) external useRandomActor(actorIndex) useRandomBucketLender(bucketIndex){
        console.log("M: remove");
        (uint256 lpBalance, ) = ERC20Pool(_pool).lenderInfo(_bucketLender, _actor);

        if ( lpBalance > 0 ) {
            amount = constrictToRange(amount, 1, 1000000 * 1e18);
            _removeQuoteToken(amount, _bucketLender);
        }
    }

    function _drawDebt(uint256 amount, uint256 limitIndex) internal {

        amount = constrictToRange(amount, 1, 1000000 * 1e18);

        (uint256 minDebt, , , ) = PoolInfoUtils(_poolInfo).poolUtilizationInfo(_pool);

        if (amount < minDebt) amount = minDebt + 100 * 1e18;

        uint256 poolQuoteBalance = Token(_quote).balanceOf(_pool);
        if (amount > poolQuoteBalance) {
            _addQuoteToken(amount, LENDER_MAX_BUCKET_INDEX);
        }

        // pledge slightly more than required collateral to draw debt
        uint256 collateralToPledge = (amount * 1e18 / PoolInfoUtils(_poolInfo).hpb(_pool)) * 101 / 100;

        ERC20Pool(_pool).drawDebt(_actor, amount, limitIndex, collateralToPledge);

        // skip some time for more interest and make borrower under collateralized
        vm.warp(block.timestamp + 200 days);
    }

    function drawDebt(uint256 actorIndex, uint256 amount, uint256 limitIndex) external useRandomActor(actorIndex) useRandomBucketBorrower(limitIndex) {
        _drawDebt(amount, _bucketBorrower);
    }

    function repayDebt(uint256 actorIndex, uint256 amountToRepay, uint256 limitIndex) external useRandomActor(actorIndex) useRandomBucketBorrower(limitIndex){
        console.log("M: repay");
        (uint256 debt, , ) = ERC20Pool(_pool).borrowerInfo(_actor);
        if(debt == 0) {
            _drawDebt(amountToRepay, _bucketBorrower);
        }
        ERC20Pool(_pool).repayDebt(_actor, amountToRepay, 0);
    }

    function kickAuction(uint256 borrowerIndex, uint256 amount, uint256 kickerIndex) external useRandomBucketBorrower(BORROWER_MIN_BUCKET_INDEX) {
        console.log("M: kick");
        borrowerIndex = constrictToRange(borrowerIndex, 0, _actors.length - 1);
        kickerIndex   = constrictToRange(kickerIndex, 0, _actors.length - 1);

        address borrower = _actors[borrowerIndex];

        ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

        if (kickTime == 0) {
            (uint256 debt, , ) = ERC20Pool(_pool).borrowerInfo(borrower);
            if (debt == 0) {
                changePrank(borrower);
                _drawDebt(borrowerIndex, amount);
            }
            changePrank(_actors[kickerIndex]);
            ERC20Pool(_pool).kick(borrower);
        }

        // skip some time for more interest
        vm.warp(block.timestamp + 2 hours);
    }

    function takeAuction(uint256 borrowerIndex, uint256 amount, uint256 actorIndex) external useRandomActor(borrowerIndex){
        console.log("M: take");
        actorIndex = constrictToRange(actorIndex, 0, _actors.length - 1);

        address borrower = _actor;
        address taker    = _actors[actorIndex];

        ( , , , uint256 kickTime, , , , , ) = ERC20Pool(_pool).auctionInfo(borrower);

        if (kickTime != 0) {
            ERC20Pool(_pool).take(borrower, amount, taker, bytes(""));
        }
    }

    function getActorsCount() external view returns(uint256) {
        return _actors.length;
    }
}