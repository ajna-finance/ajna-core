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

        // borrower deposits one NFTs into the subset pool and borrows
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
            borrowerDebt:              974_735_101.867470788027259956 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1_068_969_622.822822467761458386 * 1e18,
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
            debt:           974_735_101.867470788027259955 * 1e18,
            collateral:     1 * 1e18,
            bond:           10_897_869.739154233968795067 * 1e18,
            transferAmount: 10_897_869.739154233968795067 * 1e18
        });

        skip(1 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          10_897_869.739154233968795067 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 1 minutes,
                referencePrice:    1_083_713_799.259013131614151035 * 1e18,
                totalBondEscrowed: 10_897_869.739154233968795067 * 1e18,
                auctionPrice:      267_980_423_388.530726670632743680 * 1e18,
                debtInAuction:     974_735_101.867470788027259956 * 1e18,
                thresholdPrice:    974_735_101.867470788027259955 * 1e18,
                neutralPrice:      1_083_713_799.259013131614151035 * 1e18
            })
        );

        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      10_897_869.739154233968795067 * 1e18,
            givenAmount:     991_360_820.988112808697327591 * 1e18,
            collateralTaken: 0.003699377769661894 * 1e18,
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

        assertEq(_collateral.ownerOf(1), address(_lender));

    }

    function testTakeMultipleNFTHighPrice() external {

        _addLiquidity({
            from:    _lender,
            amount:  1_000_000_000.0 * 1e18,
            index:   1,
            lpAward: 988_807_719.662757027238723574 * 1e18,
            newLup:  999_969_141.897027226245329498 * 1e18
        });

        // first borrower adds another collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 2;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     947_300_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_922_945_967.252086173079859956 * 1e18,
            borrowerCollateral:        2.000000000000000000 * 1e18,
            borrowert0Np:              1_054_425_362.020877753266911023 * 1e18,
            borrowerCollateralization: 1.000037241461975329 * 1e18
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

        skip(1 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           1_923_209_402.550975799525343720 * 1e18,
            collateral:     2 * 1e18,
            bond:           21_502_134.795353695767188920 * 1e18,
            transferAmount: 21_502_134.795353695767188920 * 1e18
        });

        skip(1 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          21_502_134.795353695767188920 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 1 minutes,
                referencePrice:    1_069_115_375.252256382445035266 * 1e18,
                totalBondEscrowed: 21_502_134.795353695767188920 * 1e18,
                auctionPrice:      264_370_529_476.677939732804056320 * 1e18,
                debtInAuction:     1_923_209_402.550975799525343721 * 1e18,
                thresholdPrice:    961_604_701.275487899762671860 * 1e18,
                neutralPrice:      1_069_115_375.252256382445035266 * 1e18
            })
        );

        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1 * 1e18,
            bondChange:      21_502_134.795353695767188920 * 1e18,
            givenAmount:     1_956_012_919.399533593528919134 * 1e18,
            collateralTaken: 0.007398755539323788 * 1e18,
            isReward:        false
        });

        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(2), address(_lender));

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
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

    }

    function testLenderKickTakeHighPrice() external {

        _addLiquidity({
            from:    _lender,
            amount:  1_000_000_000.0 * 1e18,
            index:   1,
            lpAward: 988_807_719.662757027238723574 * 1e18,
            newLup:  999_969_141.897027226245329498 * 1e18
        });

        // first borrower adds another collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 2;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     947_300_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_922_945_967.252086173079859956 * 1e18,
            borrowerCollateral:        2.000000000000000000 * 1e18,
            borrowert0Np:              1_054_425_362.020877753266911023 * 1e18,
            borrowerCollateralization: 1.000037241461975329 * 1e18
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

        skip(1 days);

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_180_947.482590772745713575 * 1e18,
            exchangeRate: 1.011272786422610071 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days
        });

        _lenderKick({
            from:       _lender,
            index:      1,
            borrower:   _borrower,
            debt:       1_923_209_402.550975799525343720 * 1e18,
            collateral: 2.00000000000000000 * 1e18,
            bond:       21_502_134.795353695767188920 * 1e18
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_041.846142986663199620 * 1e18,
            exchangeRate: 1.011398540211305519 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          21_502_134.795353695767188920 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    1_069_115_375.252256382445035266 * 1e18,
                totalBondEscrowed: 21_502_134.795353695767188920 * 1e18,
                auctionPrice:      273_693_536_064.577633905929028096 * 1e18,
                debtInAuction:     1_923_209_402.550975799525343721 * 1e18,
                thresholdPrice:    961_604_701.275487899762671860 * 1e18,
                neutralPrice:      1_069_115_375.252256382445035266 * 1e18
            })
        );

        skip(1 minutes);

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      21_502_134.795353695767188920 * 1e18,
            givenAmount:     1_956_012_919.399533593528919134 * 1e18,
            collateralTaken: 0.007398755539323788 * 1e18,
            isReward:        false
        });

        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(2), address(_lender));

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
            borrowerCollateral:        1.0 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_215.177575407462265845 * 1e18,
            exchangeRate: 1.011398627366745639 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days - 1 minutes
        });
    }
}