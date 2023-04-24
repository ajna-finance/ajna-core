// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';
import { Token }               from '../../utils/Tokens.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc20/IERC20Pool.sol';

import 'src/ERC20Pool.sol';

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
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   high,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        }); 
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   med,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   low,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   lowest,
            lpAward: 10_000 * 1e18,
            newLup:  MAX_PRICE
        });

        _drawDebt({
            from: _borrower,
            borrower: _borrower,
            amountToBorrow: 21_000 * 1e18,
            limitIndex: 3_000,
            collateralToPledge: 100 * 1e18,
            newLup: 2_981.007422784467321543 * 1e18
        });
    }

    function testPoolInfoUtilsInvariantsFuzzed(uint256 depositIndex_, uint256 price_) external {
        depositIndex_ = bound(depositIndex_, 0, 7388);
        assertEq(_priceAt(depositIndex_), _poolUtils.indexToPrice(depositIndex_));

        price_ = bound(price_, MIN_PRICE, MAX_PRICE);
        assertEq(_indexOf(price_), _poolUtils.priceToIndex(price_));
    }

    function testPoolInfoUtilsBorrowerInfo() external {
        (uint256 debt, uint256 collateral, uint256 t0Np) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        assertEq(debt,       21_020.192307692307702000 * 1e18);
        assertEq(collateral, 100 * 1e18);
        assertEq(t0Np,       220.712019230769230871 * 1e18);
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
        assertEq(quoteTokens,  10_000 * 1e18);
        assertEq(collateral,   0);
        assertEq(bucketLP,     10_000 * 1e18);
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
        assertEq(poolSize,              50_000 * 1e18);
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
        assertEq(htp,      210.201923076923077020 * 1e18);
        assertEq(htpIndex, 3083);
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

        assertEq(reserves,                   20.192307692307702000 * 1e18);
        assertEq(claimableReserves,          0);
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
        assertEq(poolCollateralization, 14.181637252165253251 * 1e18);
        assertEq(poolActualUtilization, 0);
        assertEq(poolTargetUtilization, 1 * 1e18);
    }

    function testPoolInfoUtilsLenderInterestMargin() external {
        uint256 lenderInterestMargin = _poolUtils.lenderInterestMargin(address(_pool));
        assertEq(lenderInterestMargin, 0.849999999999999999 * 1e18);
    }

    function testMomp() external {
        assertEq(_poolUtils.momp(address(_pool)), 2_981.007422784467321543 * 1e18);

        // ensure calculation does not revert on pools with no loans and no deposit
        IERC20     otherCollateral = new Token("MompTestCollateral", "MTC");
        IERC20Pool emptyPool       = ERC20Pool(_poolFactory.deployPool(address(otherCollateral), address(_quote), 0.05 * 10**18));
        assertEq(_poolUtils.momp(address(emptyPool)), MIN_PRICE);

        // should return HPB on pools with liquidity but no loans
        changePrank(_lender);
        uint256 hpbIndex = 369;
        _quote.approve(address(emptyPool), type(uint256).max);
        emptyPool.addQuoteToken(0.0213 * 1e18, hpbIndex, type(uint256).max);
        assertEq(_poolUtils.momp(address(emptyPool)), _priceAt(hpbIndex));
    }

    function testBorrowFeeRate() external {
        assertEq(_poolUtils.borrowFeeRate(address(_pool)), 0.000961538461538462 * 1e18);
    }

    function testUnutilizedDepositFeeRate() external {
        assertEq(_poolUtils.unutilizedDepositFeeRate(address(_pool)), 0.000136986301369863 * 1e18);
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
            ), 1668940620571264
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
}
