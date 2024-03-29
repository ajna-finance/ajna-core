// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsSettleTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {
        _startTest();

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
                htp:                  2_602.500000000000001200 * 1e18,
                lup:                  3_863.654368867279344664 * 1e18,
                poolSize:             15_999.269406392694064000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 2.694340385072263856 * 1e18,
                poolDebt:             10_009.615384615384620000 * 1e18,
                actualUtilization:    0,
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
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 1.484593417432191870 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_004.807692307692310000 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_928.978897048106755629 * 1e18,
            borrowerCollateralization: 2.226890126148287806 * 1e18
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        104_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);


        /***********************/
        /*** Kick both loans ***/
        /***********************/

        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower,
            debt:       5_004.80769230769231 * 1e18,
            collateral: 2 * 1e18,
            bond:       55.955451071569254199 * 1e18
        });

        _lenderKick({
            from:       _lender,
            index:      2500,
            borrower:   _borrower2,
            debt:       5_004.80769230769231 * 1e18,
            collateral: 3 * 1e18,
            bond:       55.955451071569254199 * 1e18
        });

        // skip to make loans clearable
        skip(80 hours);
        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  3_863.654368867279344664 * 1e18,
                poolSize:             15_999.269406392694064000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 2.695570958416975794 * 1e18,
                poolDebt:             10_014.187028922603757647 * 1e18,
                actualUtilization:    0,
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
            borrowerDebt:              5_007.093514461301878824 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 1.483915675641896080 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              5_007.093514461301878824 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              1_928.978897048106755629 * 1e18,
            borrowerCollateralization: 2.225873513462844121 * 1e18
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_111.910902143138508398 * 1e18); // increased by bonds size
        assertEq(_quote.balanceOf(_lender),        103_888.089097856861491602 * 1e18); // decreased by bonds size
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);
    }

    function testKickAndSettleSubsetPoolFractionalCollateral() external tearDown {
        // settle borrower 2, whose neutral price has been carried from borrower 1
        _assertAuction(
            AuctionParams({
                borrower:          _borrower2,
                active:            true,
                kicker:            _lender,
                bondSize:          55.955451071569254199 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          _startTime,
                referencePrice:    2_893.468345572160133444 * 1e18,
                totalBondEscrowed: 111.910902143138508398 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_009.615384615384620000 * 1e18,
                debtToCollateral:  1_668.269230769230770000 * 1e18,
                neutralPrice:      1_928.978897048106755629 * 1e18
            })
        );

        // revert if auction is not settled
        _assertMergeRemoveCollateralAuctionNotClearedRevert({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            removeCollateralAtIndex: new uint256[](0)
        });

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_007.093514461301878823 * 1e18
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
                totalBondEscrowed: 111.910902143138508398 * 1e18,
                auctionPrice:      0,
                debtInAuction:     5_007.093514461301878824 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        // revert if auction is not settled
        _assertMergeRemoveCollateralAuctionNotClearedRevert({
            from:                    _lender,
            toIndex:                 MAX_FENWICK_INDEX,
            noOfNFTsToRemove:        2,
            removeCollateralAtIndex: new uint256[](0)
        });

        // settle borrower
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 5_007.093514461301878823 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             5_988.968275131226558255 * 1e18,
                pledgedCollateral:    1 * 1e18,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
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
                referencePrice:    0,
                totalBondEscrowed: 111.910902143138508398 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
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
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              0 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
        // assert bucket used for settle
        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    0.000000140579953912 * 1e18,
            collateral:   1.408104847675984812 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999995447280 * 1e18
        });

        assertEq(_quote.balanceOf(address(_pool)), 6_111.910902143138508398 * 1e18);
        assertEq(_quote.balanceOf(_lender),        103_888.089097856861491602 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);

        // lender adds liquidity in min bucket and merge / removes 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX,
            lpAward: 99.995890411414157448 * 1e18,
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
            lpBalance:    4_987.559691655058899286 * 1e18,
            collateral:   0,
            deposit:      4_988.771068627862163511 * 1e18,
            exchangeRate: 1.000242879694218013 * 1e18
        });
    }
    
}
