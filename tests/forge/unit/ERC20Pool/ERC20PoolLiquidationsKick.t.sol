// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { ERC20HelperContract, ERC20FuzzyHelperContract } from './ERC20DSTestPlus.sol';

import 'src/interfaces/pool/commons/IPoolErrors.sol';
import 'src/libraries/helpers/PoolHelper.sol';
import 'src/PoolInfoUtils.sol';

contract ERC20PoolLiquidationsKickTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;
    address internal _withdrawRecipient;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _borrower2         = makeAddr("borrower2");
        _lender            = makeAddr("lender");
        _lender1           = makeAddr("lender1");
        _withdrawRecipient = makeAddr("withdrawRecipient");

        _mintQuoteAndApproveTokens(_lender,  120_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_000 * 1e18);
        _mintCollateralAndApproveTokens(_lender1,   4 * 1e18);

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     18.65 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       _borrower2,
            amount:     7_980 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.707325000000000004 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             72_996.666666666666667 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 856.531347837213447051 * 1e18,
                poolDebt:             8_006.341009615384619076 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.317050480769230954 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.667932692307692316 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 1.001439208539095951 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.170228147822941070 * 1e18
        });
        _assertReserveAuction({
            reserves:                   11.024342948717952076 * 1e18,
            claimableReserves :         11.024269952051285409 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

    }
    
    function testKick() external tearDown {
        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.925417364872552389 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.987814396904404787 * 1e18
        });

        // should revert if NP goes below limit
        _assertKickNpUnderLimitRevert({
            from:     _lender,
            borrower: _borrower
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.925417364872552388 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.211592598652049829 * 1e18,
            transferAmount: 0.211592598652049829 * 1e18
        });

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  8.421759988983929586 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_090.532635019443083793 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 868.345387306633668354 * 1e18,
                poolDebt:             8_116.771560618651000629 * 1e18,
                actualUtilization:    0.109680912502151486 * 1e18,
                targetUtilization:    0.821990428412900408 * 1e18,
                minDebtAmount:        811.677156061865100063 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.925417364872552389 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.987814396904404787 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8_097.846143253778448241 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.235950959066335145 * 1e18,
            borrowerCollateralization: 1.154306923700949203 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 46_999.788407401347950171 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.211592598652049829 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.941498542724386393 * 1e18,
                totalBondEscrowed: 0.211592598652049829 * 1e18,
                auctionPrice:      2_801.023626937442916608 * 1e18,
                debtInAuction:     18.925417364872552389 * 1e18,
                debtToCollateral:  9.462708682436276194 * 1e18,
                neutralPrice:      10.941498542724386393 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.211592598652049829 * 1e18
        });
        _assertReserveAuction({
            reserves:                   27.588925599207916836 * 1e18,
            claimableReserves :         27.588852508675281817 * 1e18,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        // kick should fail if borrower properly collateralized
        _assertKickCollateralizedBorrowerRevert({
            from:       _lender,
            borrower:   _borrower2
        });

        _assertDepositLockedByAuctionDebtRevert({
            operator:  _lender,
            amount:    100 * 1e18,
            index:     _i9_91
        });

        skip(80 hours);

        // check locked pool actions if auction kicked for more than 72 hours and auction head not cleared
        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  _i9_91
        });
        _assertRemoveCollateralAuctionNotClearedRevert({
            from:   _lender,
            amount: 10 * 1e18,
            index:  _i9_91
        });
    }

    function testKickActiveAuctionReverts() external tearDown {
        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.925417364872552389 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.987814396904404787 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.925417364872552388 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.211592598652049829 * 1e18,
            transferAmount: 0.211592598652049829 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.211592598652049829 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    10.941498542724386393 * 1e18,
                totalBondEscrowed: 0.211592598652049829 * 1e18,
                auctionPrice:      2_801.023626937442916608 * 1e18,
                debtInAuction:     18.925417364872552389 * 1e18,
                debtToCollateral:  9.462708682436276194 * 1e18,
                neutralPrice:      10.941498542724386393 * 1e18
            })
        );

        // should not allow borrower to draw more debt if auction kicked
        _assertBorrowAuctionActiveRevert({
            from:       _borrower,
            amount:     1 * 1e18,
            indexLimit: 7000
        });

        // should not allow borrower to restamp the Neutral Price of the loan if auction kicked
        _assertStampLoanAuctionActiveRevert({
            borrower: _borrower
        });
    }

    function testKickAuctionWithoutCollateralReverts() external tearDown {
        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.925417364872552389 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.987814396904404787 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.925417364872552388 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.211592598652049829 * 1e18,
            transferAmount: 0.211592598652049829 * 1e18
        });

        // skip enough time to take collateral close to 0 price
        skip(70 hours);
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      0,
            givenAmount:     16,
            collateralTaken: 2 * 1e18,
            isReward:        true
        });
        // entire borrower collateral is taken but auction not settled as there's still bad debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.932223961270518842 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        // kick borrower again should gracefully revert with AuctionActive error
        _assertKickAuctionActiveRevert({
            from:     _lender,
            borrower: _borrower
        });
    }

    function testInterestsAccumulationWithAllLoansAuctioned() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_300 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              18.925417364872552389 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.792636928984157297 * 1e18,
            borrowerCollateralization: 0.987814396904404787 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_417.044136515672180411 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              10.740554498763858415 * 1e18,
            borrowerCollateralization: 0.992604445165255887 * 1e18
        });
        _assertLoans({
            noOfLoans:             2,
            maxBorrower:           _borrower,
            maxT0DebtToCollateral: 9.333966346153846158 * 1e18
        });

        // kick first loan
        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_417.044136515672180410 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           105.285754181824258217 * 1e18,
            transferAmount: 105.285754181824258217 * 1e18
        });

        _assertLoans({
            noOfLoans:             1,
            maxBorrower:           _borrower,
            maxT0DebtToCollateral: 9.333966346153846158 * 1e18
        });

        // kick 2nd loan
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           18.925417364872552388 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.211592598652049829 * 1e18,
            transferAmount: 0.211592598652049829 * 1e18
        });

        _assertLoans({
            noOfLoans:             0,
            maxBorrower:           address(0),
            maxT0DebtToCollateral: 0
        });
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_105.788429292052758482 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_009.475328421524777337 * 1e18,
                poolDebt:             9_435.969553880544732799 * 1e18,
                actualUtilization:    0.517112001843252414 * 1e18,
                targetUtilization:    0.955532425687922567 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 100 days
            })
        );

        // force pool interest accumulation 
        skip(14 hours);

        _addCollateralWithoutCheckingLP({
            from:    _lender1,
            amount:  1 * 1e18,
            index:   _i9_91
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_106.387204998685760269 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 1_009.547930285248351849 * 1e18,
                poolDebt:             9_436.648192532092411327 * 1e18,
                actualUtilization:    0.095694819083490222 * 1e18,
                targetUtilization:    0.955532425687922567 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 100 days + 14 hours
            })
        );
    }
}

contract ERC20PoolLiquidationKickFuzzyTest is ERC20FuzzyHelperContract {
    address internal _lender;
    address internal _kicker;
    address[] internal _borrowers;
    
    function setUp() external {
        _startTest();
        _lender = makeAddr("lender");
        _kicker = makeAddr("kicker");
    }

    function testBorrowAndKickFuzzy(uint256 noOfBorrowers, uint256 totalPoolLiquidity, uint256 startingBucket, uint256 noOfBuckets) external tearDown {
        noOfBorrowers = bound(noOfBorrowers, 1, 10);
        totalPoolLiquidity = bound(totalPoolLiquidity, 100 * 1e18, 1_000_000_000 * 1e18);
        startingBucket = bound(startingBucket, 1, 7300);
        noOfBuckets = bound(noOfBuckets, 5, 10);
        uint256 poolRate = 0.05 * 1e18;

        _mintQuoteAndApproveTokens(_lender, totalPoolLiquidity);

        // lender deposits all liquidity in 5 buckets
        for(uint i = 0; i < noOfBuckets; i++) {
            _addLiquidity({
                from:    _lender,
                amount:  totalPoolLiquidity / noOfBuckets,
                index:   startingBucket + i,
                lpAward: Maths.wmul(totalPoolLiquidity / noOfBuckets, Maths.WAD - _depositFeeRate(poolRate)),
                newLup:  MAX_PRICE
            });

            _assertBucket({
                index:        startingBucket + i,
                lpBalance:    Maths.wmul(totalPoolLiquidity / noOfBuckets, Maths.WAD - _depositFeeRate(poolRate)),
                collateral:   0,
                deposit:      Maths.wmul(totalPoolLiquidity / noOfBuckets, Maths.WAD - _depositFeeRate(poolRate)),
                exchangeRate: 1 * 1e18
            });
        }

        _borrowers = new address[](noOfBorrowers);

        // total Amount to borrow is kept 80% of total Liquidity available to account origination fees 
        uint256 totalAmountToBorrow = totalPoolLiquidity * 4 / 5;

        // all borrowers draws fuzzed amount of debt
        for (uint256 i = 0; i < noOfBorrowers; ++i) {
            _borrowers[i] = makeAddr(string(abi.encodePacked("Borrower", Strings.toString(i))));

            uint256 amountToBorrow = bound(totalAmountToBorrow, 1 * 1e18, totalAmountToBorrow / noOfBorrowers);

            // calculate collateral required to borrow amount
            (uint256 poolDebt, , , ) = _pool.debtInfo();
            uint256 depositIndex     = _pool.depositIndex(amountToBorrow + poolDebt);
            uint256 price = _poolUtils.indexToPrice(depositIndex);
            uint256 collateralToPledge = Maths.wdiv(Maths.wmul(amountToBorrow, COLLATERALIZATION_FACTOR), price) * 101 / 100 + 1;

            _mintCollateralAndApproveTokens(_borrowers[i], collateralToPledge);

            _drawDebtNoLupCheck({
                from:               _borrowers[i],
                borrower:           _borrowers[i],
                amountToBorrow:     amountToBorrow,
                limitIndex:         7_388,
                collateralToPledge: collateralToPledge
            });

            uint256 borrowerDebt = Maths.wmul(amountToBorrow, _poolUtils.borrowFeeRate(address(_pool)) + Maths.WAD);

            (,, uint256 borrowert0Np, ) = _poolUtils.borrowerInfo(address(_pool), _borrowers[i]);

            uint256 lup = _poolUtils.lup(address(_pool));

            _assertBorrower({
                borrower:                  _borrowers[i],
                borrowerDebt:              borrowerDebt,
                borrowerCollateral:        collateralToPledge,
                borrowert0Np:              borrowert0Np,
                borrowerCollateralization: _collateralization(borrowerDebt, collateralToPledge, lup)
            });
        }

        // skip some time to make all borrowers undercollateralized
        skip(400 days);

        changePrank(_kicker);
        _mintQuoteAndApproveTokens(_kicker, totalPoolLiquidity / 10);

        // kick all borrowers
        for (uint256 i = 0; i < noOfBorrowers; i++) {
            _pool.kick(_borrowers[i], 7_388);
            (uint256 kickTime,,,,,,,,) = _poolUtils.auctionStatus(address(_pool), _borrowers[i]);

            // ensure borrower is kicked
            assertEq(kickTime, block.timestamp);
        }
    }
}

contract ERC20PoolLiquidationKickHighThresholdPriceBorrower is ERC20HelperContract {
    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _lender            = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender,  10_000_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
    }

    function testKickHighThresholdPriceBorrower() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  1
        });

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   0.0000011 * 1e18
        });
        
        _borrow({
            from:       _borrower,
            amount:     998 * 1e18,
            indexLimit: 7388,
            newLup:     _priceAt(1)
        });

        for (uint256 i = 0; i < 2000; i++) {
            skip(13 hours);
            _updateInterest();
        }

        uint256 htp = _poolUtils.htp(address(_pool));

        // htp is greater than MAX_INFLATED_PRICE
        assertTrue(htp > MAX_INFLATED_PRICE);

        // htp is greater than max uint96 value 
        assertTrue(htp > type(uint96).max);

        // Kick borrower
        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           108_328_580.483857986778697590 * 1e18,
            collateral:     0.0000011 * 1e18,
            bond:           1_211_150.349339817537800651 * 1e18,
            transferAmount: 1_211_150.349339817537800651 * 1e18
        });
    }
}
