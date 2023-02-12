// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721Pool } from 'src/ERC721Pool.sol';

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsSettleAuctionTest is ERC721HelperContract {

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

        // kick both loans
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
    }

    function testSettlePartialDebtSubsetPool() external tearDown {
        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        // skip to make loans clearable
        skip(80 hours);

        _assertBucket({
            index:        2500,
            lpBalance:    4_997.115384615384614 * 1e18,
            collateral:   0,
            deposit:      4_997.115384615384614 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_069.682183392068152308 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039385618 * 1e18
        });

        // first settle call settles partial borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 4_997.146788514113366576 * 1e18
        });

        // collateral in bucket used to settle auction increased with the amount used to settle debt
        _assertBucket({
            index:        2500,
            lpBalance:    4_997.115384615384614 * 1e18,
            collateral:   1.293963857643160539 * 1e18,
            deposit:      0,
            exchangeRate: 1.000463012547417693 * 1e18
        });
        // partial borrower debt is settled, borrower collateral decreased with the amount used to settle debt
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              70.253071652712624346 * 1e18,
            borrowerCollateral:        0.706036142356839461 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000001003344372 * 1e18
        });

        _assertCollateralInvariants();

        // the 2 token ids are rebalanced and transferred to pool claimable tokens array after settle
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        // all NFTs are owned by the pool
        assertEq(_collateral.ownerOf(1),  address(_pool));
        assertEq(_collateral.ownerOf(3),  address(_pool));
        assertEq(_collateral.ownerOf(51), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));
        assertEq(_collateral.ownerOf(73), address(_pool));

        // adding more liquidity to settle all auctions
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2500
        });

        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112503013 * 1e18,
            collateral:   1.293963857643160539 * 1e18,
            deposit:      20_000 * 1e18,
            exchangeRate: 1.000463012547417693 * 1e18
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 70.220999947425097299 * 1e18
        });


        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112503013 * 1e18,
            collateral:   1.312146920864032689 * 1e18,
            deposit:      19_929.746928347287375654 * 1e18,
            exchangeRate: 1.000463012547417693 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        _assertCollateralInvariants();

        _settle({
            from:        _lender,
            borrower:    _borrower2,
            maxDepth:    1,
            settledDebt: 5_067.367788461538463875 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    24_987.859419295112503013 * 1e18,
            collateral:   2.624293841728065377 * 1e18,
            deposit:      14_860.064744955219223346 * 1e18,
            exchangeRate: 1.000463012547417693 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    0.000000137345389190 * 1e18,
            collateral:   1.375706158271934623 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000007280914 * 1e18
        });
        // borrower 2 can claim 1 NFT token (id 51) after settle
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1_769.243311298076895206 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        _assertCollateralInvariants();

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
            lpAward: 99.999999999271908600 * 1e18,
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
            lpBalance:    14_853.187532758404035619 * 1e18,
            collateral:   0,
            deposit:      14_860.064744955219223346 * 1e18,
            exchangeRate: 1.000463012547417693 * 1e18
        });
        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    99.999999999271908600 * 1e18,
            collateral:   0,
            deposit:      100 * 1e18,
            exchangeRate: 1.000000000007280914 * 1e18
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

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e18,
            collateral:   0,
            deposit:      4_997.115384615384614 * 1e18,
            exchangeRate: 1 * 1e18
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
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
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
            maxDepth:    1,
            settledDebt: 424.955585758182281304 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBucket({
            index:        2501,
            lpBalance:    2_000 * 1e18,
            collateral:   0.110613668792155518 * 1e18,
            deposit:      1_575.963420924493188203 * 1e18,
            exchangeRate: 1.000605085927545054 * 1e18
        });
        _assertBucket({
            index:        MAX_FENWICK_INDEX,
            lpBalance:    4131213057,
            collateral:   0.041379876504249116 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        // lender adds liquidity in min bucket and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  100 * 1e18,
            index:   MAX_FENWICK_INDEX,
            lpAward: 100 * 1e18,
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

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleByPledgeSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4_997.115384615384614000 * 1e18,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e18
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
            quoteTokenAmount: 7_140.058212410478208121 * 1e18,
            bondChange:       2_142.017463723143462436 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    2_141.620879120879120674 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 3,
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

        _assertCollateralInvariants();

        // the 3 new token ids pledged are owned by borrower
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 2), 2);
        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 5);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 4);

        _assertBucket({
            index:        2500,
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBucket({
            index:        6113,
            lpBalance:    0.000008766823996015 * 1e18,
            collateral:   0.151993545296404634 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 6113 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1000 * 1e18,
            index:   6113,
            lpAward: 1_000 * 1e18,
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
        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000008757551393712 * 1e18,
            index:    6113,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000008766823996015 * 1e18
        });

        // the 3 NFTs pulled from pool are owned by borrower
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(2), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        // the 2 NFTs claimed from pool are owned by lender
        assertEq(_collateral.ownerOf(5), _lender);
        assertEq(_collateral.ownerOf(4), _lender);

        _assertCollateralInvariants();
    }

    function testDepositTakeAndSettleByRepaySubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2500,
            lpBalance:    4997.115384615384614 * 1e18,
            collateral:   0,
            deposit:      4_997.115384615384614000 * 1e18,
            exchangeRate: 1 * 1e18
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
            quoteTokenAmount: 7_140.058212410478208121 * 1e18,
            bondChange:       2_142.017463723143462436 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    2_141.620879120879120674 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              425.033210305552211086 * 1e18,
            borrowerCollateral:        0.151993545296404634 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000035701847 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 3,
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

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2500,
            lpBalance:    7_138.736263736263734674 * 1e18,
            collateral:   1.848006454703595366 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBucket({
            index:        6113,
            lpBalance:    0.000008766823996015 * 1e18,
            collateral:   0.151993545296404634 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 6113 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1000 * 1e18,
            index:   6113,
            lpAward: 1_000 * 1e18,
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

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000008757551393712 * 1e18,
            index:    6113,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000008766823996015 * 1e18
        });

    }

    function testDepositTakeAndSettleByRegularTakeSubsetPool() external tearDown {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              5_067.367788461538463875 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000039403606 * 1e18
        });

        skip(4 hours);

        _addLiquidity({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   2000,
            lpAward: 1_000 * 1e18,
            newLup:  3_806.274307891526195092 * 1e18
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.021378186081598093 * 1e18,
            quoteTokenAmount: 999.9999999999999908 * 1e18,
            bondChange:       299.99999999999999724 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBucket({
            index:        2000,
            lpBalance:    1_000 * 1e18,
            collateral:   0.021378186081598093 * 1e18,
            deposit:      0,
            exchangeRate: 0.999999999999999991 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              4_422.207326928504959735 * 1e18,
            borrowerCollateral:        1.978621813918401907 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 1.703035796058482710 * 1e18
        });

        _assertCollateralInvariants();

        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 4_000 * 1e18);

        // borrower exits from auction by regular take
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      1_201.442307692307695760 * 1e18,
            givenAmount:     4_422.207326928504959735 * 1e18,
            collateralTaken: 0.286141493566424944 * 1e18,
            isReward:        false
        });

        assertEq(_quote.balanceOf(_borrower),      16_132.410148540612418451 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 8_422.207326928504959735 * 1e18);

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_067.483483110752298817 * 1e18,
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
                totalBondEscrowed: 0,
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
            deposit:      0,
            exchangeRate: 0.999999999999999991 * 1e18
        });
        _assertBucket({
            index:        2222,
            lpBalance:    15_127.888999922350308085 * 1e18,
            collateral:   0.978621813918401907 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 2222 and merge / removes remaining NFTs
        _addLiquidity({
            from:    _lender,
            amount:  20_000 * 1e18,
            index:   2222,
            lpAward: 20_000 * 1e18,
            newLup:  MAX_PRICE
        });
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2000,
            lpAward: 10_000.00000000000009 * 1e18,
            newLup:  MAX_PRICE
        });
        uint256[] memory removalIndexes = new uint256[](2);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2222;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2222,
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
            amount:   15_113.342952807040348884 * 1e18,
            index:    2222,
            newLup:   MAX_PRICE,
            lpRedeem: 15_127.888999922350308085 * 1e18
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
            deposit:      2_000 * 1e18,
            exchangeRate: 1 * 1e18
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
            index:            2502,
            collateralArbed:  0.747044074730990508 * 1e18,
            quoteTokenAmount: 2_857.671941853722277733 * 1e18,
            bondChange:       857.301582556116683320 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    857.142857142857143034 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_857.142857142857143034 * 1e18,
            collateral:   0.747044074730990508 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              3_422.703599695281361864 * 1e18,
            borrowerCollateral:        1.252955925269009492 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000036547267 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });

        // borrower exits from auction by bucket take: lender adds quote token at a higher priced bucket and calls deposit take
        _addLiquidity({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2400,
            lpAward: 10_000 * 1e18,
            newLup:  6_362.157913642177655049 * 1e18
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2400,
            collateralArbed:  0.768540585971418892 * 1e18,
            quoteTokenAmount: 4_889.576570993259088377 * 1e18,
            bondChange:       1_466.872971297977726513 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    1_466.872971297977726513 * 1e18
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

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);

        _assertBucket({
            index:        2400,
            lpBalance:    11_466.872971297977726513 * 1e18,
            collateral:   0.768540585971418892 * 1e18,
            deposit:      6_577.296400304718638136 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        6113,
            lpBalance:    0.000027940555056533 * 1e18,
            collateral:   0.484415339297590600 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 6113 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   6113,
            lpAward: 1_000 * 1e18,
            newLup:  MAX_PRICE
        });
        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2400;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 6113;
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

        _assertCollateralInvariants();

        // borrower removes tokens from auction price bucket for compensated collateral fraction
        _removeAllLiquidity({
            from:     _borrower,
            amount:   0.000027911002546377 * 1e18,
            index:    6113,
            newLup:   MAX_PRICE,
            lpRedeem: 0.000027940555056533 * 1e18
        });
    }

    function testDepositTakeAndSettleBySettleSubsetPool() external {

        // the 2 token ids are owned by borrower before settle
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 0), 1);
        assertEq(ERC721Pool(address(_pool)).borrowerTokenIds(_borrower, 1), 3);

        _assertBucket({
            index:        2502,
            lpBalance:    2_000 * 1e18,
            collateral:   0,
            deposit:      2_000 * 1e18,
            exchangeRate: 1 * 1e18
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
            index:            2502,
            collateralArbed:  0.747044074730990508 * 1e18,
            quoteTokenAmount: 2_857.671941853722277733 * 1e18,
            bondChange:       857.301582556116683320 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    857.142857142857143034 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_857.142857142857143034 * 1e18,
            collateral:   0.747044074730990508 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              3_422.703599695281361864 * 1e18,
            borrowerCollateral:        1.252955925269009492 * 1e18,
            borrowert0Np:              2_627.524038461538462750 * 1e18,
            borrowerCollateralization: 0.000000000036547267 * 1e18
        });

        _assertCollateralInvariants();

        // borrower 2 repays entire debt and pulls collateral
        _repayDebt({
            from:             _borrower2,
            borrower:         _borrower2,
            amountToRepay:    6_000 * 1e18,
            amountRepaid:     5_068.293419619520519499 * 1e18,
            collateralToPull: 3,
            newLup:           3_863.654368867279344664 * 1e18
        });

        skip(72 hours);

        // borrower exits from auction by pool debt settle
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 3_422.078505440842334340 * 1e18
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
                totalBondEscrowed: 0,
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
            lpBalance:    4_997.115384615384614000 * 1e18,
            collateral:   0.886272650740532744 * 1e18,
            deposit:      1_574.636172339194134488 * 1e18,
            exchangeRate: 1.000354601931047794 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    2_857.142857142857143034 * 1e18,
            collateral:   0.747044074730990508 * 1e18,
            deposit:      0,
            exchangeRate: 1.000185179648802797 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    0.000000036608295127 * 1e18,
            collateral:   0.366683274528476748 * 1e18,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lender adds liquidity in bucket 7388 and merge / removes the other 2 NFTs
        _addLiquidity({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   7388,
            lpAward: 1_000 * 1e18,
            newLup:  MAX_PRICE
        });
        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 7388;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 7388,
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
