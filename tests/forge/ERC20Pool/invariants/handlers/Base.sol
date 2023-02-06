
// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import '@std/Test.sol';
import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';
import { Token }            from '../../../utils/Tokens.sol';
import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { PoolCommons }     from 'src/libraries/external/PoolCommons.sol';
import { InvariantTest } from '../InvariantTest.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { _ptp } from 'src/libraries/helpers/PoolHelper.sol';

import 'src/libraries/internal/Maths.sol';

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
    address[]     public   _actors;

    // Logging
    mapping(bytes32 => uint256) public numberOfCalls;

    // Lender tracking
    mapping(address => uint256[]) public touchedBuckets;

    // Ghost variables
    uint256[7389] internal fenwickDeposits;

    constructor(address pool, address quote, address collateral, address poolInfo, uint256 numOfActors) {
        // Tokens
        _quote      = Token(quote);
        _collateral = Token(collateral);

        // Pool
        _pool       = ERC20Pool(pool);
        _poolInfo   = PoolInfoUtils(poolInfo);

        // Actors
        _actors    = _buildActors(numOfActors);

    }

    /**************************************************************************************************************************************/
    /*** Helper Functions                                                                                                               ***/
    /**************************************************************************************************************************************/

    modifier useRandomActor(uint256 actorIndex) {
        vm.stopPrank();

        address actor = _actors[constrictToRange(actorIndex, 0, _actors.length - 1)];
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
        address[] memory actors = new address[](noOfActors_);
        for(uint i = 0; i < noOfActors_; i++) {
            address actor = makeAddr(string(abi.encodePacked("Actor", Strings.toString(i))));
            actors[i] = actor;

            vm.startPrank(actor);

            _quote.mint(actor, 1e40);
            _quote.approve(address(_pool), 1e40);

            _collateral.mint(actor, 1e40);
            _collateral.approve(address(_pool), 1e40);

            vm.stopPrank();
        }
        return actors;
    }

    function getActorsCount() external view returns(uint256) {
        return _actors.length;
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

    function fenwickAdd(uint256 amount, uint256 bucketIndex) internal { 
        uint256 deposit = fenwickDeposits[bucketIndex];
        fenwickDeposits[bucketIndex] = deposit + amount;
    }

    function fenwickRemove(uint256 removedAmount, uint256 bucketIndex) internal {

        // add early withdrawal penalty back to removedAmount if removeQT is occurs above the PTP
        // as that is the value removed from the fenwick tree
        (, uint256 depositTime) = _pool.lenderInfo(bucketIndex, _actor);
        uint256 price = _poolInfo.indexToPrice(bucketIndex);
        (, uint256 poolDebt ,) = _pool.debtInfo();
        uint256 poolCollateral  = _pool.pledgedCollateral();

        if (depositTime != 0 && block.timestamp - depositTime < 1 days) {
            if (price > _ptp(poolDebt, poolCollateral)) {
                removedAmount = Maths.wdiv(removedAmount, Maths.WAD - _poolInfo.feeRate(address(_pool)));
            }
        }

        // Fenwick
        uint256 deposit = fenwickDeposits[bucketIndex];
        fenwickDeposits[bucketIndex] = deposit - removedAmount;
    }

    function fenwickSumAtIndex(uint256 index) public view returns (uint256) {
        uint256 sum = 0;
        while (index > 0) {
                sum += fenwickDeposits[index];
            index--;
        }
        return sum;
    }

    function fenwickTreeSum() public view returns (uint256) {
        return fenwickSumAtIndex(fenwickDeposits.length - 1);    
    }

    function fenwickMult(uint256 index, uint256 scale) internal returns (uint256) {
        uint256 sum = 0;
        while (index > 0) {
            fenwickDeposits[index] = Maths.wmul(fenwickDeposits[index], scale);
            index--;
        }
        return sum;
    }

    function fenwickAccrueInterest() internal {

        (,,,,uint256 pendingFactor) = _poolInfo.poolLoansInfo(address(_pool));

        // poolLoansInfo returns 1e18 if no interest is pending or time elapsed... the contracts calculate 0 time elapsed which causes discrep
        if (pendingFactor == 1e18) return;

        // get TP of worst loan, pendingInflator and poolDebt
        uint256 maxThresholdPrice;
        uint256 pendingInflator;
        uint256 poolDebt;
        {
            (, maxThresholdPrice,) =  _pool.loansInfo();
            (, poolDebt ,) = _pool.debtInfo();
            (uint256 inflator, uint256 inflatorUpdate) = _pool.inflatorInfo();
            (uint256 interestRate, ) = _pool.interestRateInfo();
            pendingInflator = PoolCommons.pendingInflator(
                inflator,
                inflatorUpdate,
                interestRate
            );
        }

        // get HTP and deposit above HTP
        uint256 htp = Maths.wmul(maxThresholdPrice, pendingInflator);
        uint256 htpIndex = htp == 0 ? 0 : _poolInfo.priceToIndex(htp);
        uint256 depositAboveHtp = fenwickSumAtIndex(htpIndex);

        if (depositAboveHtp != 0) {

            uint256 poolCollateral  = _pool.pledgedCollateral();
            uint256 utilization = _pool.depositUtilization(poolDebt, poolCollateral);
            uint256 lenderInterestMargin_ = PoolCommons.lenderInterestMargin(utilization);

            uint256 newInterest_ = Maths.wmul(
                lenderInterestMargin_,
                Maths.wmul(pendingFactor - Maths.WAD, poolDebt)
            );

            uint256 scale = Maths.wdiv(newInterest_, depositAboveHtp) + Maths.WAD;

            // simulate scale being applied to all deposits above HTP
            fenwickMult(htpIndex, scale);
        } 
    }
}


