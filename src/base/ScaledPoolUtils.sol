// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import './interfaces/IScaledPool.sol';

import '../libraries/PoolUtils.sol';

contract ScaledPoolUtils {

    /**
     *  @notice Returns info related to Claimaible Reserve Auction.
     *  @return reserves_                   The amount of excess quote tokens.
     *  @return claimableReserves_          Denominated in quote token, or 0 if no reserves can be auctioned.
     *  @return claimableReservesRemaining_ Amount of claimable reserves which has not yet been taken.
     *  @return auctionPrice_               Current price at which 1 quote token may be purchased, denominated in Ajna.
     *  @return timeRemaining_              Seconds remaining before takes are no longer allowed.
     */
    function poolReservesInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 reserves_,
            uint256 claimableReserves_,
            uint256 claimableReservesRemaining_,
            uint256 auctionPrice_,
            uint256 timeRemaining_
        )
    {
        IScaledPool pool = IScaledPool(ajnaPool_);
        uint256 poolDebt = pool.borrowerDebt();
        uint256 poolSize = pool.depositSize();

        uint256 quoteTokenBalance = ERC20(pool.quoteTokenAddress()).balanceOf(ajnaPool_);

        uint256 bondEscrowed     = pool.liquidationBondEscrowed();
        uint256 unclaimedReserve = pool.reserveAuctionUnclaimed();
        uint256 auctionKickTime  = pool.reserveAuctionKicked();

        reserves_ = poolDebt + quoteTokenBalance - poolSize - bondEscrowed - unclaimedReserve;
        claimableReserves_ = PoolUtils.claimableReserves(
            poolDebt,
            poolSize,
            bondEscrowed,
            unclaimedReserve,
            quoteTokenBalance
        );

        claimableReservesRemaining_ = unclaimedReserve;
        auctionPrice_               = PoolUtils.reserveAuctionPrice(auctionKickTime);
        timeRemaining_              = 3 days - Maths.min(3 days, block.timestamp - auctionKickTime);
    }

    function borrowerInfo(address ajnaPool_, address borrower_)
        external
        view
        returns (
            uint256 debt_,             // accrued debt (WAD)
            uint256 pendingDebt_,      // accrued debt (WAD)
            uint256 collateral_,       // deposited collateral including encumbered (WAD)
            uint256 mompFactor_,       // MOMP / inflator, used in neutralPrice calc (WAD)
            uint256 inflatorSnapshot_  // used to calculate pending interest (WAD)
        )
    {
        IScaledPool pool = IScaledPool(ajnaPool_);

        uint256 inflatorSnapshot           = pool.inflatorSnapshot();
        uint256 lastInflatorSnapshotUpdate = pool.lastInflatorSnapshotUpdate();
        uint256 interestRate               = pool.interestRate();

        (debt_, collateral_, mompFactor_, inflatorSnapshot_) = pool.borrowers(borrower_);
        uint256 pendingInflator = PoolUtils.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);
        pendingDebt_ = Maths.wmul(debt_, Maths.wdiv(pendingInflator, inflatorSnapshot));
    }

    /**
     *  @notice Returns info related to pool loans.
     *  @return poolSize_        The total amount of quote tokens in pool (WAD).
     *  @return loansCount_      The number of loans in pool.
     *  @return maxBorrower_     The address with the highest TP in pool.
     *  @return pendingInflator_ Pending inflator in pool
     */
    function poolLoansInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 poolSize_,
            uint256 loansCount_,
            address maxBorrower_,
            uint256 pendingInflator_
        )
    {
        IScaledPool pool = IScaledPool(ajnaPool_);
        poolSize_    = pool.depositSize();
        loansCount_  = pool.noOfLoans();
        maxBorrower_ = pool.maxBorrower();

        uint256 inflatorSnapshot           = pool.inflatorSnapshot();
        uint256 lastInflatorSnapshotUpdate = pool.lastInflatorSnapshotUpdate();
        uint256 interestRate               = pool.interestRate();

        pendingInflator_ = PoolUtils.pendingInflator(inflatorSnapshot, lastInflatorSnapshotUpdate, interestRate);
    }

    /**
     *  @notice Returns info related to pool prices.
     *  @return hpb_      The price value of the current Highest Price Bucket (HPB), in WAD units.
     *  @return hpbIndex_ The index of the current Highest Price Bucket (HPB), in WAD units.
     *  @return htp_      The price value of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return htpIndex_ The index of the current Highest Threshold Price (HTP) bucket, in WAD units.
     *  @return lup_      The price value of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     *  @return lupIndex_ The index of the current Lowest Utilized Price (LUP) bucket, in WAD units.
     */
    function poolPricesInfo(address ajnaPool_)
        external
        view
        returns (
            uint256 hpb_,
            uint256 hpbIndex_,
            uint256 htp_,
            uint256 htpIndex_,
            uint256 lup_,
            uint256 lupIndex_
        )
    {
        IScaledPool pool = IScaledPool(ajnaPool_);
        hpbIndex_ = pool.depositIndex(1);
        hpb_      = PoolUtils.indexToPrice(hpbIndex_);
        htp_      = Maths.wmul(pool.maxThresholdPrice(), pool.inflatorSnapshot());
        if (htp_ != 0) htpIndex_ = PoolUtils.priceToIndex(htp_);
        lupIndex_ = pool.depositIndex(pool.borrowerDebt());
        lup_      = PoolUtils.indexToPrice(lupIndex_);
    }

}
