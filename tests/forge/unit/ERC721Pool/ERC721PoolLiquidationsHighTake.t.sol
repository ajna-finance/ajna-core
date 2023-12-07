// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import { NFTNoopTakeExample } from "../../interactions/NFTTakeExample.sol";

import 'src/libraries/helpers/PoolHelper.sol';
import '@std/console.sol';

contract ERC721PoolLiquidationsTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _withdrawRecipient;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _borrower2         = makeAddr("borrower2");
        _borrower3         = makeAddr("borrower3");
        _lender            = makeAddr("lender");
        _withdrawRecipient = makeAddr("withdrawRecipient");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](17);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 6;
        subsetTokenIds[4] = 7;
        subsetTokenIds[5] = 8;
        subsetTokenIds[6] = 9;
        subsetTokenIds[7] = 10;
        subsetTokenIds[8] = 11;
        subsetTokenIds[9] = 12;
        subsetTokenIds[10] = 13;
        subsetTokenIds[11] = 14;
        subsetTokenIds[12] = 15;
        subsetTokenIds[13] = 51;
        subsetTokenIds[14] = 53;
        subsetTokenIds[15] = 73;
        subsetTokenIds[16] = 76;

        _pool = _deploySubsetPool(subsetTokenIds);

       _mintAndApproveQuoteTokens(_lender,    1_000_000 * 1e18);
       _mintAndApproveQuoteTokens(_borrower,  100 * 1e18);
       _mintAndApproveQuoteTokens(_borrower2, 8_000 * 1e18);

       _mintAndApproveCollateralTokens(_borrower,  6);
       _mintAndApproveCollateralTokens(_borrower2, 68);
       _mintAndApproveCollateralTokens(_borrower3, 2);

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  1
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 5_000 * 1e18,
            index:  1
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 11_000 * 1e18,
            index:  8
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 25_000 * 1e18,
            index:  10
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000 * 1e18,
            index:  12
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 30_000.0 * 1e18,
            index:  _i9_91
        });

       // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     70_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     946585655.625225796879504875 * 1e18
        });

        // second borrower deposits three NFTs into the subset pool and borrows
        tokenIdsToAdd = new uint256[](12);
        tokenIdsToAdd[0] = 7;
        tokenIdsToAdd[1] = 8;
        tokenIdsToAdd[2] = 9;
        tokenIdsToAdd[3] = 10;
        tokenIdsToAdd[4] = 11;
        tokenIdsToAdd[5] = 12;
        tokenIdsToAdd[6] = 13;
        tokenIdsToAdd[7] = 14;
        tokenIdsToAdd[8] = 15;
        tokenIdsToAdd[9] = 51;
        tokenIdsToAdd[10] = 53;
        tokenIdsToAdd[11] = 73;

        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower2,
            amount:     1.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     946_585_655.625225796879504875 * 1e18
        });

        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 76;

        _pledgeCollateral({
            from:     _borrower3,
            borrower: _borrower3,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower3,
            amount:     2_900.0 * 1e18,
            indexLimit: _i9_72,
            newLup:     946_585_655.625225796879504875 * 1e18
        });

        skip(100 days);

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        // _assertPool(
        //     PoolParams({
        //         htp:                  13012.500000000000006000 * 1e18,
        //         lup:                  956075176.822868670011708730 * 1e18,
        //         poolSize:             72_996.666666666666667000 * 1e18,
        //         pledgedCollateral:    5 * 1e18,
        //         encumberedCollateral: 0.000027236995197946 * 1e18,
        //         poolDebt:             25039.052884615384626930 * 1e18,
        //         actualUtilization:    0,
        //         targetUtilization:    1 * 1e18,
        //         minDebtAmount:        1251.952644230769231347 * 1e18,
        //         loans:                2,
        //         maxBorrower:          address(_borrower),
        //         interestRate:         0.05 * 1e18,
        //         interestRateUpdate:   _startTime
        //     })
        // );
        // _assertBorrower({
        //     borrower:                  _borrower,
        //     borrowerDebt:              25024.038461538461550000 * 1e18,
        //     borrowerCollateral:        2 * 1e18,
        //     borrowert0Np:              13910.905507558462180020 * 1e18,
        //     borrowerCollateralization: 73473.596681872712358952 * 1e18
        // });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              71033.738098717354809129 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              38950.535421163694104056 * 1e18,
            borrowerCollateralization: 0.000268485227228161 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              1.014767687124533641 * 1e18,
            borrowerCollateral:        12 * 1e18,
            borrowert0Np:              0.092739370050389747 * 1e18,
            borrowerCollateralization: 112.763795435827766372 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 897_000 * 1e18);
    }


    function testTakeHighPrice() external {

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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           71033.738098717354809128 * 1e18,
            collateral:     2 * 1e18,
            bond:           794.181335423243327069 * 1e18,
            transferAmount: 794.181335423243327069 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          794.181335423243327069 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    39487.775726474894181973 * 1e18,
                totalBondEscrowed: 794.181335423243327069 * 1e18,
                auctionPrice:      10_108_870.585977572910585088 * 1e18,
                debtInAuction:     71033.738098717354809129 * 1e18,
                thresholdPrice:    35516.869049358677404564 * 1e18,
                neutralPrice:      39_487.775726474894181973 * 1e18
            })
        );
    }
}