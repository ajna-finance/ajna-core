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
            bond:       112.526190000038609125 * 1e18
        });
        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower2,
            debt:       10_064.648403565736152554 * 1e18,
            collateral: 3 * 1e18,
            bond:       112.526190000038609125 * 1e18
        });
    }

    function testSettlePartialDebtSubsetPool() external tearDown {
        _assertBucket({
            index:        2500,
            lpBalance:    7999.634703196347032000 * 1e18,
            collateral:   0,
            deposit:      13293.006524204762122216 * 1e18,
            exchangeRate: 1.661701692315198699 * 1e18
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
            borrowert0Np:              2782.181101511692436004 * 1e18,
            borrowerCollateralization: 0.737867154306508702 * 1e18
        });

        // first settle call settles partial borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 2485.445445980762364312 * 1e18
        });

        // collateral in bucket used to settle auction increased with the amount used to settle debt
        _assertBucket({
            index:        2499,
            lpBalance:    4999.748858447488585000 * 1e18,
            collateral:   1.287861785696232799 * 1e18,
            deposit:      0,
            exchangeRate: 1.000196653963394216 * 1e18
        });
        // partial borrower debt is settled, borrower collateral decreased with the amount used to settle debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5068.972897349563013267 * 1e18,
            borrowerCollateral:        0.712138214303767201 * 1e18,
            borrowert0Np:              3933.275103347858307094 * 1e18,
            borrowerCollateralization: 0.521926384043273437 * 1e18
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
            settledDebt: 1_369.922338567221579743 * 1e18
        });

        // no token id left in borrower token ids array
        assertEq(ERC721Pool(address(_pool)).totalBorrowerTokens(_borrower), 0);
        assertEq(ERC721Pool(address(_pool)).totalBucketTokens(), 2);
        // tokens used to settle entire bad debt (settle auction) are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    20034.884788261831319325 * 1e18,
            collateral:   0.712138214303767201 * 1e18,
            deposit:      30547.093039196991134852 * 1e18,
            exchangeRate: 1.662028472538971359 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              2_312.680420634460396298 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 1_149.439907759708365945 * 1e18
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
            lpBalance:    20_034.884788261831319325 * 1e18,
            collateral:   3.318402650731141155 * 1e18,
            deposit:      18164.707642336489729783 * 1e18,
            exchangeRate: 1.546595793735176658 * 1e18
        });
        _assertBucket({
            index:        2499,
            lpBalance:    4999.748858447488585000 * 1e18,
            collateral:   1.287861785696232799 * 1e18,
            deposit:      0,
            exchangeRate: 1.000196653963394216 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    99.994977208251138039 * 1e18,
            collateral:   0.393735563572626046 * 1e18,
            deposit:      100.014641577529559813 * 1e18,
            exchangeRate: 1.000196653963394217 * 1e18
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
            lpBalance:    15757.677829213243231010 * 1e18,
            collateral:   1.606264436427373954 * 1e18,
            deposit:      18164.707642336489729783 * 1e18,
            exchangeRate: 1.546595793735176658 * 1e18
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
            lpBalance:    99.994977208251138039 * 1e18,
            collateral:   0.393735563572626046 * 1e18,
            deposit:      100.014641577529559813 * 1e18,
            exchangeRate: 1.000196653963394217 * 1e18
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

    function testDepositTakeAndSettleSubsetPool() external {
        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      3_323.251631051190530554 * 1e18,
            exchangeRate: 1.661701692315198699 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_782.181101511692436004 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
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
            lpBalance:    3_847.910224217955230860 * 1e18,
            collateral:   1.671805256817908593 * 1e18,
            deposit:      0.000000000000003183 * 1e18,
            exchangeRate: 1.661984238498668786 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              3_743.004715171921060836 * 1e18,
            borrowerCollateral:        0.328194743182091407 * 1e18,
            borrowert0Np:              6_304.030158815967856681 * 1e18,
            borrowerCollateralization: 0.324123197070597148 * 1e18
        });

        _assertCollateralInvariants();

        skip(80 hours);

        // settle auction 1
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    2,
            settledDebt: 1_860.895155634793071933 * 1e18
        });
        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   0.328194743182091407 * 1e18,
            deposit:      9_559.656155403043853802 * 1e18,
            exchangeRate: 1.353522705781987493 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    3_847.910224217955230860 * 1e18,
            collateral:   1.671805256817908593 * 1e18,
            deposit:      0.000000000000003184 * 1e18,
            exchangeRate: 1.661984238498668786 * 1e18
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

        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   2.802447158831185990 * 1e18,
            deposit:      0,
            exchangeRate: 1.353522705781987493 * 1e18
        });

        _assertBucket({
            index:        2501,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0.133198384953772019 * 1e18,
            deposit:      2_812.853805161609579345 * 1e18,
            exchangeRate: 1.662538898172472227 * 1e18
        });
        
        _assertBucket({
            index:        2502,
            lpBalance:    3_847.910224217955230860 * 1e18,
            collateral:   1.671805256817908593 * 1e18,
            deposit:      0.000000000000003184 * 1e18,
            exchangeRate: 1.661984238498668786 * 1e18
        });

        _assertCollateralInvariants();

        // collateral in buckets:
        // 2500 - 2.802447158831185990
        // 2501 - 0.133198384953772019
        // 2502 - 1.671805256817908593
        // 7388 - 0.392549199397133398

        // lender deposits quote token into 7388 to merge from that bucket
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1 * 1e18,
            index:   7388
        });

        // lender merge / removes available NFTs
        uint256[] memory removalIndexes = new uint256[](4);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2501;
        removalIndexes[2] = 2502;
        removalIndexes[3] = 7388;
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
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      3_323.251631051190530554 * 1e18,
            exchangeRate: 1.661701692315198699 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_782.181101511692436004 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
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
            collateralArbed:  0.021377112291429611 * 1e18,
            quoteTokenAmount: 999.949771689497712185 * 1e18,
            bondChange:       11.179778317915557589 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBucket({
            index:        2000,
            lpBalance:    999.949771689497717000 * 1e18,
            collateral:   0.021377112291429611 * 1e18,
            deposit:      0.000000000000004816 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              9_081.721067669685162105 * 1e18,
            borrowerCollateral:        1.978622887708570389 * 1e18,
            borrowert0Np:              2_537.528961151615989927 * 1e18,
            borrowerCollateralization: 0.801360027022203345 * 1e18
        });

        _assertCollateralInvariants();

        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 4_225.052380000077218250 * 1e18);

        // borrower exits from auction by regular take
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      101.346411682123051536 * 1e18,
            givenAmount:     9_236.623960608616705911 * 1e18,
            collateralTaken: 0.825442180503000900 * 1e18,
            isReward:        false
        });

        assertEq(_quote.balanceOf(_borrower),      7_053.286342957505578146 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 13_461.676340608693924161 * 1e18);

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
                totalBondEscrowed: 112.526190000038609125 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_064.901171882309537906 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertCollateralInvariants();

        // remaining token is moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 1);

        // buckets with collateral
        // 2000 - 0.021377112291429611
        // 2286 - 0.978622887708570389
        _assertBucket({
            index:        2000,
            lpBalance:    999.949771689497717000 * 1e18,
            collateral:   0.021377112291429611 * 1e18,
            deposit:      0.000000000000004816 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        2286,
            lpBalance:    10_993.876483524201092535 * 1e18,
            collateral:   0.978622887708570389 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 2286 and merge / removes remaining NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2286
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2000
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2286;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2286,
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
            lpBalance:    39_997.990867579908684761 * 1e18,
            collateral:   0,
            deposit:      39_997.990867579908684815 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });
        _assertBucket({
            index:        2286,
            lpBalance:    39_997.990867579908680000 * 1e18,
            collateral:   0,
            deposit:      39_997.990867579908680000 * 1e18,
            exchangeRate: 1 * 1e18
        });

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   10_993.876483524201092535 * 1e18,
            index:    2286,
            newLup:   _priceAt(2000),
            lpRedeem: 10_993.876483524201092535 * 1e18
        });

        // borrower2 exits from auction by deposit take
        skip(3 hours);
        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   0 * 1e18,
            deposit:      13_293.289032652657233828 * 1e18,
            exchangeRate: 1.661737007483750362 * 1e18
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2500,
            collateralArbed:  2.644665084063031672 * 1e18,
            quoteTokenAmount: 10_218.071806230882907180 * 1e18,
            bondChange:       40.716636838076396308 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
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
                totalBondEscrowed: 71.809553161962212817 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        // lender removes collateral
        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   2.644665084063031672 * 1e18,
            deposit:      3_075.242406105194717486 * 1e18,
            exchangeRate: 1.661740155087904129 * 1e18
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2576
        });
        _assertBucket({
            index:        2576,
            lpBalance:    10_939.254479284605973531 * 1e18,
            collateral:   0.355334915936968328 * 1e18,
            deposit:      9_999.497716894977170000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2576;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2576,
            noOfNFTsToRemove:        3,
            collateralMerged:        3 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });
        _assertBucket({
            index:        2500,
            lpBalance:    1_850.615691442154479841 * 1e18,
            collateral:   0,
            deposit:      3_075.242406105194717486 * 1e18,
            exchangeRate: 1.661740155087904129 * 1e18
        });
        _assertBucket({
            index:        2576,
            lpBalance:    9_999.497716894977170003 * 1e18,
            collateral:   0,
            deposit:      9_999.497716894977170000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        // borrower 2 redeems LP for quote token
        _removeAllLiquidity({
            from:     _borrower2,
            amount:   939.756762389628803527 * 1e18,
            index:    2576,
            newLup:   MAX_PRICE,
            lpRedeem: 939.756762389628803528 * 1e18
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
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0,
            deposit:      3_323.251631051190530554 * 1e18,
            exchangeRate: 1.661701692315198699 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              10_064.648403565736152555 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_782.181101511692436004 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  0.878726709574230505 * 1e18,
            quoteTokenAmount: 3_361.398272802004594686 * 1e18,
            bondChange:       37.581575187178322169 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    22.612473883102005262 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_022.521149682188763262 * 1e18,
            collateral:   0.878726709574230505 * 1e18,
            deposit:      0.000000000000003545 * 1e18,
            exchangeRate: 1.661984238498668786 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              6_742.854030240414212199 * 1e18,
            borrowerCollateral:        1.121273290425769495 * 1e18,
            borrowert0Np:              3_324.006080622209644773 * 1e18,
            borrowerCollateralization: 0.608603524551268026 * 1e18
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
            collateralArbed:  0.146608690667722735 * 1e18,
            quoteTokenAmount: 6_857.863904268309585227 * 1e18,
            bondChange:       76.673249351930248685 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
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
                totalBondEscrowed: 148.379130648146969565 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_066.670727855240484714 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5483,
            lpBalance:    0.001301641065472439 * 1e18,
            collateral:   0.974664599758046760 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000155 * 1e18
        });

        // bucket take on borrower 2
        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.218877853231731145 * 1e18,
            quoteTokenAmount: 10_238.373470803340942675 * 1e18,
            bondChange:       112.526190000038609125 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
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
                totalBondEscrowed: 35.852940648108360440 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5565,
            lpBalance:    0.000693007502638594 * 1e18,
            collateral:   0.781122146768268855 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000410 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(2), 73);

        _assertBucket({
            index:        2000,
            lpBalance:    59_996.986301369863020000 * 1e18,
            collateral:   0.365486543899453880 * 1e18,
            deposit:      42_900.748926298212443280 * 1e18,
            exchangeRate: 1.000000000000000001 * 1e18
        });

        // lender adds liquidity in bucket 6171 and 6252 and merge / removes the other 3 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  2_000 * 1e18,
            index:   5483
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  2_000 * 1e18,
            index:   5565
        });
        uint256[] memory removalIndexes = new uint256[](4);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 5483;
        removalIndexes[3] = 5565;

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
            amount:   0.001301641065472439 * 1e18,
            index:    5483,
            newLup:   MAX_PRICE,
            lpRedeem: 0.001301641065472439 * 1e18
        });

        _removeAllLiquidity({
            from:     _borrower2,
            amount:   0.000693007502638594 * 1e18,
            index:    5565,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000693007502638594 * 1e18
        });
    }
}
