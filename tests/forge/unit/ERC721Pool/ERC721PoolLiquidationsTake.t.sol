// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import { NFTNoopTakeExample } from "../../interactions/NFTTakeExample.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _withdrawRecipient;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _borrower2         = makeAddr("borrower2");
        _lender            = makeAddr("lender");
        _withdrawRecipient = makeAddr("withdrawRecipient");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        _pool = _deploySubsetPool(subsetTokenIds);

       _mintAndApproveQuoteTokens(_lender,    120_000 * 1e18);
       _mintAndApproveQuoteTokens(_borrower,  100 * 1e18);
       _mintAndApproveQuoteTokens(_borrower2, 8_000 * 1e18);

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
            newLup:     9.917184843435912074 * 1e18
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
            newLup:     9.917184843435912074 * 1e18
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.909519230769230774 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
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
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 1.000773560501591181 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              15.014423076923076930 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.764554510715692564 * 1e18,
            borrowerCollateralization: 1.981531649793150539 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);
    }

    function testTakeCollateralSubsetPool() external tearDown {
        // Skip to make borrower undercollateralized
        skip(1000 days);

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
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           22.728719829841718804 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.345029692224734546 * 1e18,
            transferAmount: 0.345029692224734546 * 1e18
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
                encumberedCollateral: 4.028103499563389533 * 1e18,
                poolDebt:             39.947446973661202747 * 1e18,
                actualUtilization:    0.000477170706006322 * 1e18,
                targetUtilization:    0.786051641950380194 * 1e18,
                minDebtAmount:        3.994744697366120275 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              17.218727143819483943 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.764554510715692564 * 1e18,
            borrowerCollateralization: 1.727860269914713433 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 46_999.654970307775265454 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224734546 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224734546 * 1e18,
                auctionPrice:      3350.914144267400237568 * 1e18,
                debtInAuction:     22.728719829841718805 * 1e18,
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.345029692224734546 * 1e18
        });
        
        skip(5.5 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        // before take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_999.654970307775265454 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119.8 * 1e18);

        // threshold price increases slightly due to interest
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224734546 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 5.5 hours,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224734546 * 1e18,
                auctionPrice:      15.566136492679870612 * 1e18,
                debtInAuction:     22.728719829841718805 * 1e18,
                thresholdPrice:    11.364681001543373706 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.729362003086747412 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872632046785045240 * 1e18
        });

        uint256 snapshot = vm.snapshot();

        /****************************************/
        /* Take partial collateral tokens (1) ***/
        /****************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      0.236299242694081216 * 1e18,
            givenAmount:     15.566136492679870612 * 1e18,
            collateralTaken: 1.0 * 1e18,
            isReward:        false
        });

        // borrower still under liquidation
        _assertPool(
            PoolParams({
                htp:                  5.739737879567360457 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_004.347847014760830891 * 1e18,
                pledgedCollateral:    4 * 1e18,
                encumberedCollateral: 2.494345764818852289 * 1e18,
                poolDebt:             24.736888013150079997 * 1e18,
                actualUtilization:    0.000411524083711660 * 1e18,
                targetUtilization:    0.781984313351887130 * 1e18,
                minDebtAmount:        2.473688801315008000 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              7.517674374447998626 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              7.550178184893434284 * 1e18,
            borrowerCollateralization: 1.319182548946741612 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.108730449530653330 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 5.5 hours,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.108730449530653330 * 1e18,
                auctionPrice:      15.566136492679870612 * 1e18,
                debtInAuction:     7.517674374447998626 * 1e18,
                thresholdPrice:    7.517674374447998626 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertKicker({
            kicker:    address(0),
            claimable: 0,
            locked:    0
        });

        // after take: one NFT pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), address(_pool));

        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_984.088833815095394842 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119.8 * 1e18); // no additional tokens as there is no rounding of collateral taken (1)

        vm.revertTo(snapshot);

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      0.345029692224734546 * 1e18,
            givenAmount:     23.258980855317575086 * 1e18,
            collateralTaken: 1.494203835759460320 * 1e18, // not a rounded collateral, difference of 2 - 1.49 collateral should go to borrower in quote tokens at auction price
            isReward:        false
        });

        _assertPool(
            PoolParams({
                htp:                  5.739737879567360457 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_004.347847014760830891 * 1e18,
                pledgedCollateral:    3.0 * 1e18,
                encumberedCollateral: 1.736300564176668638 * 1e18,
                poolDebt:             17.219213638702081372 * 1e18,
                actualUtilization:    0.000411524083711660 * 1e18,
                targetUtilization:    0.781984313351887130 * 1e18,
                minDebtAmount:        1.721921363870208137 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
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
        _assertKicker({
            kicker:    address(0),
            claimable: 0,
            locked:    0 * 1e18
        });

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_968.522697322415524242 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 127.673292130042166126 * 1e18); // borrower gets quote tokens from the difference of rounded collateral (2) and needed collateral (1.49) at auction price (15.5) = 7.9 additional tokens
    }

    function testTakeCollateralAndSettleSubsetPool() external tearDown {
        // Skip to make borrower undercollateralized
        skip(1000 days);

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
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           22.728719829841718804 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.345029692224734546 * 1e18,
            transferAmount: 0.345029692224734546 * 1e18
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
                encumberedCollateral: 4.028103499563389533 * 1e18,
                poolDebt:             39.947446973661202747 * 1e18,
                actualUtilization:    0.000477170706006322 * 1e18,
                targetUtilization:    0.786051641950380194 * 1e18,
                minDebtAmount:        3.994744697366120275 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              17.218727143819483943 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.764554510715692564 * 1e18,
            borrowerCollateralization: 1.727860269914713433 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 46_999.654970307775265454 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224734546 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224734546 * 1e18,
                auctionPrice:      3_350.914144267400237568 * 1e18,
                debtInAuction:     22.728719829841718805 * 1e18,
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.345029692224734546 * 1e18
        });
        
        skip(10 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        // before take: check quote token balances of taker
        assertEq(_quote.balanceOf(_lender), 46_999.654970307775265454 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224734546 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224734546 * 1e18,
                auctionPrice:      3.272377094011133044 * 1e18,
                debtInAuction:     22.728719829841718805 * 1e18,
                thresholdPrice:    11.364943715527677468 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.729887431055354936 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872611874873280395 * 1e18
        });

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      0.099351593054310196 * 1e18,
            givenAmount:     6.544754188022266088 * 1e18,
            collateralTaken: 2 * 1e18,
            isReward:        true
        });

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // after take: Taker quote token used for buying collateral
        assertEq(_quote.balanceOf(_lender), 46_993.110216119752999366 * 1e18);

        _assertPool(
            PoolParams({
                htp:                  5.739870563397816903 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_004.348631994338166115 * 1e18,
                pledgedCollateral:    3 * 1e18,
                encumberedCollateral: 3.378387824288349781 * 1e18,
                poolDebt:             33.504096526280849753 * 1e18,
                actualUtilization:    0.000371337774626592 * 1e18,
                targetUtilization:    0.778640404875432888 * 1e18,
                minDebtAmount:        3.350409652628084975 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        // Borrower collateral is 0 and some debt is still to be paid
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              16.284484836087399045 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.444381285279044742 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    13.089508376044532178 * 1e18, 
                totalBondEscrowed: 0.444381285279044742 * 1e18,
                auctionPrice:      3.272377094011133044 * 1e18,
                debtInAuction:     16.284484836087399045 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        // kicker bond is locked as auction is not cleared
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.444381285279044742 * 1e18
        });

        // settle auction
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 14.199051019135248430 * 1e18
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
                totalBondEscrowed: 0.444381285279044742 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0.444381285279044742 * 1e18,
            locked:    0
        });

        changePrank(_lender);
        skip(1 minutes);
        // Kicker claims bond + reward and transfer to a different address
        _pool.withdrawBonds(_withdrawRecipient, 0.1 * 1e18);
        assertEq(_quote.balanceOf(_withdrawRecipient), 0.1 * 1e18);

        // Kicker claims remaining bond + reward to his own address
        _pool.withdrawBonds(_lender, type(uint256).max);
        assertEq(_quote.balanceOf(_lender), 46_993.454597405032044108 * 1e18);
    }

    function testTakeCollateralSubsetPoolAndSettleWithDebt() external tearDown {
        // Skip to make borrower undercollateralized
        skip(1000 days);

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
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        }); 

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           22.728719829841718804 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.345029692224734546 * 1e18,
            transferAmount: 0.345029692224734546 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.728719829841718805 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              11.413817931217071277 * 1e18,
            borrowerCollateralization: 0.872656701977127996 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224734546 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224734546 * 1e18,
                auctionPrice:      3_350.914144267400237568 * 1e18,
                debtInAuction:     22.728719829841718805 * 1e18,
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );

        // skip enough time to accumulate debt and take to not settle auction
        skip(50 hours);

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      0.000000000000180719 * 1e18,
            givenAmount:     0.000000000011904838 * 1e18,
            collateralTaken: 1 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224915265 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 50 hours,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224915265 * 1e18,
                auctionPrice:      0.000000000011904838 * 1e18,
                debtInAuction:     22.734558435739539104 * 1e18,
                thresholdPrice:    22.734558435739539104 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.734558435739539104 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              22.827635862422370438 * 1e18,
            borrowerCollateralization: 0.436216294742093726 * 1e18
        });

        // confirm borrower cannot repay while in liquidation
        _assertRepayAuctionActiveRevert(_borrower, 25 * 1e18);

        // confirm borrower cannot recollateralize while in liquidation
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 5;
        _assertPledgeCollateralAuctionActiveRevert(_borrower, tokenIdsToAdd);

        // ensure auction state did not change
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.345029692224915265 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 50 hours,
                referencePrice:    13.089508376044532178 * 1e18,
                totalBondEscrowed: 0.345029692224915265 * 1e18,
                auctionPrice:      0.000000000011904838 * 1e18,
                debtInAuction:     22.734558435739539104 * 1e18,
                thresholdPrice:    22.734558435739539104 * 1e18,
                neutralPrice:      13.089508376044532178 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              22.734558435739539104 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              22.827635862422370438 * 1e18,
            borrowerCollateralization: 0.436216294742093726 * 1e18
        });

        // settle the auction with debt
        skip(22 hours + 1);
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 19.819038461528240952 * 1e18
        });
    }

    function testTakeCollateralWithAtomicSwapSubsetPool() external tearDown {
        // Skip to make borrower undercollateralized
        skip(1000 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           22.728719829841718804 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.345029692224734546 * 1e18,
            transferAmount: 0.345029692224734546 * 1e18
        });

        skip(5.5 hours);

        uint256 initialBalance = 10_000 * 1e18;

        // instantiate a NOOP taker contract which implements IERC721Taker
        NFTNoopTakeExample taker = new NFTNoopTakeExample();
        deal(address(_quote), address(taker), initialBalance);
        changePrank(address(taker));
        _quote.approve(address(_pool), type(uint256).max);

        bytes memory data = abi.encode(address(_pool));
        _pool.take(_borrower, 2, address(taker), data);

        // check that token ids are the same as id pledged by borrower
        assertEq(taker.tokenIdsReceived(0), 3);
        assertEq(taker.tokenIdsReceived(1), 1);

        // check that the amount of quote tokens passed to taker contract is the same as the one deducted from taker balance
        uint256 currentBalance = _quote.balanceOf(address(taker));
        assertEq(initialBalance - taker.quoteAmountDueReceived(), currentBalance);

        // check address received is the address of current ajna pool
        assertEq(taker.poolAddressReceived(), address(_pool));
    }
}