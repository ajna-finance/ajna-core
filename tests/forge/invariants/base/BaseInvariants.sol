// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import '@std/Test.sol';

import { PoolInfoUtils }    from 'src/PoolInfoUtils.sol';
import { Pool }             from 'src/base/Pool.sol';

import { TokenWithNDecimals, BurnableToken }  from '../../utils/Tokens.sol';

abstract contract BaseInvariants is Test {

    uint256 internal LENDER_MIN_BUCKET_INDEX;
    uint256 internal LENDER_MAX_BUCKET_INDEX;

    TokenWithNDecimals internal _quote;

    BurnableToken internal _ajna;

    uint256 internal _numOfActors;

    Pool          internal _pool;
    PoolInfoUtils internal _poolInfo;

    // bucket exchange rate tracking
    mapping(uint256 => uint256) internal previousBucketExchangeRate;

    // inflator tracking
    uint256 previousInflator;
    uint256 previousInflatorUpdate;

    // interest rate tracking
    uint256 previousInterestRateUpdate;
    uint256 previousTotalInterestEarned;
    uint256 previousTotalInterestEarnedUpdate;

    // address of pool handler
    address internal _handler;

    uint256 public currentTimestamp;

    // use current timestamp for invariants
    modifier useCurrentTimestamp {
        vm.warp(currentTimestamp);

        _;
    }

    function setUp() public virtual {
        // Tokens
        _ajna  = new BurnableToken("Ajna", "A");
        _quote = new TokenWithNDecimals("Quote", "Q", uint8(vm.envOr("QUOTE_PRECISION", uint256(18))));

        _numOfActors = uint256(vm.envOr("NO_OF_ACTORS", uint256(10)));

        // Pool
        _poolInfo = new PoolInfoUtils();

        currentTimestamp = block.timestamp;
    }

    function setCurrentTimestamp(uint256 currentTimestamp_) external {
        currentTimestamp = currentTimestamp_;
    }
}