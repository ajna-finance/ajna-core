// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';
import { Token }               from '../../utils/Tokens.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

import 'src/ERC20Pool.sol';
import 'src/PoolInfoUtilsMulticall.sol';

contract ERC20PoolInfoUtilsTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    uint256 highest = 2550;
    uint256 high    = 2551;
    uint256 med     = 2552;
    uint256 low     = 2553;
    uint256 lowest  = 2554;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintCollateralAndApproveTokens(_borrower,  100 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2,  100 * 1e18);

        _mintQuoteAndApproveTokens(_lender,   200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1,  200_000 * 1e18);

        // lender deposits 10000 DAI in 5 buckets each
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   highest,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   high,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  MAX_PRICE
        }); 
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   med,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   low,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   lowest,
            lpAward: 9_999.54337899543379 * 1e18,
            newLup:  MAX_PRICE
        });

        _drawDebt({
            from:               _borrower,
            borrower:           _borrower,
            amountToBorrow:     21_000 * 1e18,
            limitIndex:         3_000,
            collateralToPledge: 100 * 1e18,
            newLup:             2_981.007422784467321543 * 1e18
        });
    }

    function testPoolInfoUtilsInvariantsFuzzed(uint256 depositIndex_, uint256 price_) external {
        depositIndex_ = bound(depositIndex_, 0, 7388);
        assertEq(_priceAt(depositIndex_), _poolUtils.indexToPrice(depositIndex_));

        price_ = bound(price_, MIN_PRICE, MAX_PRICE);
        assertEq(_indexOf(price_), _poolUtils.priceToIndex(price_));
    }

    function testPoolInfoUtilsAuctionStatusNoLiquidation() external {
        (
            uint256 kickTime,
            uint256 collateral,
            uint256 debtToCover,
            bool    isCollateralized,
            uint256 price,
            uint256 neutralPrice,
            uint256 referencePrice,
            uint256 debtToCollateral,
            uint256 bondFactor
        ) = _poolUtils.auctionStatus(address(_pool), _borrower);
        // since loan is not in auction values are 0
        assertEq(kickTime,         0);
        assertEq(collateral,       0);
        assertEq(debtToCover,      0);
        assertEq(isCollateralized, false);
        assertEq(price,            0);
        assertEq(neutralPrice,     0);
        assertEq(referencePrice,   0);
        assertEq(debtToCollateral, 0);
        assertEq(bondFactor,       0);
    }

    function testPoolInfoUtilsAuctionStatusMatureLiquidation() external {
        _removeAndKick();
        skip(6 hours);
        (
            uint256 kickTime,
            uint256 collateral,
            uint256 debtToCover,
            bool    isCollateralized,
            uint256 price,
            uint256 neutralPrice,
            uint256 referencePrice,
            uint256 debtToCollateral,
            uint256 bondFactor
        ) = _poolUtils.auctionStatus(address(_pool), _borrower);
        // at 6 hours, auction price should match reference price
        assertEq(kickTime,          _startTime);
        assertEq(collateral,        100 * 1e18);
        assertEq(debtToCover,       21_020.912189618561131155 * 1e18);
        assertEq(isCollateralized,  true);
        assertEq(price,             243.051341028061451208 * 1e18);
        assertEq(neutralPrice,      243.051341028061451209 * 1e18);
        assertEq(referencePrice,    243.051341028061451209 * 1e18);
        assertEq(debtToCollateral,  210.201923076923077020 * 1e18);
        assertEq(bondFactor,        0.011180339887498948 * 1e18);
    }


    function testPoolInfoUtilsAuctionInfoNoLiquidation() external {
        (
            address kicker,
            uint256 bondFactor,
            uint256 bondSize,
            uint256 kickTime,
            uint256 referencePrice,
            uint256 neutralPrice,
            uint256 debtToCollateral,
            address head,
            address next,
            address prev
        ) = _poolUtils.auctionInfo(address(_pool), _borrower);
        // since loan is not in auction values are 0
        assertEq(kicker,            address(0));
        assertEq(bondFactor,        0);
        assertEq(bondSize,          0);
        assertEq(kickTime,          0);
        assertEq(referencePrice,    0);
        assertEq(neutralPrice,      0);
        assertEq(debtToCollateral,  0);
        assertEq(head,              address(0));
        assertEq(next,              address(0));
        assertEq(prev,              address(0));
    }

    function testPoolInfoUtilsAuctionInfoSingleLiquidation() external {
        _removeAndKick();
        (
            address kicker,
            uint256 bondFactor,
            uint256 bondSize,
            uint256 kickTime,
            uint256 referencePrice,
            uint256 neutralPrice,
            uint256 debtToCollateral,
            address head,
            address next,
            address prev
        ) = _poolUtils.auctionInfo(address(_pool), _borrower);
        assertEq(kicker,            _lender);
        assertEq(bondFactor,        0.011180339887498948 * 1e18);
        assertEq(bondSize,          235.012894500590867635 * 1e18);
        assertEq(kickTime,          _startTime);
        assertEq(referencePrice,    243.051341028061451209 * 1e18);
        assertEq(neutralPrice,      243.051341028061451209 * 1e18);
        assertEq(debtToCollateral,  210.201923076923077020 * 1e18);
        assertEq(head,              _borrower);
        assertEq(next,              address(0));
        assertEq(prev,              address(0));
    }

    function testPoolInfoUtilsBorrowerInfo() external {
        (uint256 debt, uint256 collateral, uint256 npTpRatio, uint256 thresholdPrice) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,       21_020.192307692307702000 * 1e18);
        assertEq(collateral, 100 * 1e18);
        assertEq(thresholdPrice, 218.610000000000000101 * 1e18);
        assertEq(npTpRatio,  243.051341028061451209 * 1e18);
    }

    function testPoolInfoUtilsBucketInfo() external {
        (
            uint256 price,
            uint256 quoteTokens,
            uint256 collateral,
            uint256 bucketLP,
            uint256 scale,
            uint256 exchangeRate
        ) = _poolUtils.bucketInfo(address(_pool), 5000);

        assertEq(price,        0.014854015662334135 * 1e18);
        assertEq(quoteTokens,  0);
        assertEq(collateral,   0);
        assertEq(bucketLP,     0);
        assertEq(scale,        1 * 1e18);
        assertEq(exchangeRate, 1 * 1e18);

        (
            price,
            quoteTokens,
            collateral,
            bucketLP,
            scale,
            exchangeRate
        ) = _poolUtils.bucketInfo(address(_pool), high);
        assertEq(price,        2_995.912459898389633881 * 1e18);
        assertEq(quoteTokens,  9_999.54337899543379 * 1e18);
        assertEq(collateral,   0);
        assertEq(bucketLP,     9_999.54337899543379 * 1e18);
        assertEq(scale,        1 * 1e18);
        assertEq(exchangeRate, 1 * 1e18);
    }

    function testPoolInfoUtilsLoansInfo() external {
        (
            uint256 poolSize,
            uint256 loansCount,
            address maxBorrower,
            uint256 pendingInflator,
            uint256 pendingInterestFactor
        ) = _poolUtils.poolLoansInfo(address(_pool));
        assertEq(poolSize,              49_997.71689497716895 * 1e18);
        assertEq(loansCount,            1);
        assertEq(maxBorrower,           _borrower);
        assertEq(pendingInflator,       1 * 1e18);
        assertEq(pendingInterestFactor, 1 * 1e18);
    }

    function testPoolInfoUtilsPricesInfo() external {
        (
            uint256 hpb,
            uint256 hpbIndex,
            uint256 htp,
            uint256 htpIndex,
            uint256 lup,
            uint256 lupIndex
        ) = _poolUtils.poolPricesInfo(address(_pool));

        assertEq(hpb,      3_010.892022197881557845 * 1e18);
        assertEq(hpbIndex, 2550);
        assertEq(htp,      218.610000000000000101 * 1e18);
        assertEq(htpIndex, 3075);
        assertEq(lup,      2981.007422784467321543 * 1e18);
        assertEq(lupIndex, 2552);

        assertEq(hpb,      _poolUtils.hpb(address(_pool)));
        assertEq(hpbIndex, _poolUtils.hpbIndex(address(_pool)));
        assertEq(htp,      _poolUtils.htp(address(_pool)));
        assertEq(lup,      _poolUtils.lup(address(_pool)));
        assertEq(lupIndex, _poolUtils.lupIndex(address(_pool)));
    }

    function testPoolInfoUtilsReservesInfo() external {
        (
            uint256 reserves,
            uint256 claimableReserves,
            uint256 claimableReservesRemaining,
            uint256 auctionPrice,
            uint256 timeRemaining
        ) = _poolUtils.poolReservesInfo(address(_pool));

        assertEq(reserves,                   22.475412715138752000 * 1e18);
        assertEq(claimableReserves,          22.475362717421857023 * 1e18);
        assertEq(claimableReservesRemaining, 0);
        assertEq(auctionPrice,               0);
        assertEq(timeRemaining,              0);
    }

    function testPoolInfoUtilsUtilizationInfo() external {
        (
            uint256 poolMinDebtAmount,
            uint256 poolCollateralization,
            uint256 poolActualUtilization,
            uint256 poolTargetUtilization
        ) = _poolUtils.poolUtilizationInfo(address(_pool));

        assertEq(poolMinDebtAmount,     2_102.019230769230770200 * 1e18);
        assertEq(poolCollateralization, 13.636189665543512740 * 1e18);
        assertEq(poolActualUtilization, 0);
        assertEq(poolTargetUtilization, 1 * 1e18);
    }

    function testPoolInfoUtilsLenderInterestMargin() external {
        uint256 lenderInterestMargin = _poolUtils.lenderInterestMargin(address(_pool));
        assertEq(lenderInterestMargin, 0.849999999999999999 * 1e18);
    }

    function testBorrowFeeRate() external {
        assertEq(_poolUtils.borrowFeeRate(address(_pool)), 0.000961538461538462 * 1e18);
    }

    function testDepositFeeRate() external {
        assertEq(_poolUtils.depositFeeRate(address(_pool)), 0.000045662100456621 * 1e18);
    }

    function testPoolInfoUtilsLPToCollateralAndQuote() external {
        assertEq(
            _poolUtils.lpToCollateral(
                address(_pool),
                100 * 1e18,
                high
            ), 0
        );

        changePrank(_borrower2);
        ERC20Pool(address(_pool)).addCollateral(10 * 1e18, high, block.timestamp + 5 minutes);

        assertEq(
            _poolUtils.lpToCollateral(
                address(_pool),
                5 * 1e18,
                high
            ), 1668940620571263
        );
        assertEq(
            _poolUtils.lpToCollateral(
                address(_pool),
                20 * 1e18,
                high
            ), 6675762482285055
        );
        assertEq(
            _poolUtils.lpToQuoteTokens(
                address(_pool),
                100 * 1e18,
                high
            ), 100000000000000000000
        );
        assertEq(
            _poolUtils.lpToQuoteTokens(
                address(_pool),
                5 * 1e18,
                high
            ), 5000000000000000000
        );
        assertEq(
            _poolUtils.lpToQuoteTokens(
                address(_pool),
                20 * 1e18,
                high
            ), 20000000000000000000
        );
    }

    // Helps test liquidation functions
    function _removeAndKick() internal {
        uint256 amountLessFee = 9_999.543378995433790000 * 1e18;
        _removeAllLiquidity({
            from:     _lender, 
            amount:   amountLessFee,
            index:    lowest,
            newLup:   _priceAt(med), 
            lpRedeem: amountLessFee
        });
        _removeAllLiquidity({
            from:     _lender, 
            amount:   amountLessFee,
            index:    low,
            newLup:   _priceAt(med), 
            lpRedeem: amountLessFee
        });
        _lenderKick({
            from:       _lender, 
            index:      med, 
            borrower:   _borrower, 
            debt:       21_020.192307692307702000 * 1e18, 
            collateral: 100 * 1e18, 
            bond:       235.012894500590867635 * 1e18
        });
    }

    function testPoolInfoUtilsMulticallRatesAndFees() external {
        PoolInfoUtilsMulticall poolUtilsMulticall = new PoolInfoUtilsMulticall(_poolUtils);

        (uint256 lim, uint256 bfr, uint256 dfr) = poolUtilsMulticall.poolRatesAndFeesMulticall(address(_pool));

        assertEq(lim, 0.849999999999999999 * 1e18);
        assertEq(bfr, 0.000961538461538462 * 1e18);
        assertEq(dfr, 0.000045662100456621* 1e18);
    }

    function testPoolInfoUtilsMulticallPoolDetails() external {
        PoolInfoUtilsMulticall poolUtilsMulticall = new PoolInfoUtilsMulticall(_poolUtils);

        (
            PoolInfoUtilsMulticall.PoolLoansInfo memory poolLoansInfo,
            PoolInfoUtilsMulticall.PoolPriceInfo memory poolPriceInfo,
            PoolInfoUtilsMulticall.PoolRatesAndFees memory poolRatesAndFees,
            PoolInfoUtilsMulticall.PoolReservesInfo memory poolReservesInfo,
            PoolInfoUtilsMulticall.PoolUtilizationInfo memory poolUtilizationInfo
        ) = poolUtilsMulticall.poolDetailsMulticall(address(_pool));

        assertEq(poolLoansInfo.poolSize, 49_997.716894977168950000 * 1e18);

        assertEq(poolPriceInfo.hpb,      3_010.892022197881557845 * 1e18);
        assertEq(poolPriceInfo.hpbIndex, 2550);
        assertEq(poolPriceInfo.htp,      218.610000000000000101 * 1e18);
        assertEq(poolPriceInfo.htpIndex, 3075);
        assertEq(poolPriceInfo.lup,      2981.007422784467321543 * 1e18);
        assertEq(poolPriceInfo.lupIndex, 2552);

        assertEq(poolRatesAndFees.lenderInterestMargin, 0.849999999999999999 * 1e18);
        assertEq(poolRatesAndFees.borrowFeeRate,        0.000961538461538462 * 1e18);
        assertEq(poolRatesAndFees.depositFeeRate,       0.000045662100456621 * 1e18);

        assertEq(poolReservesInfo.reserves,             22.475412715138752000 * 1e18);

        assertEq(poolUtilizationInfo.poolMinDebtAmount, 2_102.019230769230770200 * 1e18);
    }

    function testPoolInfoUtilsMulticallPoolBalanceDetails() external {
        PoolInfoUtilsMulticall poolUtilsMulticall = new PoolInfoUtilsMulticall(_poolUtils);

        uint256 meaningfulIndex = 5000;
        address quoteTokenAddress = IPool(_pool).quoteTokenAddress();
        address collateralTokenAddress = IPool(_pool).collateralAddress();

        PoolInfoUtilsMulticall.PoolBalanceDetails memory poolBalanceDetails = poolUtilsMulticall.poolBalanceDetails(address(_pool), meaningfulIndex, quoteTokenAddress, collateralTokenAddress, false);

        assertEq(poolBalanceDetails.debt,        21_020.192307692307702000 * 1e18);
        assertEq(poolBalanceDetails.quoteTokenBalance,  29_000 * 1e18);
        assertEq(poolBalanceDetails.collateralTokenBalance,  100 * 1e18);
    }
}
