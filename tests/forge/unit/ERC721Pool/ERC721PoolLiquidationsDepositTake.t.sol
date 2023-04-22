// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsDepositTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;
    address internal _taker;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");
        _taker     = makeAddr("taker");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender,  120_000 * 1e18);
        _mintAndApproveQuoteTokens(_lender2, 120_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 10 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  6);
        _mintAndApproveCollateralTokens(_borrower2, 74);

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
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

        uint256 expectedNewLup = 9.917184843435912074 * 1e18;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     19.8 * 1e18,
            indexLimit: _i9_91,
            newLup:     expectedNewLup
        });

        // second borrower deposits three NFTs into the subset pool and borrows
        tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 51;
        tokenIdsToAdd[1] = 53;
        tokenIdsToAdd[2] = 73;
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower2,
            amount:     15 * 1e18,
            indexLimit: _i9_72,
            newLup:     expectedNewLup
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.909519230769230774 * 1e18,
                lup:                  expectedNewLup,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 3.512434434608473285 * 1e18,
                poolDebt:             34.833461538461538478 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        1.741673076923076924 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.819038461538461548 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.404995192307692312 * 1e18,
            borrowerCollateralization: 1.000773560501591181 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              15.014423076923076930 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.255048076923076925 * 1e18,
            borrowerCollateralization: 1.981531649793150539 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        // Skip to make borrower undercollateralized
        skip(1000 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           23.012828827714740289 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.227287198298417188 * 1e18,
            transferAmount: 0.227287198298417188 * 1e18
        });

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  5.739575714606494647 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_004.346887619919714000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 4.056751649452525709 * 1e18,
                poolDebt:             40.231555971534224231 * 1e18,
                actualUtilization:    0.000477170706006322 * 1e18,
                targetUtilization:    0.786051641950380194 * 1e18,
                minDebtAmount:        4.023155597153422423 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              23.012828827714740289 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.404995192307692312 * 1e18,
            borrowerCollateralization: 0.861883162446546169 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              17.218727143819483942 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.255048076923076925 * 1e18,
            borrowerCollateralization: 1.727860269914713433 * 1e18
        });
    }

    function testDepositTakeNFTAndSettleAuction() external {

        skip(5 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298417188 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 5 hours,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      23.865155821333804736 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.506709959118993144 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );
        assertEq(_poolUtils.momp(address(_pool)), 9.917184843435912074 * 1e18);

        _addLiquidity({
            from:    _lender,
            amount:  15.0 * 1e18,
            index:   _i1505_26,
            lpAward: 15.0 * 1e18,
            newLup:  9.917184843435912074 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              23.013419918237986289 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.404995192307692312 * 1e18,
            borrowerCollateralization: 0.861861025320848319 * 1e18
        });

        // before deposit take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  0.009965031187761219 * 1e18,
            quoteTokenAmount: 14.999999999999999995 * 1e18,
            bondChange:       0.15 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 0.077287198298417188 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    9.624359312514645329 * 1e18,
                neutralPrice:      0
            })
        );
        // borrower is compensated LP for fractional collateral
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       3519,
            lpBalance:   23.737330323739529015 * 1e18,
            depositTime: block.timestamp
        });
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    15 * 1e18,
            collateral:   0.009965031187761219 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              9.624359312514645329 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              8.769696613728507377 * 1e18,
            borrowerCollateralization: 1.030425457052554443 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   15.0 * 1e18,
            depositTime: block.timestamp
        });

        // borrower should be able to repay and pull collateral from the pool
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    10 * 1e18,
            amountRepaid:     10 * 1e18,
            collateralToPull: 1
        });

        // after deposit take and pull: NFT taken remains in pool, the pulled one goes to borrower
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), _borrower);
    }
}
