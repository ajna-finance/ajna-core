// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';

import 'src/ERC20Pool.sol';
import { _priceAt } from 'src/libraries/helpers/PoolHelper.sol';

import { TokenWithNDecimals } from '../../../utils/Tokens.sol';

import { BaseERC20PoolHandler }            from './unbounded/BaseERC20PoolHandler.sol';
import { UnboundedBasicERC20PoolHandler }  from './unbounded/UnboundedBasicERC20PoolHandler.sol';
import { UnboundedLiquidationPoolHandler } from '../../base/handlers/unbounded/UnboundedLiquidationPoolHandler.sol';

contract TradingERC20PoolHandler is UnboundedLiquidationPoolHandler, UnboundedBasicERC20PoolHandler {
    using EnumerableSet for EnumerableSet.UintSet;

    address[] internal _lenders;
    address[] internal _traders;

    uint16 internal constant LENDERS = 500;
    uint16 internal constant TRADERS = 500;
    uint16 nonce;
    uint256 numberOfBuckets;

    EnumerableSet.UintSet internal _activeBorrowers;

    constructor(
        address pool_,
        address ajna_,
        address poolInfo_,
        address testContract_
    ) BaseERC20PoolHandler(pool_, ajna_, poolInfo_, 0, testContract_) {
        numberOfBuckets = buckets.length();
        setUp();
    }

    function setUp() internal useTimestamps {
        vm.startPrank(address(this));

        _setupQuoteDeposits(LENDERS);
        _setupCollateralDeposits(TRADERS);
    }

    modifier writeSwapLogs() {
        if (numberOfCalls["Write logs"]++ == 0) vm.writeFile(path, "");
        string memory data = string(abi.encodePacked("================= Handler Call : ", Strings.toString(numberOfCalls["Write logs"]), " =================="));
        printInNextLine(data);
        printLog("Time                      = ", block.timestamp);
        printLog("Quote pool Balance        = ", _quote.balanceOf(address(_pool)));
        printLog("Collateral pool Balance   = ", _collateral.balanceOf(address(_pool)));
        _;
    }

    /************************/
    /*** Trader Functions ***/
    /************************/

    function swapQuoteForCollateral(
        uint256 traderIndex_,
        uint256 tradeAmount_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeSwapLogs {
        tradeAmount_ = constrictToRange(tradeAmount_, Maths.max(_pool.quoteTokenScale(), MIN_QUOTE_AMOUNT), MAX_QUOTE_AMOUNT);
        traderIndex_ = constrictToRange(traderIndex_, 0, _lenders.length - 1);

        _actor = _lenders[traderIndex_];

        changePrank(_actor);

        uint256 rateBeforeSwap        = _pool.bucketExchangeRate(_lenderBucketIndex);
        (uint256 lpBeforeSwap, , , ,) = _pool.bucketInfo(_lenderBucketIndex);

        _addQuoteToken(tradeAmount_, _lenderBucketIndex);
        _removeCollateral(type(uint256).max, _lenderBucketIndex);

        (uint256 lpAfterSwap, , , ,)  = _pool.bucketInfo(_lenderBucketIndex);

        printLine(
            string(
                abi.encodePacked("Collateral Trader         = ", Strings.toHexString(uint160(_actor), 20), "")
            )
        );
        printLog("Trading price             = ", _priceAt(_lenderBucketIndex));
        printLog("Bucket LP before          = ", lpBeforeSwap);
        printLog("Bucket LP after           = ", lpAfterSwap);

        require (rateBeforeSwap == _pool.bucketExchangeRate(_lenderBucketIndex), "R1-R8: Exchange Rate Invariant");
    }

    function swapCollateralForQuote(
        uint256 traderIndex_,
        uint256 tradeAmount_,
        uint256 bucketIndex_,
        uint256 skippedTime_
    ) external useRandomLenderBucket(bucketIndex_) useTimestamps skipTime(skippedTime_) writeSwapLogs {
        tradeAmount_ = constrictToRange(tradeAmount_, MIN_COLLATERAL_AMOUNT, MAX_COLLATERAL_AMOUNT);
        traderIndex_ = constrictToRange(traderIndex_, 0, _traders.length - 1);

        _actor = _traders[traderIndex_];

        changePrank(_actor);

        uint256 rateBeforeSwap        = _pool.bucketExchangeRate(_lenderBucketIndex);
        (uint256 lpBeforeSwap, , , ,) = _pool.bucketInfo(_lenderBucketIndex);

        _addCollateral(tradeAmount_, _lenderBucketIndex);
        _removeQuoteToken(type(uint256).max, _lenderBucketIndex);

        (uint256 lpAfterSwap, , , ,)  = _pool.bucketInfo(_lenderBucketIndex);

        printLine(
            string(
                abi.encodePacked("Quote Trader              = ", Strings.toHexString(uint160(_actor), 20), "")
            )
        );
        printLog("Trading price             = ", _priceAt(_lenderBucketIndex));
        printLog("Bucket LP before          = ", lpBeforeSwap);
        printLog("Bucket LP after           = ", lpAfterSwap);

        require (rateBeforeSwap == _pool.bucketExchangeRate(_lenderBucketIndex), "R1-R8: Exchange Rate Invariant");
    }

    function _setupQuoteDeposits(uint256 count_) internal virtual {
        uint256[] memory buckets = buckets.values();
        for (uint256 i; i < count_;) {
            address lender = address(uint160(uint256(keccak256(abi.encodePacked(i, 'lender')))));

            _actor = lender;
            changePrank(_actor);
            _addQuoteToken(100_000 * 1e18, buckets[_randomBucket()]);

            actors.push(lender);
            _lenders.push(lender);

            unchecked { ++i; }
        }
    }

    function _setupCollateralDeposits(uint256 count_) internal virtual {
        uint256[] memory buckets = buckets.values();
        for (uint256 i; i < count_;) {
            address trader = address(uint160(uint256(keccak256(abi.encodePacked(i, 'trader')))));

            _actor = trader;
            changePrank(_actor);
            _addQuoteToken(100_000 * 1e18, buckets[_randomBucket()]);

            actors.push(trader);
            _traders.push(trader);

            unchecked { ++i; }
        }
    }

    function _randomBucket() internal returns (uint256 randomBucket_) {
        randomBucket_ = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))
        ) % numberOfBuckets;
        ++ nonce;
    }

    function _randomDebt() internal returns (uint256 randomDebt_) {
        randomDebt_ = uint256(
            keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))
        ) % 900 + 100;
        ++ nonce;
    }

    function _resetSettledAuction(address borrower_, uint256 borrowerIndex_) internal {
        (,,, uint256 kickTime,,,,,) = _pool.auctionInfo(borrower_);
        if (kickTime == 0) {
            if (borrowerIndex_ != 0) _activeBorrowers.remove(borrowerIndex_);
        }
    }

}