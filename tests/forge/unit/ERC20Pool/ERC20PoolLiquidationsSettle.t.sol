// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract } from './ERC20DSTestPlus.sol';

import 'src/ERC20Pool.sol';
import 'src/interfaces/pool/commons/IPoolEvents.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolLiquidationsSettleTest is ERC20HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender1;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender1   = makeAddr("lender1");

        _mintQuoteAndApproveTokens(_lender,  120_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 120_000 * 1e18);

        _mintCollateralAndApproveTokens(_borrower,  4 * 1e18);
        _mintCollateralAndApproveTokens(_borrower2, 1_001 * 1e18);
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
            amount:     19.25 * 1e18,
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
                htp:                  9.634254807692307697 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    1_002 * 1e18,
                encumberedCollateral: 823.649613971736296163 * 1e18,
                poolDebt:             8_006.941586538461542154 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1e18,
                minDebtAmount:        400.347079326923077108 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.268509615384615394 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.096767433127708186 * 1e18,
            borrowerCollateralization: 1.009034539679184679 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_987.673076923076926760 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              9.200228999102245332 * 1e18,
            borrowerCollateralization: 1.217037273735858713 * 1e18
        });
        _assertReserveAuction({
            reserves:                   7.691586538461542154 * 1e18,
            claimableReserves :         0,
            claimableReservesRemaining: 0,
            auctionPrice:               0,
            timeRemaining:              0
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

    }
    
    function testSettleOnAuctionKicked72HoursAgoAndPartiallyTaken() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_012.686105677503216000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    5_000 * 1e18,
            collateral:   0,
            deposit:      5_031.715264193758040000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      11_069.773581226267688000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853900422492752583 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.900422492752583093 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986542937133981323 * 1e18
        });

        // take partial 800 collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   800 * 1e18,
            bondChange:      34.456860650725712362 * 1e18,
            givenAmount:     2_269.834595673383616 * 1e18,
            collateralTaken: 800 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          184.034734289495351885 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 184.034734289495351885 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     7_618.522687470094679893 * 1e18,
                thresholdPrice:    38.092613437350473399 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_618.522687470094679893 * 1e18,
            borrowerCollateral:        200 * 1e18,
            borrowert0Np:              43.276046239860018335 * 1e18,
            borrowerCollateralization: 0.255201599150450493 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_012.735939051273346000 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    5_000 * 1e18,
            collateral:   0,
            deposit:      5_031.839847628183365000 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      11_070.047664782003403000 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // settle should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_621.380169222238377339 * 1e18,
            borrowerCollateral:        200 * 1e18,
            borrowert0Np:              43.276046239860018335 * 1e18,
            borrowerCollateralization: 0.255105916492388742 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_012.735939051273346000 * 1e18,
            exchangeRate: 1.006367969525636673 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 7_514.484899441934449285 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 184.034734289495351885 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   200 * 1e18,
            deposit:      0,
            exchangeRate: 0.991718484343591208 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      10_525.670272469343333339 * 1e18,
            exchangeRate: 0.956879115679031213 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertPool(
            PoolParams({
                htp:                  9.771304290202671377 * 1e18,
                lup:                  9.721295865031779605 * 1e18,
                poolSize:             65_525.670272469343333339 * 1e18,
                pledgedCollateral:    2 * 1e18,
                encumberedCollateral: 2.010288427770370775 * 1e18,
                poolDebt:             19.542608580405342754 * 1e18,
                actualUtilization:    0.593847771807726236 * 1e18,
                targetUtilization:    0.999790809254532429 * 1e18,
                minDebtAmount:        1.954260858040534275 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.0405 * 1e18,
                interestRateUpdate:   _startTime + 83 hours + 100 days
            })
        );
    }

    function testSettleOnAuctionKicked72HoursAgo() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          _startTime + 100 days,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_012.686105677503216000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    5_000 * 1e18,
            collateral:   0,
            deposit:      5_031.715264193758040000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0,
            deposit:      11_069.773581226267688000 * 1e18,
            exchangeRate: 1.006343052838751608 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // settle should work on an kicked auction if 72 hours passed from kick time
        // settle should affect first 3 buckets, reducing deposit and incrementing collateral
        skip(73 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 73 hours,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      0,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.857089957723356708 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_857.089957723356708150 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986223713766031127 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 9_719.336538461538466020 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_000 * 1e18,
            collateral:   202.986026776638220827 * 1e18,
            deposit:      0,
            exchangeRate: 1.006524974089276386 * 1e18
        });
        _assertBucket({
            index:        _i9_81,
            lpBalance:    5_000 * 1e18,
            collateral:   512.552404237685039184 * 1e18,
            deposit:      0,
            exchangeRate: 1.006524974089276386 * 1e18
        });
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   284.461568985676739989 * 1e18,
            deposit:      8_290.291541398624686508 * 1e18,
            exchangeRate: 1.005056965067230573 * 1e18
        });
        _assertBucket({
            index:        _i9_62,
            lpBalance:    25_000 * 1e18,
            collateral:   0,
            deposit:      25_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        
        // borrower can re-open a loan once their previous loan is fully settled
        _drawDebt({
            from: _borrower2,
            borrower: _borrower2,
            amountToBorrow: 5 * 1e18,
            limitIndex: _i9_72,
            collateralToPledge: 1 * 1e18,
            newLup: 9.721295865031779605 * 1e18
        });
    }

    function testSettleAuctionReverts() external {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);
        // settle should revert on a borrower that is not auctioned
        _assertSettleOnNotKickedAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });

        uint256 kickTime = _startTime + 100 days;

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        // settle should revert on an kicked auction but 72 hours not passed (there's still debt to settle and collateral to be auctioned)
        _assertSettleOnNotClearableAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });

        // skip ahead so take can be called on the loan
        skip(12.5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      1.192934859200383004 * 1e18,
                debtInAuction:     9853.394241979221645667 * 1e18,
                thresholdPrice:    9.854026971684066190 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_854.026971684066190794 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986530267571451282 * 1e18
        });

        _addLiquidityWithPenalty({
            from:        _lender1,
            amount:      100 * 1e18,
            amountAdded: 99.987671232876712300 * 1e18,
            index:       _i9_52,
            lpAward:     99.987671232876712300 * 1e18,
            newLup:      9.721295865031779605 * 1e18
        });
 
        _addLiquidity({ 
            from:    _lender1, 
            amount:  100 * 1e18, 
            index:   _i9_91, 
            lpAward: 99.366617416827728755 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        // take entire collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      18.109156626307515503 * 1e18,
            givenAmount:     1_192.934859200383004000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        // remove quote tokens should fail since auction head is clearable
        _assertRemoveLiquidityAuctionNotClearedRevert({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  _i9_52
        });

        _assertRemoveAllLiquidityAuctionNotClearedRevert({
            from:   _lender,
            index:  _i9_52
        });

        // remove collateral should fail since auction head is clearable
        _assertRemoveCollateralAuctionNotClearedRevert({
            from:   _lender,
            amount: 10 * 1e18,
            index:  _i9_52
        });

        // remove all collateral should fail since auction head is clearable
        _assertRemoveAllCollateralAuctionNotClearedRevert({
            from:   _lender,
            index:  _i9_52
        });

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   99.366617416827728755 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours
        });

        // settle to make buckets insolvent
        // settle should work because there is still debt to settle but no collateral left to auction (even if 72 hours didn't pass from kick)
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              8679.201269109990702794 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });


        assertTrue(block.timestamp - kickTime < 72 hours); // assert auction was kicked less than 72 hours ago

        // LP forfeited when forgive bad debt should be reflected in BucketBankruptcy event
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_91, 2_099.366617416827728755 * 1e18);
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_81, 5_000 * 1e18);
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 8_560.569020353099739628 * 1e18
        });

        // bucket is insolvent, balances are resetted
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        // after bucket bankruptcy lenders balance is zero
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime
        });
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime + 100 days + 12.5 hours
        });

        // cannot add liquidity in same block when bucket marked insolvent
        _assertAddLiquidityBankruptcyBlockRevert({
            from:   _lender1,
            amount: 1_000 * 1e18,
            index:  _i9_91
        });

        // cannot add collateral in same block when bucket marked insolvent
        _assertAddCollateralBankruptcyBlockRevert({
            from:   _lender1,
            amount: 10 * 1e18,
            index:  _i9_91
        });

        // cannot move LP in same block when bucket marked insolvent
        _assertMoveLiquidityBankruptcyBlockRevert({
            from:      _lender1,
            amount:    10 * 1e18,
            fromIndex: _i9_52,
            toIndex:   _i9_91
        });

        // all operations should work if not in same block
        skip(1 hours);

        // move quote token in a bankrupt bucket should set deposit time to time of bankruptcy + 1 to prevent losing deposit
        _pool.moveQuoteToken(10 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes, false);
        (, , uint256 bankruptcyTime, , ) = _pool.bucketInfo(_i9_91);
        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   10 * 1e18,
            depositTime: bankruptcyTime + 1
        });

        _pool.addQuoteToken(100 * 1e18, _i9_91, block.timestamp + 1 minutes, false);
        ERC20Pool(address(_pool)).addCollateral(4 * 1e18, _i9_91, block.timestamp + 1 minutes);

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   149.668739373743648296 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 hours
        });
        // bucket is healthy again
        _assertBucket({
            index:        _i9_91,
            lpBalance:    149.668739373743648296 * 1e18,
            collateral:   4 * 1e18,
            deposit:      110 * 1e18,
            exchangeRate: 1 * 1e18
        });

        // when moving to a bucket that was marked insolvent, the deposit time should be the greater between from bucket deposit time and insolvency time + 1
        changePrank(_lender);
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   0,
            depositTime: _startTime
        });

        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes, false);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   1_000 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 // _i9_91 bucket insolvency time + 1 (since deposit in _i9_52 from bucket was done before _i9_91 target bucket become insolvent)
        });

        _pool.addQuoteToken(1_000 * 1e18, _i9_52, block.timestamp + 1 minutes, false);
        _pool.moveQuoteToken(1_000 * 1e18, _i9_52, _i9_91, block.timestamp + 1 minutes, false);

        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i9_91,
            lpBalance:   2_000 * 1e18,
            depositTime: _startTime + 100 days + 12.5 hours + 1 hours // time of deposit in _i9_52 from bucket (since deposit in _i9_52 from bucket was done after _i9_91 target bucket become insolvent)
        });

        // ensure bucket bankruptcy when moving amounts from an unbalanced bucket leave bucket healthy
        _assertBucket({
            index:        _i9_72,
            lpBalance:    11_000 * 1e18,
            collateral:   0 * 1e18,
            deposit:      9_565.123570257669797761 * 1e18,
            exchangeRate: 0.869556688205242709 * 1e18
        });

        _pool.moveQuoteToken(10000000000 * 1e18, _i9_72, _i9_91, type(uint256).max, false);

        _assertBucket({
            index:        _i9_72,
            lpBalance:    0,
            collateral:   0 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }

    function testSettleZeroExchangeRateResidualBankruptcy() external tearDown {
        // Borrower2 borrows
        _borrow({
            from:       _borrower2,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        // Skip to make borrower undercollateralized
        skip(100 days);
        // settle should revert on a borrower that is not auctioned
        _assertSettleOnNotKickedAuctionRevert({
            from:     _lender,
            borrower: _borrower2
        });
        
        uint256 kickTime = _startTime + 100 days;

        _kick({
            from:           _lender,
            borrower:       _borrower2,
            debt:           9_853.394241979221645666 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           149.577873638769639523 * 1e18,
            transferAmount: 149.577873638769639523 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2_905.388282461931028480 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853394241979221645 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.394241979221645667 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986593617011217057 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          149.577873638769639523 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          kickTime,
                referencePrice:    11.349172978366918080 * 1e18,
                totalBondEscrowed: 149.577873638769639523 * 1e18,
                auctionPrice:      2.837293244591729520 * 1e18,
                debtInAuction:     9_853.394241979221645667 * 1e18,
                thresholdPrice:    9.853900422492752583 * 1e18,
                neutralPrice:      11.349172978366918080 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              9_853.900422492752583093 * 1e18,
            borrowerCollateral:        1_000 * 1e18,
            borrowert0Np:              11.194764859809874960 * 1e18,
            borrowerCollateralization: 0.986542937133981323 * 1e18
        });

        // add liquidity in same block should be possible as debt was not yet settled / bucket is not yet insolvent
        _addLiquidity({
            from:    _lender1,
            amount:  100 * 1e18,
            index:   _i9_91,
            lpAward: 99.367232491646341844 * 1e18,
            newLup:  9.721295865031779605 * 1e18
        });

        // take entire collateral
        _take({
            from:            _lender,
            borrower:        _borrower2,
            maxCollateral:   1_000 * 1e18,
            bondChange:      43.071075813407140453 * 1e18,
            givenAmount:     2_837.29324459172952 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _assertLenderLpBalance({
            lender:      _lender1,
            index:       _i9_91,
            lpBalance:   99.367232491646341844 * 1e18,
            depositTime: _startTime + 100 days + 10 hours
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              7_059.678253714430204093 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _assertBucket({
            index:        _i9_91,
            lpBalance:    2_099.367232491646341844 * 1e18,
            collateral:   0,
            deposit:      2_112.735939051273346000 * 1e18,
            exchangeRate: 1.006367969525636674 * 1e18
        });

        // LP forfeited when forgive bad debt should be reflected in BucketBankruptcy event
        vm.expectEmit(true, true, false, true);
        emit BucketBankruptcy(_i9_91, 2_099.367232491646341844 * 1e18);
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    10,
            settledDebt: 6_963.271989687033445101 * 1e18
        });

        // bucket is insolvent, balances are resetted
        _assertBucketAssets({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }
}

contract ERC20PoolLiquidationsSettleRegressionTest is ERC20HelperContract {

    address internal actor1;
    address internal actor2;
    address internal actor3;
    address internal actor4;
    address internal actor6;
    address internal actor7;
    address internal actor8;

    function setUp() external {
        _startTest();

        actor1 = makeAddr("actor1");
        _mintQuoteAndApproveTokens(actor1, type(uint256).max);
        _mintCollateralAndApproveTokens(actor1, type(uint256).max);

        actor2 = makeAddr("actor2");
        _mintQuoteAndApproveTokens(actor2, type(uint256).max);
        _mintCollateralAndApproveTokens(actor2, type(uint256).max);

        actor3 = makeAddr("actor3");
        _mintQuoteAndApproveTokens(actor3, type(uint256).max);
        _mintCollateralAndApproveTokens(actor3, type(uint256).max);

        actor4 = makeAddr("actor4");
        _mintQuoteAndApproveTokens(actor4, type(uint256).max);
        _mintCollateralAndApproveTokens(actor4, type(uint256).max);

        actor6 = makeAddr("actor6");
        _mintQuoteAndApproveTokens(actor6, type(uint256).max);
        _mintCollateralAndApproveTokens(actor6, type(uint256).max);

        actor7 = makeAddr("actor7");
        _mintQuoteAndApproveTokens(actor7, type(uint256).max);
        _mintCollateralAndApproveTokens(actor7, type(uint256).max);

        actor8 = makeAddr("actor8");
        _mintQuoteAndApproveTokens(actor8, type(uint256).max);
        _mintCollateralAndApproveTokens(actor8, type(uint256).max);
    }

    function test_regression_bankruptcy_on_hpb_with_tiny_deposit() external {
        // add liquidity to bucket 2572
        changePrank(actor6);
        _pool.addQuoteToken(2_000_000 * 1e18, 2572, block.timestamp + 100, false);
        skip(100 days);

        // borrower 6 draws debt and becomes undercollateralized due to interest accrual
        ERC20Pool(address(_pool)).drawDebt(actor6, 1_000_000 * 1e18, 7388, 372.489032271806320214 * 1e18);
        skip(100 days);

        // borrower 1 kicks borrower 6 and draws debt before auction 6 is settled
        changePrank(actor1);
        _pool.kick(actor6, 7388);
        skip(100 hours);
        ERC20Pool(address(_pool)).drawDebt(actor1, 1_000_000 * 1e18, 7388, 10_066_231_386_838.450530455239517417 * 1e18);
        skip(100 days);

        // another actor kicks borrower 1
        changePrank(actor2);
        _pool.kick(actor1, 7388);
        skip(10 days);

        // attempt to deposit tiny amount into bucket 2571, creating new HPB
        changePrank(actor3);
        vm.expectRevert(abi.encodeWithSignature('AuctionNotCleared()'));
        _pool.addQuoteToken(2, 2571, block.timestamp + 100, false);

        // Previous test added quote token successfully, then settled auction 1, bankrupting bucket 2571.
        // This is not possible because we prevent depositing into bucket when an uncleared auction exists.
    }

    function test_regression_settle_with_reserves() external tearDown {
        changePrank(actor2);
        _addInitialLiquidity({
            from:   actor2,
            amount: 112_807_891_516.8015826259279868 * 1e18,
            index:  2572
        });

        // no reserves
        (uint256 reserves, uint256 claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 0);
        assertEq(claimableReserves, 0);

        _drawDebtNoLupCheck({
            from:               actor2,
            borrower:           actor2,
            amountToBorrow:     56_403_945_758.4007913129639934 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 21_009_851.171858165566322122 * 1e18
        });

        // origination fee goes to reserves
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 54_234_563.229231556141209574 * 1e18);
        assertEq(claimableReserves, 0);

        // skip some time to make actor2 undercollateralized
        skip(200 days);
        ERC20Pool(address(_pool)).updateInterest();
        // check reserves after interest accrual
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 289_462_063.392449001089942144 * 1e18);
        assertEq(claimableReserves, 0);

        // kick actor2
        changePrank(actor4);
        _kick({
            from:           actor4,
            borrower:       actor2,
            debt:           58_026_363_656.051471906282127718 * 1e18,
            collateral:     21_009_851.171858165566322122 * 1e18,
            bond:           880_859_922.734477445997454079 * 1e18,
            transferAmount: 880_859_922.734477445997454079 * 1e18
        });
        // ensure reserves did not increase as result of kick
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 289_462_063.392449001089942144 * 1e18);
        assertEq(claimableReserves, 0);

        changePrank(actor7);
        _drawDebtNoLupCheck({
            from:               actor7,
            borrower:           actor7,
            amountToBorrow:     1_000_000 * 1e18,
            limitIndex:         7388,
            collateralToPledge: 372.489032271806320214 * 1e18
        });

        // skip some time to make actor7 undercollateralized
        skip(200 days);
        (uint256 borrowerDebt, , ) = _poolUtils.borrowerInfo(address(_pool), actor2);
        assertEq(borrowerDebt, 59_474_936_428.593370593619524964 * 1e18);

        // reserves increase slightly due to interest accrual
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 289_462_928.777064385704942145 * 1e18);
        assertEq(claimableReserves, 0);
 
        // settle auction with reserves
        changePrank(actor6);
        _settle({
            from:        actor6,
            borrower:    actor2,
            maxDepth:    2,
            settledDebt: 56_458_180_321.630022869105202974 * 1e18
        });

        // almost all the reserves are used to settle debt
        (reserves, claimableReserves, , ,) = _poolUtils.poolReservesInfo(address(_pool));
        assertEq(reserves, 58.732475079196632424 * 1e18);
        assertEq(claimableReserves, 0);
    }
}

contract ERC20PoolLiquidationSettleFuzzyTest is ERC20FuzzyHelperContract {
    address internal _lender;
    address internal _kicker;
    address internal _borrower;

    uint256[3] internal _buckets = [2550, 2551, 2552];
    function setUp() external {
        _startTest();
        _lender   = makeAddr("lender");
        _kicker   = makeAddr("kicker");
        _borrower = makeAddr("borrower");

        _mintQuoteAndApproveTokens(_lender, 1_000_000 * 1e18);
        _mintQuoteAndApproveTokens(_kicker, 100_000 * 1e18);
        _mintCollateralAndApproveTokens(_borrower, 1_000 * 1e18);

        // lender deposits all liquidity in 3 buckets
        for(uint i = 0; i < 3; i++) {
            _addLiquidity({
                from:    _lender,
                amount:  100_000 * 1e18,
                index:   _buckets[i],
                lpAward: 100_000 * 1e18,
                newLup:  MAX_PRICE
            });

            _assertBucket({
                index:        _buckets[i],
                lpBalance:    100_000 * 1e18,
                collateral:   0,
                deposit:      100_000 * 1e18,
                exchangeRate: 1 * 1e18
            });
        }

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100 * 1e18
        });
        _borrow({
            from:       _borrower,
            amount:     290_000 * 1e18,
            indexLimit: 7_388,
            newLup:     2981.007422784467321543 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              290_278.84615384615398 * 1e18,
            borrowerCollateral:        100 * 1e18,
            borrowert0Np:              3_343.441616215101687356 * 1e18,
            borrowerCollateralization: 1.026946145846449373 * 1e18
        });

        // skip to make borrower undercollateralized
        skip(400 days);

        _kick({
            from:           _kicker,
            borrower:       _borrower,
            debt:           306_628.378237887861419289 * 1e18,
            collateral:     100 * 1e18,
            bond:           4_654.723000803723493401 * 1e18,
            transferAmount: 4_654.723000803723493401 * 1e18
        });
    }

    function testSettleWithDepositFuzzy(uint256 quoteAmount, uint256 bucketIndex) external {
        quoteAmount = bound(quoteAmount, 1 * 1e18, 500_000 * 1e18);
        bucketIndex = bound(bucketIndex, 1, 7388);

        // add some deposits to be used to settle auction
        _addLiquidityNoEventCheck({
            from:   _lender,
            amount: quoteAmount,
            index:  bucketIndex
        });

        // skip some time to make auction settleable
        skip(73 hours);

        (uint256 beforeDebt, uint256 beforeCollateral,) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // settle auction with deposits
        _pool.settle(_borrower, 2);

        (uint256 afterDebt, uint256 afterCollateral,) = _poolUtils.borrowerInfo(address(_pool), _borrower);

        // ensure some borrower debt is settled
        assertLt(afterDebt, beforeDebt);

        // ensure some collateral is used to settle debt
        assertLt(afterCollateral, beforeCollateral);
    }
}
