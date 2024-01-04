// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import { Multicall } from '@openzeppelin/contracts/utils/Multicall.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import { PoolInfoUtils } from "./PoolInfoUtils.sol";

import { IPool } from "./interfaces/pool/IPool.sol";
import { IERC20Pool } from "./interfaces/pool/erc20/IERC20Pool.sol";

contract PoolInfoUtilsMulticall {

    PoolInfoUtils public immutable poolInfoUtils;

    struct PoolLoansInfo {
        uint256 poolSize;
        uint256 loansCount;
        address maxBorrower;
        uint256 pendingInflator;
        uint256 pendingInterestFactor;
    }

    struct PoolPriceInfo {
        uint256 hpb;
        uint256 hpbIndex;
        uint256 htp;
        uint256 htpIndex;
        uint256 lup;
        uint256 lupIndex;
    }

    struct PoolRatesAndFees {
        uint256 lenderInterestMargin;
        uint256 borrowFeeRate;
        uint256 depositFeeRate;
    }

    struct PoolReservesInfo {
        uint256 reserves;
        uint256 claimableReserves;
        uint256 claimableReservesRemaining;
        uint256 auctionPrice;
        uint256 timeRemaining;
    }

    struct PoolUtilizationInfo {
        uint256 poolMinDebtAmount;
        uint256 poolCollateralization;
        uint256 poolActualUtilization;
        uint256 poolTargetUtilization;
    }

    struct PoolBalanceDetails {
        uint256 debt;                   // debtInfo()
        uint256 accruedDebt;            // debtInfo()
        uint256 debtInAuction;          // debtInfo()
        uint256 t0Debt2ToCollateral;    // debtInfo()
        uint256 depositUpToIndex;
        uint256 quoteTokenBalance;
        uint256 collateralTokenBalance;
    }

    constructor(PoolInfoUtils poolInfoUtils_) {
        poolInfoUtils = poolInfoUtils_;
    }

    /**
     *  @notice Retrieves PoolLoansInfo, PoolPriceInfo, PoolRatesAndFees, PoolReservesInfo and PoolUtilizationInfo
     *  @dev    This function is used to retrieve pool details available from PoolInfoUtils in a single RPC call for Indexers.
     *  @param  ajnaPool_    Address of `Ajna` pool
     *  @return poolLoansInfo_       Pool loans info struct
     *  @return poolPriceInfo_       Pool price info struct
     *  @return poolRatesAndFees_    Pool rates and fees struct
     *  @return poolReservesInfo_    Pool reserves info struct
     *  @return poolUtilizationInfo_ Pool utilization info struct
     */
    function poolDetailsMulticall(address ajnaPool_) external view returns (
        PoolLoansInfo memory poolLoansInfo_,
        PoolPriceInfo memory poolPriceInfo_,
        PoolRatesAndFees memory poolRatesAndFees_,
        PoolReservesInfo memory poolReservesInfo_,
        PoolUtilizationInfo memory poolUtilizationInfo_
    ) {
        // retrieve loans info
        (
            poolLoansInfo_.poolSize,
            poolLoansInfo_.loansCount,
            poolLoansInfo_.maxBorrower,
            poolLoansInfo_.pendingInflator,
            poolLoansInfo_.pendingInterestFactor
        ) = poolInfoUtils.poolLoansInfo(ajnaPool_);

        // retrieve prices info
        (
            poolPriceInfo_.hpb,
            poolPriceInfo_.hpbIndex,
            poolPriceInfo_.htp,
            poolPriceInfo_.htpIndex,
            poolPriceInfo_.lup,
            poolPriceInfo_.lupIndex
        ) = poolInfoUtils.poolPricesInfo(ajnaPool_);

        // retrieve rates and fees
        poolRatesAndFees_.lenderInterestMargin = poolInfoUtils.lenderInterestMargin(ajnaPool_);
        poolRatesAndFees_.borrowFeeRate        = poolInfoUtils.borrowFeeRate(ajnaPool_);
        poolRatesAndFees_.depositFeeRate       = poolInfoUtils.depositFeeRate(ajnaPool_);

        // retrieve reserves info
        (
            poolReservesInfo_.reserves,
            poolReservesInfo_.claimableReserves,
            poolReservesInfo_.claimableReservesRemaining,
            poolReservesInfo_.auctionPrice,
            poolReservesInfo_.timeRemaining
        ) = poolInfoUtils.poolReservesInfo(ajnaPool_);

        // retrieve utilization info
        (
            poolUtilizationInfo_.poolMinDebtAmount,
            poolUtilizationInfo_.poolCollateralization,
            poolUtilizationInfo_.poolActualUtilization,
            poolUtilizationInfo_.poolTargetUtilization
        ) = poolInfoUtils.poolUtilizationInfo(ajnaPool_);
    }

    /**
     *  @notice Retrieves info of lenderInterestMargin, borrowFeeRate and depositFeeRate
     *  @param  ajnaPool_            Address of `Ajna` pool
     *  @return lenderInterestMargin Lender interest margin in pool
     *  @return borrowFeeRate        Borrow fee rate calculated from the pool interest rate
     *  @return depositFeeRate       Deposit fee rate calculated from the pool interest rate
     */
    function poolRatesAndFeesMulticall(address ajnaPool_)
        external view
        returns
        (
            uint256 lenderInterestMargin,
            uint256 borrowFeeRate,
            uint256 depositFeeRate
        )
    {
        lenderInterestMargin = poolInfoUtils.lenderInterestMargin(ajnaPool_);
        borrowFeeRate        = poolInfoUtils.borrowFeeRate(ajnaPool_);
        depositFeeRate       = poolInfoUtils.depositFeeRate(ajnaPool_);
    }

    /**
        *  @notice Retrieves pool debtInfo, depositUpToIndex, quoteTokenBalance and collateralTokenBalance
        *  @dev    This function is used to retrieve pool balance details in a single RPC call for Indexers.
        *  @param  ajnaPool_               Address of `Ajna` pool
        *  @param  index_                  Index of deposit
        *  @param  quoteTokenAddress_      Address of quote token
        *  @param  collateralTokenAddress_ Address of collateral token
        *  @param  isNFT_                  Boolean indicating if the pool is an NFT pool
        *  @return poolBalanceDetails_     Pool balance details struct
     */
    function poolBalanceDetails(address ajnaPool_, uint256 index_, address quoteTokenAddress_, address collateralTokenAddress_, bool isNFT_)
        external view
        returns (PoolBalanceDetails memory poolBalanceDetails_)
    {
        IPool pool = IPool(ajnaPool_);

        // pool debtInfo
        (poolBalanceDetails_.debt, poolBalanceDetails_.accruedDebt, poolBalanceDetails_.debtInAuction, poolBalanceDetails_.t0Debt2ToCollateral) = pool.debtInfo();

        // depositUpToIndex(index_)
        poolBalanceDetails_.depositUpToIndex = pool.depositUpToIndex(index_);

        // get pool quote token balance
        uint256 poolQuoteBalance = IERC20(quoteTokenAddress_).balanceOf(ajnaPool_);
        uint256 quoteScale = pool.quoteTokenScale();
        // normalize token balance to WAD scale
        poolBalanceDetails_.quoteTokenBalance = poolQuoteBalance * quoteScale;

        // get pool collateral token balance
        if (isNFT_) {
            // convert whole NFT amounts to WAD to match pool accounting
            poolBalanceDetails_.collateralTokenBalance = IERC721(collateralTokenAddress_).balanceOf(ajnaPool_) * 10**18;
        } else {
            // normalize token balance to WAD scale
            uint256 collateralScale = IERC20Pool(ajnaPool_).collateralScale();
            uint256 poolCollateralBalance = IERC20(collateralTokenAddress_).balanceOf(ajnaPool_);
            poolBalanceDetails_.collateralTokenBalance = poolCollateralBalance * collateralScale;
        }
    }
}