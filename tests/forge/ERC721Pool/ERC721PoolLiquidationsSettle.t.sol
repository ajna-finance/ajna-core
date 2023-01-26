// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721Pool } from 'src/ERC721Pool.sol';

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsSettleTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

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

        // Lender adds Quote token in one bucket
        _addInitialLiquidity({
            from:   _lender,
            amount: 15_000 * 1e18,
            index:  2500
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000 * 1e18,
            index:  2501
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

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  2_502.403846153846155000 * 1e18,
                lup:                  3_863.654368867279344664 * 1e18,
                poolSize:             16_000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 2.590711908723330630 * 1e18,
                poolDebt:             10_009.615384615384620000 * 1e18,
                actualUtilization:    0.625600961538461539 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        500.480769230769231000 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_004.807692307692310000 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1.543977154129479546 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_004.807692307692310000 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_751.682692307692308500 * 1e18,
            borrowerCollateralization: 2.315965731194219318 * 1e18
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        104_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);


        /***********************/
        /*** Kick both loans ***/
        /***********************/

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         2 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_863.654368867279344664 * 1e18
        });

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower2,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         3 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_863.654368867279344664 * 1e18
        });

        // skip to make loans clearable
        skip(80 hours);
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  3_863.654368867279344664 * 1e18,
                poolSize:             12_997.115384615384614000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 2.624293841728065377 * 1e18,
                poolDebt:             10_139.364366784136304617 * 1e18,
                actualUtilization:    0.780124209621624751 * 1e18,
                targetUtilization:    1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_069.682183392068152308 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1.524219558190194493 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_069.682183392068152308 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_751.682692307692308500 * 1e18,
            borrowerCollateralization: 2.286329337285291739 * 1e18
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        104_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);

    }

    function testKickAndSettleSubsetPoolFractionalCollateral() external tearDown {

        // settle borrower 2
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          1_501.442307692307693000 * 1e18,
                bondFactor:        0.3 * 1e18,
                kickTime:          _startTime,
                kickMomp:          3_863.654368867279344664 * 1e18,
                totalBondEscrowed: 3_002.884615384615386000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_134.735576923076927750 * 1e18,
                thresholdPrice:    1_689.894061130689384102 * 1e18,
                neutralPrice:      1_751.682692307692308500 * 1e18
            })
        );

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_067.367788461538463875 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 1_501.442307692307693000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     5_069.682183392068152308 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        // settle borrower
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 5_067.367788461538463875 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             2_861.960513526920122158 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    0.437382306954677563 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   _startTime + 80 hours
            })
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
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
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1_751.682692307692308500 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        // assert bucket used for settle
        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    0.000000137345389190751978670 * 1e27,
            collateral:   1.375706158271934624 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999999994537736 * 1e27
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        104_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);

        // lender adds liquidity in min bucket and merge / removes 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX,
            lpAward: 100.000000000000000000546226400 * 1e27,
            newLup:  MAX_PRICE
        });

        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2501;
        removalIndexes[2] = MAX_FENWICK_INDEX;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // lender merge and claim one more NFT
        removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = MAX_FENWICK_INDEX;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        1,
            collateralMerged:        1 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // lender claims one more settled NFT
        _pool.removeCollateral(1, MAX_FENWICK_INDEX);

        // borrower pulls one NFT
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 1,
            newLup:           MAX_PRICE
        });

        // check lender is owner of 3 NFTs (2 pledged by first borrower, one pledged by 2nd borrower)
        assertEq(_collateral.ownerOf(1), _lender);
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(53), _lender);
        assertEq(_collateral.ownerOf(73), address(_lender));

        // check borrower 2 owner of 1 NFT
        assertEq(_collateral.ownerOf(51), _borrower2);

        _assertBucket({
            index:        2500,
            lpBalance:    1_861.033884081553472671582113012 * 1e27,
            collateral:   0,
            deposit:      1861.636634299022017158 * 1e18,
            exchangeRate: 1.000323879227898104734699503 * 1e27
        });
    }

    function testKickAndSettleSubsetPoolByRepay() external tearDown {
        // before auction settle: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(51), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));
        assertEq(_collateral.ownerOf(73), address(_pool));

        // borrower 2 repays debt and settles auction
        _repayDebtNoLupCheck({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     0,
            collateralToPull: 3
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                kickMomp:          0,
                totalBondEscrowed: 1_501.442307692307693000 * 1e18,
                auctionPrice:      0,
                debtInAuction:     5_069.682183392068152308 * 1e18,
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

        // after settle: NFTs pledged by auctioned borrower are owned by the borrower
        assertEq(_collateral.ownerOf(51), address(_borrower2));
        assertEq(_collateral.ownerOf(53), address(_borrower2));
        assertEq(_collateral.ownerOf(73), address(_borrower2));

        // before auction settle: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));

        // borrower repays debt and settles auction
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     0,
            collateralToPull: 2
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
            borrowerCollateralization: 1 * 1e18
        });

        // after settle: NFTs pledged by auctioned borrower are owned by the borrower
        assertEq(_collateral.ownerOf(1), address(_borrower));
        assertEq(_collateral.ownerOf(3), address(_borrower));
    }
}

contract ERC721PoolLiquidationsPartialSettleTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {
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
    }

    function testSettlePartialDebtSubsetPool() external tearDown {
        // kick loan
        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         2 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_825.305679430983794766 * 1e18
        });

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower2,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         3 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                99836282890
        });

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        // skip to make loans clearable
        skip(80 hours);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e27,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_069.682183392068152308 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039385618 * 1e18
        });

        // first settle partially settles borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 4_997.146788514113366576 * 1e18
        });

        // invariant bucket collateral + borrower remaining collateral = borrower pledged collateral
        // 1.293963857643160539 + 0.706036142356839461 = 2

        // collateral in bucket used to settle auction increased with the amount used to settle debt
        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e27,
            collateral:   1.293963857643160539 * 1e18,
            deposit:      0,
            exchangeRate: 1.000463012547417693069317412 * 1e27
        });

        // partial borrower debt is settled, borrower collateral decreased with the amount used to settle debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              70.253071652712624346 * 1e18,
            borrowerCollateral:        0.706036142356839461 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000001003344372 * 1e18
        });

        // the 2 token ids are still owned by borrower after settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        // all NFTs are owned by the pool
        assertEq(_collateral.ownerOf(1),  address(_pool));
        assertEq(_collateral.ownerOf(3),  address(_pool));
        assertEq(_collateral.ownerOf(51), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));
        assertEq(_collateral.ownerOf(73), address(_pool));

        // all auctions should be settled prior of claiming NFTs from pool

        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2500
        });

        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112501627698449534 * 1e27,
            collateral:   1.293963857643160539 * 1e18,
            deposit:      20_000 * 1e18,
            exchangeRate: 1.000463012547417693069317412 * 1e27
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 70.220999947425097299 * 1e18
        });

        // invariant bucket collateral = borrower pledged collateral

        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112501627698449534 * 1e27,
            collateral:   1.312146920864032689 * 1e18,
            deposit:      19_929.746928347287375654 * 1e18,
            exchangeRate: 1.000463012547417693146364158 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_067.367788461538463875 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112501627698449534 * 1e27,
            collateral:   2.624293841728065377 * 1e18,
            deposit:      14_860.064744955219223346 * 1e18,
            exchangeRate: 1.000463012547417693082646212 * 1e27
        });

        _assertBucket({
            index:        7388,
            lpBalance:    0.000000137345389190751978570 * 1e27,
            collateral:   1.375706158271934623 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999999995729747 * 1e27
        });

        uint256 collateral;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }

        assertEq(collateral, 4 * 1e18);

        // borrower 2 can claim 1 NFT token (id 51) after settle
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1_769.243311298076895206 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower2, 0), 51);

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(2), 73);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(3), 53);

        // lender can claim 2 NFTs from bucket 2500
        changePrank(_lender);
        _pool.removeCollateral(2, 2500);

        // lender adds liquidity in min bucket and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX,
            lpAward: 100.000000000000000000427025300 * 1e27,
            newLup:  MAX_PRICE
        });

        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = MAX_FENWICK_INDEX;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 4 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(1),  _lender);
        assertEq(_collateral.ownerOf(3),  _lender);
        assertEq(_collateral.ownerOf(53), _lender);
        assertEq(_collateral.ownerOf(73), _lender);
        assertEq(_collateral.ownerOf(51), address(_pool));

        // borrower 2 can pull 1 NFT from pool
        _repayDebtNoLupCheck({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 1
        });

        assertEq(_collateral.ownerOf(1),  _lender);
        assertEq(_collateral.ownerOf(3),  _lender);
        assertEq(_collateral.ownerOf(53), _lender);
        assertEq(_collateral.ownerOf(73), _lender);
        // the NFT pulled from pool is owned by lender
        assertEq(_collateral.ownerOf(51), _borrower2);

        _assertBucket({
            index:        2500,
            lpBalance:    14_853.187532758404035070648439563 * 1e27,
            collateral:   0,
            deposit:      14_860.064744955219223346 * 1e18,
            exchangeRate: 1.000463012547417693082628591 * 1e27
        });

        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    100.000000000000000000179003909 * 1e27,
            collateral:   0,
            deposit:      100 * 1e18,
            exchangeRate: 0.999999999999999999998209960 * 1e27
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
            borrowert0Np:              0,
            borrowerCollateralization: 1 * 1e18
        });
    }

    function testDepositTakeAndSettleSubsetPool() external tearDown {
        // kick loan
        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         2 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_825.305679430983794766 * 1e18
        });

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower2,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         3 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                99836282890
        });

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e27,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_067.367788461538463875 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039403606 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:     _lender,
            borrower: _borrower,
            index:    2500
        });

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
        });

        uint256 collateral;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }

        assertEq(collateral + 0.151993545296404634 * 1e18, 2 * 1e18);

        assertEq(_quote.balanceOf(_borrower), 5_100 * 1e18);

        // borrower tries to repay remaining debt
        _repayDebtNoLupCheck({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    1000 * 1e18,
            amountRepaid:     0,
            collateralToPull: 0
        });

        // borrower cannot repay anything at this point as colalteral is below 1, settle should be called
        assertEq(_quote.balanceOf(_borrower), 5_100 * 1e18);

        skip(80 hours);

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 424.955585758182281304 * 1e18
        });

        collateral = 0;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }

        assertEq(collateral, 2 * 1e18);

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });

        _assertBucket({
            index:        2501,
            lpBalance:    2_000 * 1e27,
            collateral:   0.110613668792155518 * 1e18,
            deposit:      1_575.963420924493188203 * 1e18,
            exchangeRate: 1.000605085927545054261711487 * 1e27
        });

        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    4131213056631479032,
            collateral:   0.041379876504249116 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000000002039410 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        // lender adds liquidity in min bucket and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX,
            lpAward: 99.999999999999999999796059000 * 1e27,
            newLup:  3_806.274307891526195092 * 1e18
        });

        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2501;
        removalIndexes[2] = MAX_FENWICK_INDEX;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(1), _lender);
        assertEq(_collateral.ownerOf(3), _lender);
    }

    function testDepositTakeAndSettleByPledgeSubsetPool() external { // tearDown { FIXME: incorrect pledgedCollateral pool balance
        // kick loan
        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         2 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_825.305679430983794766 * 1e18
        });

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower2,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         3 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                99836282890
        });

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e27,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_067.367788461538463875 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039403606 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2500,
            collateralArbed:  1.848006454703595366 * 1e18,
            quoteTokenAmount: 4_998.040748687334744778 * 1e18,
            bondChange:       1_499.412224606200423433 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    1_499.134615384615384200000000000 * 1e27
        });

        assertEq(_pool.pledgedCollateral(), 3.151993545296404634 * 1e18);

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
        });

        uint256 collateral;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }
        assertEq(collateral + _pool.pledgedCollateral(), 5 * 1e18);

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 2,
            newLup:           3_844.432207828138682757 * 1e18
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
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              149.442714324960768925 * 1e18,
            borrowerCollateralization: 27.135048141751657646 * 1e18
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
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    141.677736768517403695 * 1e18,
                neutralPrice:      0
            })
        );

        collateral = 0;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }
        assertEq(collateral, 2 * 1e18);

        assertEq(_pool.pledgedCollateral(), 4.151993545296404634 * 1e18); // FIXME: should be 4

        // the 3 new token ids pledged are owned by borrower
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 2), 2);
        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 5);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 4);

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });
        _assertBucket({
            index:        6113,
            lpBalance:    0.000008766823996014791499039 * 1e27,
            collateral:   0.151993545296404634 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999999999978734 * 1e27
        });

        // lender adds liquidity in bucket 6113 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1000 * 1e18,
            index:   6113,
            lpAward: 1_000.000000000000000000021266000 * 1e27,
            newLup:  3_844.432207828138682757 * 1e18
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 6113;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6113,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // borrower repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    500 * 1e18,
            amountRepaid:     425.033210305552211086 * 1e18,
            collateralToPull: 3,
            newLup:           MAX_PRICE
        });

        // the 3 NFTs pulled from pool are owned by borrower
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(2), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(5), _lender);
        assertEq(_collateral.ownerOf(4), _lender);

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000008757551393712 * 1e18,
            index:    6113,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000008766823996014791499039 * 1e27
        });

        assertEq(_pool.pledgedCollateral(), 1.151993545296404634 * 1e18); // FIXME: should be 0
    }

    function testDepositTakeAndSettleByRepaySubsetPool() external { // tearDown { FIXME: incorrect pledgedCollateral pool balance
        // kick loan
        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         2 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                3_825.305679430983794766 * 1e18
        });

        _kickWithDeposit({
            from:               _lender,
            index:              2500,
            borrower:           _borrower2,
            debt:               5_067.367788461538463875 * 1e18,
            collateral:         3 * 1e18,
            bond:               1_501.442307692307693000 * 1e18,
            removedFromDeposit: 1_501.442307692307693000 * 1e18,
            transferAmount:     0,
            lup:                99836282890
        });

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e27,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_067.367788461538463875 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039403606 * 1e18
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2500,
            collateralArbed:  1.848006454703595366 * 1e18,
            quoteTokenAmount: 4_998.040748687334744778 * 1e18,
            bondChange:       1_499.412224606200423433 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    1_499.134615384615384200000000000 * 1e27
        });

        assertEq(_pool.pledgedCollateral(), 3.151993545296404634 * 1e18);

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
        });

        uint256 collateral;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }
        assertEq(collateral + _pool.pledgedCollateral(), 5 * 1e18);

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 2,
            newLup:           3_844.432207828138682757 * 1e18
        });

        // borrower exits from auction by repaying the debt
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    500 * 1e18,
            amountRepaid:     425.033210305552211086 * 1e18,
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
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        collateral = 0;
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (, uint256 bucketCollateral, , , ) = _pool.bucketInfo(bucketIndex);
            collateral += bucketCollateral;
        }
        assertEq(collateral, 2 * 1e18);

        assertEq(_pool.pledgedCollateral(), 1.151993545296404634 * 1e18); // FIXME: should be 0

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    6_496.2499999999999982 * 1e27,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.099104593020662414485129597 * 1e27
        });
        _assertBucket({
            index:        6113,
            lpBalance:    0.000008766823996014791499039 * 1e27,
            collateral:   0.151993545296404634 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999999999978734 * 1e27
        });

        // lender adds liquidity in bucket 6113 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1000 * 1e18,
            index:   6113,
            lpAward: 1_000.000000000000000000021266000 * 1e27,
            newLup:  MAX_PRICE
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 6113;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 6113,
            noOfNFTsToRemove:        2,
            collateralMerged:        2 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000008757551393712 * 1e18,
            index:    6113,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000008766823996014791499039 * 1e27
        });

        assertEq(_pool.pledgedCollateral(), 1.151993545296404634 * 1e18); // FIXME: should be 0
    }
}
