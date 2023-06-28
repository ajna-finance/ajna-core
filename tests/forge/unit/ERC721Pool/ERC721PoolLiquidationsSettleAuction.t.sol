// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721Pool } from 'src/ERC721Pool.sol';

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsSettleAuctionTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](9);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 2;
        subsetTokenIds[2] = 3;
        subsetTokenIds[3] = 4;
        subsetTokenIds[4] = 5;
        subsetTokenIds[5] = 6;
        subsetTokenIds[6] = 51;
        subsetTokenIds[7] = 53;
        subsetTokenIds[8] = 73;
        _pool = _deploySubsetPool(subsetTokenIds);

       _mintAndApproveQuoteTokens(_lender,    120_000 * 1e18);
       _mintAndApproveQuoteTokens(_borrower,  100 * 1e18);
       _mintAndApproveQuoteTokens(_borrower2, 8_000 * 1e18);

       _mintAndApproveCollateralTokens(_borrower,  6);
       _mintAndApproveCollateralTokens(_borrower2, 74);

        // Lender adds Quote token in one bucket
        _addInitialLiquidity({
            from:   _lender,
            amount: 8_000 * 1e18,
            index:  2500
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  2501
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 2_000 * 1e18,
            index:  2502
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  2503
        });

        // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        // borrower deposits two NFTs into the subset pool and borrows
        _drawDebtNoLupCheck({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 5_000 * 1e18,
            limitIndex:     5000,
            tokenIds:       tokenIdsToAdd
        });

        // second borrower deposits three NFTs into the subset pool and borrows
        tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 51;
        tokenIdsToAdd[1] = 53;
        tokenIdsToAdd[2] = 73;
        // borrower deposits two NFTs into the subset pool and borrows
        _drawDebtNoLupCheck({
            from:           _borrower2,
            borrower:       _borrower2,
            amountToBorrow: 5_000 * 1e18,
            limitIndex:     5000,
            tokenIds:       tokenIdsToAdd
        });

        // skip time to accumulate interest
        skip(5100 days);

        // kick both loans
        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower,
            debt:       10_190.456508610307854461 * 1e18,
            collateral: 2 * 1e18,
            bond:       100.646484035657361526 * 1e18
        });
        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower2,
            debt:       10_203.037319114765024653 * 1e18,
            collateral: 3 * 1e18,
            bond:       1_325.327386341314188042 * 1e18
        });
    }

    function testSettlePartialDebtSubsetPool() external tearDown {
        _assertBucket({
            index:        2500,
            lpBalance:    8_000 * 1e18,
            collateral:   0,
            deposit:      13_293.371821008415088000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  5_000 * 1e18,
            index:   2499
        });

        // adding more liquidity to settle all auctions
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2500
        });

        // lender adds liquidity in min bucket to and merge / remove the other NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX
        });

        // skip to make loans clearable
        skip(80 hours);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_195.576288428866513838 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.757907990596315111 * 1e18
        });

        // first settle call settles partial borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 2_485.576684127234225434 * 1e18
        });

        // collateral in bucket used to settle auction increased with the amount used to settle debt
        _assertBucket({
            index:        2499,
            lpBalance:    5_000 * 1e18,
            collateral:   1.287929788232333535 * 1e18,
            deposit:      0,
            exchangeRate: 1.000199226172731231 * 1e18
        });
        // partial borrower debt is settled, borrower collateral decreased with the amount used to settle debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_194.580157565210366847 * 1e18,
            borrowerCollateral:        0.712070211767666465 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.529627631336027971 * 1e18
        });

        _assertCollateralInvariants();

        // 1 token id (token id 3, the most recent pledged token) was moved from borrower token ids array to pool claimable token ids array after partial bad debt settle
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 1);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);

        // all NFTs are owned by the pool
        assertEq(_collateral.ownerOf(1),  address(_pool));
        assertEq(_collateral.ownerOf(3),  address(_pool));
        assertEq(_collateral.ownerOf(51), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));
        assertEq(_collateral.ownerOf(73), address(_pool));

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 2_258.399659496838434005 * 1e18
        });

        // no token id left in borrower token ids array
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 0);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 2);
        // tokens used to settle entire bad debt (settle auction) are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    20_036.073477395793018984 * 1e18,
            collateral:   0.712070211767666465 * 1e18,
            deposit:      30_548.811547417239049073 * 1e18,
            exchangeRate: 1.662002526074875972 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              650.665648223383091746 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 323.391444837465804436 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1.0 * 1e18
        });

        _assertCollateralInvariants();

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_073.623798076923079263 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    20_036.073477395793018984 * 1e18,
            collateral:   3.354170784195916811 * 1e18,
            deposit:      19_689.982479544706885705 * 1e18,
            exchangeRate: 1.629527817447087792 * 1e18
        });
        _assertBucket({
            index:        2499,
            lpBalance:    5_000 * 1e18,
            collateral:   1.287929788232333535 * 1e18,
            deposit:      0,
            exchangeRate: 1.000199226172731231 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    99.984931542573546395 * 1e18,
            collateral:   0.357899427571749654 * 1e18,
            deposit:      100.004851122084218862 * 1e18,
            exchangeRate: 1.000199226172731231 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              1_769.243311298076895206 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(2), 73);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(3), 53);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(4), 51);

        // lender can claim 1 NFTs from bucket 2499
        changePrank(_lender);
        _pool.removeCollateral(1, 2499);

        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2499;
        removalIndexes[1] = 2500;
        removalIndexes[2] = MAX_FENWICK_INDEX;

        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 3 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(1),  address(_pool));
        assertEq(_collateral.ownerOf(3),  address(_pool));
        assertEq(_collateral.ownerOf(73), _lender);
        assertEq(_collateral.ownerOf(51), _lender);
        assertEq(_collateral.ownerOf(53), _lender);

        _assertBucket({
            index:        2500,
            lpBalance:    15_976.708867181974059418 * 1e18,
            collateral:   1.642100572428250346 * 1e18,
            deposit:      19_689.982479544706885705 * 1e18,
            exchangeRate: 1.629527817447087792 * 1e18
        });
        _assertBucket({
            index:        2499,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    99.984931542573546395 * 1e18,
            collateral:   0.357899427571749654 * 1e18,
            deposit:      100.004851122084218862 * 1e18,
            exchangeRate: 1.000199226172731231 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              1_769.243311298076895206 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        uint256[] memory removalIndexes2 = new uint256[](2);
        removalIndexes2[0] = 2500;
        removalIndexes2[1] = MAX_FENWICK_INDEX;

        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes2,
            toIndexLps:              0
        });

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      3_323.342955252103772000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(32 hours);
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  3_000 * 1e18,
            index:   2502
        });

        _depositTake({
            from:     _lender,
            borrower: _borrower,
            index:    2502
        });

        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4_582.063964428011899646 * 1e18,
            borrowerCollateral:        0.330122111965997525 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.276978254692862222 * 1e18
        });

        _assertCollateralInvariants();

        // borrower tries to repay remaining debt
        _repayDebtNoLupCheck({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    1000 * 1e18,
            amountRepaid:     0,
            collateralToPull: 0
        });

        skip(80 hours);

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    2,
            settledDebt: 2_278.046992473852091989 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    8_000 * 1e18,
            collateral:   0.330122111965997525 * 1e18,
            deposit:      11_222.172625306604949654 * 1e18,
            exchangeRate: 1.562206295682965556 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        // _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        // lender merge / removes the other 2 NFTs
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2502;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2502,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(1), _lender);
        assertEq(_collateral.ownerOf(3), _lender);

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleByPledgeSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before bucket take
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 2);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 0);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(32 hours);
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  3_000 * 1e18,
            index:   2502
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  1.669877888034002475 * 1e18,
            quoteTokenAmount: 6_387.793369052686121698 * 1e18,
            bondChange:       63.877933690526861217 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    38.435354287866834063 * 1e18
        });

        // after bucket take, token id 3 is moved to pool claimable array (the most recent pledged)
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 1);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4_582.063964428011899646 * 1e18,
            borrowerCollateral:        0.330122111965997525 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.276978254692862222 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     10_205.087450363250041380 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });

        // borrower exits from auction by pledging more collateral
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 5;
        _drawDebtNoLupCheck({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 0,
            limitIndex:     0,
            tokenIds:       tokenIdsToAdd
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4_582.063964428011899646 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              801.113192353304652349 * 1e18,
            borrowerCollateralization: 2.529637996454456058 * 1e18
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
                totalBondEscrowed: 1_425.973870376971549568 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    1_527.354654809337299882 * 1e18,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // after settle borrower has 3 token ids (token id 1 saved from auction + pledged token ids 2 and 4)
        // most recent token pledged 5 is used to settle the auction hence in pool claimable array 
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 3);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 2);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 2);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 2), 4);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 5);

        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBucket({
            index:        6051,
            lpBalance:    0.000025941052120484 * 1e18,
            collateral:   0.330122111965997525 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999991014 * 1e18
        });

        // lender adds liquidity in bucket 6051 and merge / removes the other 2 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   6051
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2502;
        removalIndexes[1] = 6051;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6051,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // borrower repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * 1e18,
            amountRepaid:     4_582.063964428011899646 * 1e18,
            collateralToPull: 3,
            newLup:           MAX_PRICE
        });
        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000025941052120483 * 1e18,
            index:    6051,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000025941052120484 * 1e18
        });

        // the 3 NFTs pulled from pool are owned by borrower
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(2), _borrower);
        assertEq(_collateral.ownerOf(4), _borrower);
        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(5), _lender);

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleByRepaySubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before bucket take
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(32 hours);
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  3_000 * 1e18,
            index:   2502
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  1.669877888034002475 * 1e18,
            quoteTokenAmount: 6_387.793369052686121698 * 1e18,
            bondChange:       63.877933690526861217 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    38.435354287866834063 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4_582.063964428011899646 * 1e18,
            borrowerCollateral:        0.330122111965997525 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.276978254692862222 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     10_205.087450363250041380 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });
        // borrower exits from auction by repaying the debt
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5_000 * 1e18,
            amountRepaid:     4_582.063964428011899646 * 1e18,
            collateralToPull: 0,
            newLup:           MAX_PRICE
        });

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
                kickMomp:          0,
                totalBondEscrowed: 1_425.973870376971549568 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2502,
            lpBalance:    3_843.535428786683406029 * 1e18,
            collateral:   1.669877888034002475 * 1e18,
            deposit:      0,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBucket({
            index:        6051,
            lpBalance:    0.000025941052120484 * 1e18,
            collateral:   0.330122111965997525 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999991014 * 1e18
        });

        // lender adds liquidity in bucket 6051 and merge / removes the other 2 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   6051
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2502;
        removalIndexes[1] = 6051;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6051,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000025941052120483 * 1e18,
            index:    6051,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000025941052120484 * 1e18
        });

    }

    function testDepositTakeAndSettleByRegularTakeSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before bucket take
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      3_323.342955252103772000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(4 hours);
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   2000
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.021378186081598093 * 1e18,
            quoteTokenAmount: 999.9999999999999908 * 1e18,
            bondChange:       9.999999999999999908 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBucket({
            index:        2000,
            lpBalance:    1_000 * 1e18,
            collateral:   0.021378186081598093 * 1e18,
            deposit:      9203,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              9_904.062307087997104829 * 1e18,
            borrowerCollateral:        1.978621813918401907 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.760412964078541435 * 1e18
        });

        _assertCollateralInvariants();

        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 5_425.973870376971549568 * 1e18);

        // borrower exits from auction by regular take
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      90.646484035657361618 * 1e18,
            givenAmount:     9_904.062307087997104828 * 1e18,
            collateralTaken: 0.468592638026133319 * 1e18,
            isReward:        false
        });

        assertEq(_quote.balanceOf(_borrower),      16_331.699340400048807627 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 15_330.036177464968654396 * 1e18);

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     10_203.293562995691294053 * 1e18,
            collateralToPull: 3,
            newLup:           MAX_PRICE
        });

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
                kickMomp:          0,
                totalBondEscrowed: 1_325.327386341314188042 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // remaining token is moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 1);

        _assertBucket({
            index:        2000,
            lpBalance:    1_000 * 1e18,
            collateral:   0.021378186081598093 * 1e18,
            deposit:      9203,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        2159,
            lpBalance:    20_712.867160884608174886 * 1e18,
            collateral:   0.978621813918401907 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000001 * 1e18
        });

        // lender adds liquidity in bucket 2159 and merge / removes remaining NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2159
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2000
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2159;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2159,
            noOfNFTsToRemove:        1,
            collateralMerged:        1 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs (one taken, one claimed) are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   20_712.867160884608174886 * 1e18,
            index:    2159,
            newLup:   MAX_PRICE,
            lpRedeem: 20_712.867160884608174886 * 1e18
        });
    }

    function testDepositTakeAndSettleByBucketTakeSubsetPool() external tearDown {
        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      3_323.342955252103772000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  0.877705109111459100 * 1e18,
            quoteTokenAmount: 3_357.490338749655817817 * 1e18,
            bondChange:       33.574903387496558178 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    20.202020202020202017 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_020.202020202020202017 * 1e18,
            collateral:   0.877705109111459100 * 1e18,
            deposit:      362,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              7_582.063964428011900489 * 1e18,
            borrowerCollateral:        1.122294890888540900 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.563403610033938441 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     10_205.087450363250041380 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });

        // borrower exits from auction by bucket take: lender adds quote token at a higher priced bucket and calls deposit take
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2000
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.163728054862748873 * 1e18,
            quoteTokenAmount: 7_658.650469119203939887 * 1e18,
            bondChange:       76.586504691192039399 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    76.586504691192039399 * 1e18
        });

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
                kickMomp:          0,
                totalBondEscrowed: 1_425.973870376971549568 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2000,
            lpBalance:    40_076.586504691192039399 * 1e18,
            collateral:   0.163728054862748873 * 1e18,
            deposit:      32_417.936035571988099513 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        6051,
            lpBalance:    0.000075324346213057 * 1e18,
            collateral:   0.958566836025792027 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999996900 * 1e18
        });

        // lender adds liquidity in bucket 6051 and merge / removes the other 2 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   6051
        });
        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 6051;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6051,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000075324346213056 * 1e18,
            index:    6051,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000075324346213057 * 1e18
        });
    }

    function testDepositTakeAndSettleBySettleSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      3_323.342955252103772000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_190.456508610307854462 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.747027241552026434 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  0.877705109111459100 * 1e18,
            quoteTokenAmount: 3_357.490338749655817817 * 1e18,
            bondChange:       33.574903387496558178 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    20.202020202020202017 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_020.202020202020202017 * 1e18,
            collateral:   0.877705109111459100 * 1e18,
            deposit:      362,
            exchangeRate: 1.661957717681079631 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              7_582.063964428011900489 * 1e18,
            borrowerCollateral:        1.122294890888540900 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.563403610033938441 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    11_000 * 1e18,
            amountRepaid:     10_205.087450363250041380 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });

        skip(72 hours);

        // borrower exits from auction by pool debt settle
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 3_769.545371910961412793 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
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
                kickMomp:          0,
                totalBondEscrowed: 1_425.973870376971549568 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    8_000 * 1e18,
            collateral:   1.122294890888540900 * 1e18,
            deposit:      8_218.389542394611030535 * 1e18,
            exchangeRate: 1.569318637591693583 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    2_020.202020202020202017 * 1e18,
            collateral:   0.877705109111459100 * 1e18,
            deposit:      362,
            exchangeRate: 1.661957717681079631 * 1e18
        });

        // lender merge / removes the other 2 NFTs
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2502;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2502,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        _assertCollateralInvariants();
    }
}
