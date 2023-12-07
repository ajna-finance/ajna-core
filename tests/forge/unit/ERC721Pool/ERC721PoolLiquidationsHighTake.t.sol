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
        _lender            = makeAddr("lender");
        _withdrawRecipient = makeAddr("withdrawRecipient");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](2);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 2;

        _pool = _deploySubsetPool(subsetTokenIds);

       _mintAndApproveQuoteTokens(_lender,    300_000_000_000 * 1e18);
       _mintAndApproveQuoteTokens(_borrower,  100 * 1e18);

       _mintAndApproveCollateralTokens(_borrower,  6);

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000.0 * 1e18,
            index:  1
        });

       // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;
        // tokenIdsToAdd[1] = 3;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     960_550_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });


        skip(100 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              974735101.867470788027259956 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1068969622.822822467761458386 * 1e18,
            borrowerCollateralization: 0.986430865620282143 * 1e18
        });
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
            debt:           974735101.867470788027259955 * 1e18,
            collateral:     1 * 1e18,
            bond:           10897869.739154233968795067 * 1e18,
            transferAmount: 10897869.739154233968795067 * 1e18
        });

        skip(1 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          10897869.739154233968795067 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 1 minutes,
                referencePrice:    1083713799.259013131614151035 * 1e18,
                totalBondEscrowed: 10897869.739154233968795067 * 1e18,
                auctionPrice:      267_980_423_388.530726670632743680 * 1e18,
                debtInAuction:     974735101.867470788027259956 * 1e18,
                thresholdPrice:    974735101.867470788027259955 * 1e18,
                neutralPrice:      1083713799.259013131614151035 * 1e18
            })
        );

        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      10897869739154233968795067,
            givenAmount:     991360820988112808697327591,
            collateralTaken: 3699377769661894,
            isReward:        false
        });

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

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

    }
}