
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@std/Test.sol';
import '@std/Vm.sol';
import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { InvariantTest } from '../InvariantTest.sol';


uint256 constant LENDER_MIN_BUCKET_INDEX = 2570;
uint256 constant LENDER_MAX_BUCKET_INDEX = 2590;

uint256 constant BORROWER_MIN_BUCKET_INDEX = 2600;
uint256 constant BORROWER_MAX_BUCKET_INDEX = 2620;

contract BaseHandler is InvariantTest, Test {

    // Tokens
    Token         internal _quote;
    Token         internal _collateral;

    // Pool
    ERC20Pool     internal _pool;
    PoolInfoUtils internal _poolInfo;

    // Modifiers
    address       internal _actor;
    uint256       internal _lenderBucketIndex;
    uint256       internal _limitIndex;
    address[]     public   actors;

    // Logging
    mapping(bytes32 => uint256) public numberOfCalls;

    // Lender tracking
    mapping(address => uint256[]) public touchedBuckets;

    // bucket exchange rate invariant check
    bool public shouldExchangeRateChange;

    bool public shouldReserveChange;

    // if take is called on auction first time
    bool public firstTake;

    // mapping borrower address to first take on auction
    mapping(address => bool) internal isFirstTakeOnAuction;

    // amount of reserve increase after first take
    uint256 public firstTakeIncreaseInReserve;

    // amount of reserve increase after kicking a loan
    uint256 public loanKickIncreaseInReserve;
    
    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) {
        // Tokens
        _quote      = Token(quote);
        _collateral = Token(collateral);

        // Pool
        _pool       = ERC20Pool(pool);
        _poolInfo   = PoolInfoUtils(poolInfo);

        // Actors
        actors    = _buildActors(numOfActors);
    }

    /**************************************************************************************************************************************/
    /*** Helper Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    modifier useRandomActor(uint256 actorIndex) {
        // pre condition
        firstTakeIncreaseInReserve = 0;
        loanKickIncreaseInReserve = 0;

        vm.stopPrank();

        address actor = actors[constrictToRange(actorIndex, 0, actors.length - 1)];
        _actor = actor;
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier useRandomLenderBucket(uint256 bucketIndex) {
        uint256[] storage lenderBucketIndexes = touchedBuckets[_actor];
        if (lenderBucketIndexes.length < 3) {
            // if actor has touched less than three buckets, add a new bucket
            _lenderBucketIndex = constrictToRange(bucketIndex, LENDER_MIN_BUCKET_INDEX, LENDER_MAX_BUCKET_INDEX);
            lenderBucketIndexes.push(_lenderBucketIndex);
        } else {
            // if actor has touched more than three buckets, reuse one of the touched buckets
            _lenderBucketIndex = lenderBucketIndexes[constrictToRange(bucketIndex, 0, lenderBucketIndexes.length - 1)];
        }
        _;
    }
 
    function _buildActors(uint256 noOfActors_) internal returns(address[] memory) {
        address[] memory actorsAddress = new address[](noOfActors_);
        for(uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actorsAddress[i] = actor;

            vm.startPrank(actor);

            _quote.mint(actor, 1e45);
            _quote.approve(address(_pool), 1e45);

            _collateral.mint(actor, 1e45);
            _collateral.approve(address(_pool), 1e45);

            vm.stopPrank();
        }
        return actorsAddress;
    }

    function getActorsCount() external view returns(uint256) {
        return actors.length;
    }

    function constrictToRange(
        uint256 x,
        uint256 min,
        uint256 max
    ) pure public returns (uint256 result) {
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

}