// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import './DSTestPlus.sol';

import {
    AuctionsState,
    Borrower,
    Bucket,
    DepositsState,
    LoansState,
    PoolState,
    ReserveAuctionState
}                         from 'src/interfaces/pool/commons/IPoolState.sol';
import { SettleParams }   from 'src/interfaces/pool/commons/IPoolInternals.sol';
import { PoolType }       from 'src/interfaces/pool/IPool.sol';

import { Buckets }        from 'src/libraries/internal/Buckets.sol';
import { Deposits }       from 'src/libraries/internal/Deposits.sol';
import { Loans }          from 'src/libraries/internal/Loans.sol';
import { Maths }          from 'src/libraries/internal/Maths.sol';

import { KickerActions }  from 'src/libraries/external/KickerActions.sol';
import { SettlerActions } from 'src/libraries/external/SettlerActions.sol';

import { _indexOf }       from 'src/libraries/helpers/PoolHelper.sol';

contract AuctionQueueInstance is DSTestPlus {
    AuctionsState              private _auctions;
    mapping(uint256 => Bucket) private _buckets;
    DepositsState              private _deposits;
    LoansState                 private _loans;
    PoolState                  private _poolState;
    ReserveAuctionState        private _reserveAuction;

    uint256 private constant LOAN_SIZE =   100 * 1e18;
    uint256 private constant TP        =     5 * 1e18;
    uint256 private constant LUP       =     4 * 1e18;
    uint256 private constant LUP_INDEX = 3_878;
    address private          _lender;

    constructor() {
        Loans.init(_loans);
        _poolState.inflator        = 1 * 1e18;
        // _poolState.rate            = 0.05 * 1e18;
        _poolState.poolType        = uint8(PoolType.ERC20);
        _poolState.quoteTokenScale = 18;
        _lender                    = makeAddr("lender");
        skip(1);
    }

    function add(address loan) external {
        _mockDraw(loan);
        KickerActions.kick(
            _auctions,
            _deposits,
            _loans,
            _poolState,
            loan,
            7_388
        );
    }

    function remove(address loan) external {
        _mockSettle(loan);
        SettlerActions.settlePoolDebt(
            _auctions,
            _buckets,
            _deposits,
            _loans,
            _reserveAuction,
            _poolState,
            SettleParams({
                borrower:    loan,
                poolBalance: type(uint256).max,
                bucketDepth: 1
            })
        );
    }

    function count() external view returns (uint256 count_) {
        return _auctions.noOfAuctions;
    }

    function _mockDraw(address loan) internal {
        // add debt and collateral to PoolState
        uint256 pledge        =  Maths.wdiv(LOAN_SIZE, TP);
        _poolState.debt       += LOAN_SIZE;
        _poolState.collateral += pledge;

        // create Deposits with single Bucket at LUP
        Deposits.unscaledAdd(_deposits, LUP_INDEX, LOAN_SIZE);
        Bucket storage bucket =  _buckets[LUP_INDEX];
        bucket.lps            += LOAN_SIZE;
        Buckets.addLenderLP(bucket, 0, _lender, LOAN_SIZE);

        // add Borrower to Loans
        Borrower memory borrower;
        borrower.t0Debt = LOAN_SIZE;
        borrower.collateral = pledge;
        borrower.npTpRatio = 1 * 1e18;
        Loans.update(_loans, borrower, loan, _poolState.rate, false, false);
    }

    function _mockSettle(address loan) internal {
        // remove debt and collateral from PoolState
        uint256 pull = Maths.wdiv(LOAN_SIZE, TP);
        _poolState.debt       -= LOAN_SIZE;
        _poolState.collateral -= pull;

        // remove Borrower from Loans
        Borrower memory borrower;
        borrower.t0Debt     = 0;
        borrower.collateral = 0;
        Loans.update(_loans, borrower, loan, _poolState.rate, false, false);

        // remove liquidity from LUP
        Deposits.unscaledRemove(_deposits, LUP_INDEX, LOAN_SIZE);
        Bucket storage bucket =  _buckets[LUP_INDEX];
        bucket.lps            -= LOAN_SIZE;
    }
}
