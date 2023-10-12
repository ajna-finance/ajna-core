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
            debt:       10_064.648403565736152554 * 1e18,
            collateral: 2 * 1e18,
            bond:       152.784783614301553735 * 1e18
        });
        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower2,
            debt:       10_064.648403565736152554 * 1e18,
            collateral: 3 * 1e18,
            bond:       152.784783614301553735 * 1e18
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
            borrowerDebt:              10_069.704976226041001321 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_882.277255357846282204 * 1e18,
            borrowerCollateralization: 0.767381840478769050 * 1e18
        });

        // first settle call settles partial borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 2_485.570270210405357279 * 1e18
        });

        // collateral in bucket used to settle auction increased with the amount used to settle debt
        _assertBucket({
            index:        2499,
            lpBalance:    5_000 * 1e18,
            collateral:   1.287926464788484107 * 1e18,
            deposit:      0,
            exchangeRate: 1.000196645204423177 * 1e18
        });
        // partial borrower debt is settled, borrower collateral decreased with the amount used to settle debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_068.721750203925124024 * 1e18,
            borrowerCollateral:        0.712073535211515893 * 1e18,
            borrowert0Np:              4_074.953051699645482676 * 1e18,
            borrowerCollateralization: 0.542781032548108438 * 1e18
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
            settledDebt: 2_127.089747762669017517 * 1e18
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
            collateral:   0.712073535211515893 * 1e18,
            deposit:      30_548.712777641352242710 * 1e18,
            exchangeRate: 1.661998237353453822 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              789.003620205433623214 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 392.147674334617935204 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

        _assertCollateralInvariants();

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_004.807692307692310000 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    20_036.073477395793018984 * 1e18,
            collateral:   3.318337971638889847 * 1e18,
            deposit:      19_690.004181209877611641 * 1e18,
            exchangeRate: 1.622619083494012841 * 1e18
        });
        _assertBucket({
            index:        2499,
            lpBalance:    5_000 * 1e18,
            collateral:   1.287926464788484107 * 1e18,
            deposit:      0,
            exchangeRate: 1.000196645204423177 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    99.984931546150681783 * 1e18,
            collateral:   0.393735563572626046 * 1e18,
            deposit:      100.004593064144716734 * 1e18,
            exchangeRate: 1.000196645204423177 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
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
            lpBalance:    15_959.417125063160793398 * 1e18,
            collateral:   1.606264436427373954 * 1e18,
            deposit:      19_690.004181209877611641 * 1e18,
            exchangeRate: 1.622619083494012841 * 1e18
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
            lpBalance:    99.984931546150681783 * 1e18,
            collateral:   0.393735563572626046 * 1e18,
            deposit:      100.004593064144716734 * 1e18,
            exchangeRate: 1.000196645204423177 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
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
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_882.277255357846282204 * 1e18,
            borrowerCollateralization: 0.756365082071426765 * 1e18
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
            lpBalance:    3_863.757250427550337858 * 1e18,
            collateral:   1.678659796633077181 * 1e18,
            deposit:      0.000000000000002754 * 1e18,
            exchangeRate: 1.661954009450878778 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              3_742.762708953482933471 * 1e18,
            borrowerCollateral:        0.321340203366922819 * 1e18,
            borrowert0Np:              6_669.712537943716399889 * 1e18,
            borrowerCollateralization: 0.330069182462081655 * 1e18
        });

        _assertCollateralInvariants();

        skip(80 hours);

        // settle auction 1
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    2,
            settledDebt: 1_860.774838340588348583 * 1e18
        });
        _assertBucket({
            index:        2500,
            lpBalance:    8_000 * 1e18,
            collateral:   0.321340203366922819 * 1e18,
            deposit:      11_084.202409928441579151 * 1e18,
            exchangeRate: 1.540718736319969120 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    3_863.757250427550337858 * 1e18,
            collateral:   1.678659796633077181 * 1e18,
            deposit:      0.000000000000002755 * 1e18,
            exchangeRate: 1.661954009450878778 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        // settle auction 2 to enable mergeOrRemoveCollateral
        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    2,
            settledDebt: 5_004.80769230769231 * 1e18
        });
        _assertCollateralInvariants();

        // collateral in buckets:
        // 2500 - 2.928128325437681102
        // 2502 - 1.678659796633077182
        // 7388 - 0.393211877929241716

        // lender deposits quote token into 7388 to merge from that bucket
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1 * 1e18,
            index:   7388
        });

        // lender merge / removes available NFTs
        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 7388;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 7388,
            noOfNFTsToRemove:        5,
            collateralMerged:        5 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(1),  _lender);
        assertEq(_collateral.ownerOf(51), _lender);
        assertEq(_collateral.ownerOf(53), _lender);
        assertEq(_collateral.ownerOf(73), _lender);

        _assertCollateralInvariants();
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
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_882.277255357846282204 * 1e18,
            borrowerCollateralization: 0.756365082071426765 * 1e18
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
            quoteTokenAmount: 999.999999999999990800 * 1e18,
            bondChange:       15.180339887498947860 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBucket({
            index:        2000,
            lpBalance:    1_000 * 1e18,
            collateral:   0.021378186081598093 * 1e18,
            deposit:      0.000000000000009201 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              9_087.671681713557968897 * 1e18,
            borrowerCollateral:        1.978621813918401907 * 1e18,
            borrowert0Np:              2_630.547032872719470290 * 1e18,
            borrowerCollateralization: 0.832868255733566506 * 1e18
        });

        _assertCollateralInvariants();

        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 4_305.569567228603107470 * 1e18);

        // borrower exits from auction by regular take
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      137.604443726802605875 * 1e18,
            givenAmount:     9_299.424314491640485936 * 1e18,
            collateralTaken: 0.802193429456335794 * 1e18,
            isReward:        false
        });

        assertEq(_quote.balanceOf(_borrower),      7_393.071925217111242444 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 13_604.993881720243593406 * 1e18);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
        // auction 2 still ongoing
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 152.784783614301553735 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10064.901171882309537906 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // remaining token is moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 1);

        // buckets with collateral
        // 2000 - 0.021876321065491412
        // 2279 - 0.978123678934508588
        _assertBucket({
            index:        2000,
            lpBalance:    1_000 * 1e18,
            collateral:   0.021378186081598093 * 1e18,
            deposit:      0.000000000000009201 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        2279,
            lpBalance:    11_384.469793445698921143 * 1e18,
            collateral:   0.978621813918401907 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 2159 and merge / removes remaining NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2279
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2000
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2279;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2279,
            noOfNFTsToRemove:        1,
            collateralMerged:        1 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs (one taken, one claimed) are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // ensure no collateral in buckets
        _assertBucket({
            index:        2000,
            lpBalance:    40_000.000000000000009178 * 1e18,
            collateral:   0,
            deposit:      40_000.000000000000009201 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        2279,
            lpBalance:    40_000.000000000000000001 * 1e18,
            collateral:   0,
            deposit:      40_000.000000000000000000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   11_384.469793445698921142 * 1e18,
            index:    2279,
            newLup:   _priceAt(2000),
            lpRedeem: 11_384.469793445698921143 * 1e18
        });

        // borrower2 exits from auction by deposit take
        skip(3 hours);
        _assertBucket({
            index:        2500,
            lpBalance:    8_000.000000000000000000 * 1e18,
            collateral:   0 * 1e18,
            deposit:      13_293.654327999447280000 * 1e18,
            exchangeRate: 1.661706790999930910 * 1e18
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2500,
            collateralArbed:  2.645225595891871889 * 1e18,
            quoteTokenAmount: 10_220.237430207183199580 * 1e18,
            bondChange:       155.146677921483848824 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    93.365678971373374698 * 1e18
        });
        _assertCollateralInvariants();
        _assertBorrower({
            borrower:                  _borrower2,
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
                totalBondEscrowed: 152.784783614301553735 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        // lender removes collateral
        _assertBucket({
            index:        2500,
            lpBalance:    8_093.365678971373374698 * 1e18,
            collateral:   2.645225595891871889 * 1e18,
            deposit:      3_228.588863672794087920 * 1e18,
            exchangeRate: 1.661709951994811681 * 1e18
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2569
        });
        _assertBucket({
            index:        2569,
            lpBalance:    10_971.610695426638179656 * 1e18,
            collateral:   0.354774404108128111 * 1e18,
            deposit:      10_000.000000000000000000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2569;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2569,
            noOfNFTsToRemove:        3,
            collateralMerged:        3 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });
        _assertBucket({
            index:        2500,
            lpBalance:    1_942.931652901886597757 * 1e18,
            collateral:   0,
            deposit:      3_228.588863672794087920 * 1e18,
            exchangeRate: 1.661709951994811681 * 1e18
        });
        _assertBucket({
            index:        2569,
            lpBalance:    10_000.000000000000000004 * 1e18,
            collateral:   0,
            deposit:      10_000.000000000000000000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // borrower 2 redeems LP for quote token
        _removeAllLiquidity({
            from:     _borrower2,
            amount:   971.610695426638179651 * 1e18,
            index:    2569,
            newLup:   MAX_PRICE,
            lpRedeem: 971.610695426638179652 * 1e18
        });
    }

    function testDepositTakeAndSettleByBucketTakeSubsetPool() external tearDown {
        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        // 1 token id is owned by borrower 2 before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower2, 2), 73);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      3_323.342955252103772000 * 1e18,
            exchangeRate: 1.661671477626051886 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_882.277255357846282204 * 1e18,
            borrowerCollateralization: 0.756365082071426765 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  0.882320037286956004 * 1e18,
            quoteTokenAmount: 3_375.143849709550192592 * 1e18,
            bondChange:       51.235830807792639427 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    30.828669455613465562 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_030.828669455613465562 * 1e18,
            collateral:   0.882320037286956004 * 1e18,
            deposit:      0.000000000000000834 * 1e18,
            exchangeRate: 1.661954009450878778 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              6_742.762708953482931550 * 1e18,
            borrowerCollateral:        1.117679962713043996 * 1e18,
            borrowert0Np:              3_454.620119359940588354 * 1e18,
            borrowerCollateralization: 0.630927812552385529 * 1e18
        });

        _assertCollateralInvariants();

        // borrowers exits from auction by bucket take: lender adds quote token at a higher priced bucket and calls deposit take
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  60_000 * 1e18,
            index:   2000
        });

        // bucket take on borrower
        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.146369981971725896 * 1e18,
            quoteTokenAmount: 6_846.697910339464805069 * 1e18,
            bondChange:       103.935201385981873520 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    103.935201385981873519 * 1e18
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
                referencePrice:    0,
                totalBondEscrowed: 305.569567228603107470 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_066.670727855240484714 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5476,
            lpBalance:    0.001343248402621047 * 1e18,
            collateral:   0.971309980741318100 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000249 * 1e18
        });

        // bucket take on borrower 2
        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.218524435242978009 * 1e18,
            quoteTokenAmount: 10_221.841760049014997661 * 1e18,
            bondChange:       155.171032193774512947 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    155.171032193774512946 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
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
                totalBondEscrowed: 305.569567228603107470 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5557,
            lpBalance:    0.000721544103807183 * 1e18,
            collateral:   0.781475564757021991 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999669 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(2), 73);

        _assertBucket({
            index:        2000,
            lpBalance:    60_259.106233579756386465 * 1e18,
            collateral:   0.364894417214703905 * 1e18,
            deposit:      43_190.566563191276548531 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });

        // lender adds liquidity in bucket 6171 and 6252 and merge / removes the other 3 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   5476
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   5557
        });
        uint256[] memory removalIndexes = new uint256[](4);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 5476;
        removalIndexes[3] = 5557;

        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6252,
            noOfNFTsToRemove:        3,
            collateralMerged:        3 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 3 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);
        assertEq(_collateral.ownerOf(73), _lender);

        _assertCollateralInvariants();

        // remove lps for both borrower and borrower 2
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.001343248402621047 * 1e18,
            index:    5476,
            newLup:   MAX_PRICE,
            lpRedeem: 0.001343248402621047 * 1e18
        });

        _removeAllLiquidity({
            from:     _borrower2,
            amount:   0.000721544103807182 * 1e18,
            index:    5557,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000721544103807183 * 1e18
        });
    }
}
