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
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 0.737867154306508702 * 1e18
        });

        // first settle call settles partial borrower debt
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    1,
            settledDebt: 5_000.732078876477988054 * 1e18
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
            borrowert0Np:              4_090.606107481772639379 * 1e18,
            borrowerCollateralization: 0.521926384043273437 * 1e18
        });

        _assertCollateralInvariants();

        // 1 token id (token id 3, the most recent pledged token) was moved from borrower token ids array to pool claimable token ids array after partial bad debt settle
        assertEq(ERC721Pool(address(_pool)).getBorrowerTokenIds(_borrower).length, 1);
        assertEq(ERC721Pool(address(_pool)).getBorrowerTokenIds(_borrower)[0], 1);
        assertEq(ERC721Pool(address(_pool)).getBucketTokenIds().length, 1);
        assertEq(ERC721Pool(address(_pool)).getBucketTokenIds()[0], 3);

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
            settledDebt: 2_756.297127247586280076 * 1e18
        });

        // no token id left in borrower token ids array
        assertEq(ERC721Pool(address(_pool)).getBorrowerTokenIds(_borrower).length, 0);
        assertEq(ERC721Pool(address(_pool)).getBucketTokenIds().length, 2);
        // tokens used to settle entire bad debt (settle auction) are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).getBucketTokenIds()[0], 3);
        assertEq(ERC721Pool(address(_pool)).getBucketTokenIds()[1], 1);

        _assertBucket({
            index:        2500,
            lpBalance:    20034.884788261831319325 * 1e18,
            collateral:   0.712138214303767201 * 1e18,
            deposit:      30547.093039196991134852 * 1e18,
            exchangeRate: 1.662028472538971359 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              2_312.675770101976733191 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 2_312.675770101976733191 * 1e18
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
            settledDebt: 10_069.704976226041001321 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    20_034.884788261831319325 * 1e18,
            collateral:   3.318402650731141155 * 1e18,
            deposit:      18_164.712292868973392890 * 1e18,
            exchangeRate: 1.546596025856924939 * 1e18
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
            lpBalance:    15_757.678471160293718635 * 1e18,
            collateral:   1.606264436427373954 * 1e18,
            deposit:      18_164.712292868973392890 * 1e18,
            exchangeRate: 1.546596025856924939 * 1e18
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

    function testDepositTakeAndSettleSubsetPool() external tearDown {
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
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
        });

        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  3_000 * 1e18,
            index:   2502
        });
        skip(32 hours);

        _depositTake({
            from:     _lender,
            borrower: _borrower,
            index:    2502
        });

        _assertBucket({
            index:        2502,
            lpBalance:    3_848.220602860971165296 * 1e18,
            collateral:   1.671905447194023163 * 1e18,
            deposit:      0.000000000000001434 * 1e18,
            exchangeRate: 1.661949784757169370 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              3_742.625741320959738707 * 1e18,
            borrowerCollateral:        0.328094552805976837 * 1e18,
            borrowert0Np:              6_557.529424508974043853 * 1e18,
            borrowerCollateralization: 0.324057059956572295 * 1e18
        });

        _assertCollateralInvariants();

        skip(80 hours);

        // settle auction 1
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    2,
            settledDebt: 3_744.317995698454162123 * 1e18
        });
        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   0.328094552805976837 * 1e18,
            deposit:      9_559.443166179627977772 * 1e18,
            exchangeRate: 1.353447691080682492 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    3_848.220602860971165296 * 1e18,
            collateral:   1.671905447194023163 * 1e18,
            deposit:      0.000000000000001435 * 1e18,
            exchangeRate: 1.661949784757169370 * 1e18
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
            settledDebt: 10_071.222443357521878028 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   2.802291842089438895 * 1e18,
            deposit:      0,
            exchangeRate: 1.353447691080682492 * 1e18
        });
        _assertBucket({
            index:        2501,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0.133122201019904801 * 1e18,
            deposit:      2_812.950529824876926491 * 1e18,
            exchangeRate: 1.662440814040839338 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    3_848.220602860971165296 * 1e18,
            collateral:   1.671905447194023163 * 1e18,
            deposit:      0.000000000000001435 * 1e18,
            exchangeRate: 1.661949784757169370 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    0.000000039203762451 * 1e18,
            collateral:   0.392680509696633141 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000011796173 * 1e18
        });

        _assertCollateralInvariants();

        // collateral in buckets:
        // 2500 - 2.802290638246429771
        // 2501 - 0.133123410882128970
        // 2502 - 1.671905447194023163
        // 7388 - 0.392680503677418096

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
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
        });

        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  1_000 * 1e18,
            index:   2000
        });

        skip(4 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.021377546506154720 * 1e18,
            quoteTokenAmount: 999.970082801181914578 * 1e18,
            bondChange:       11.180005403047679924 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertBucket({
            index:        2000,
            lpBalance:    999.949771689497717000 * 1e18,
            collateral:   0.021377546506154720 * 1e18,
            deposit:      0.000000000000024123 * 1e18,
            exchangeRate: 1.000020312131928292 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              9_081.701097185699143214 * 1e18,
            borrowerCollateral:        1.978622453493845280 * 1e18,
            borrowert0Np:              2_639.024895576489054434 * 1e18,
            borrowerCollateralization: 0.801361613336061264 * 1e18
        });

       _assertCollateralInvariants();

        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 4_225.052380000077218250 * 1e18);

        // borrower exits from auction by regular take
        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      101.346184596990929201 * 1e18,
            givenAmount:     9_236.603649496932514865 * 1e18,
            collateralTaken: 1.000000000000000000 * 1e18,
            isReward:        false
        });

        assertEq(_quote.balanceOf(_borrower),      7_500.903066211834660554 * 1e18);
        assertEq(_quote.balanceOf(address(_pool)), 13_461.656029497009733115 * 1e18);

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
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

       _assertCollateralInvariants();

        // remaining token is moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 1);

        // buckets with collateral
        _assertBucket({
            index:        2000,
            lpBalance:    999.949771689497717000 * 1e18,
            collateral:   0.021377546506154720 * 1e18,
            deposit:      0.000000000000024123 * 1e18,
            exchangeRate: 1.000020312131928292 * 1e18
        });
        _assertBucket({
            index:        2278,
            lpBalance:    11_441.399619901522216594 * 1e18,
            collateral:   0.978622453493845280 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000001 * 1e18
        });

        // the 2 NFTs (one taken, one claimed) are owned by lender
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1),address(_pool));

       _assertCollateralInvariants();

        // borrower2 exits from auction by deposit take
        skip(3.2 hours);
        _assertBucket({
            index:        2500,
            lpBalance:    7_999.634703196347032000 * 1e18,
            collateral:   0 * 1e18,
            deposit:      13_293.276533507005404455 * 1e18,
            exchangeRate: 1.661735445019198470 * 1e18
        });

        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2500,
            collateralArbed:  2.641774864645406157 * 1e18,
            quoteTokenAmount: 10_206.904997350989042985 * 1e18,
            bondChange:       3.376910369914579034 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    2.032141649575679124 * 1e18
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
                totalBondEscrowed: 112.526190000038609125 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

       // lender adds liquidity in bucket 2286 and merge / removes remaining NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2278
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  40_000 * 1e18,
            index:   2000
        });

        // pool owns borrower2's collateral pre-merge and remove
        assertEq(_collateral.ownerOf(51), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));
        assertEq(_collateral.ownerOf(73), address(_pool));

        uint256[] memory removalIndexes = new uint256[](3);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2278;
        removalIndexes[2] = 2501;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2286,
            noOfNFTsToRemove:        1,
            collateralMerged:        1 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        // lender removes collateral
        _assertBucket({
            index:        2500,
            lpBalance:    8_001.666844845922711124 * 1e18,
            collateral:   2.641774864645406157 * 1e18,
            deposit:      3_089.860880462677483506 * 1e18,
            exchangeRate: 1.661749499903067308 * 1e18
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  10_000 * 1e18,
            index:   2576
        });
        _assertBucket({
            index:        2576,
            lpBalance:    9_999.497716894977170000 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      9_999.497716894977169999 * 1e18,
            exchangeRate: 1.000000000000000000 * 1e18
        });
        _assertBucket({
            index:        2502,
            lpBalance:    1_999.908675799086758000 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      3_323.347241860937986864 * 1e18,
            exchangeRate: 1.661749499903067308 * 1e18
        });
        _assertBucket({
            index:        2501,
            lpBalance:    2_828.657081073845584103 * 1e18,
            collateral:   0.358225135354593843 * 1e18,
            deposit:      3_323.347241860937986864 * 1e18,
            exchangeRate: 1.661749499903067308 * 1e18
        });
        removalIndexes[0] = 2500;
        removalIndexes[1] = 2501;
        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 2502,
            noOfNFTsToRemove:        3,
            collateralMerged:        3 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0 * 1e18
        });

        // lender owns collateral post-merge and remove
        assertEq(_collateral.ownerOf(51), _lender);
        assertEq(_collateral.ownerOf(53), _lender);
        assertEq(_collateral.ownerOf(73), _lender);

        _removeAllLiquidity({
            from:     _lender,
            amount:   3_323.347241860937986864 * 1e18,
            index:    2502,
            newLup:   MAX_PRICE,
            lpRedeem: 1_999.908675799086758000 * 1e18
        });

        _removeAllLiquidity({
            from:     _borrower2,
            amount:   1_377.172248010795027155 * 1e18,
            index:    2501,
            newLup:   MAX_PRICE,
            lpRedeem: 828.748405274758826103 * 1e18
        });

       _removeAllLiquidity({
            from:     _borrower,
            amount:   11_441.399619901522216594 * 1e18,
            index:    2278,
            newLup:   MAX_PRICE,
            lpRedeem: 11_441.399619901522216594 * 1e18
        });

        _assertBucket({
            index:        2500,
            lpBalance:    1_859.402323059470972038 * 1e18,
            collateral:   0,
            deposit:      3_089.860880462677483506 * 1e18,
            exchangeRate: 1.661749499903067308 * 1e18
        });
        _assertBucket({
            index:        2576,
            lpBalance:    9_999.497716894977170000 * 1e18,
            collateral:   0,
            deposit:      9_999.497716894977169999 * 1e18,
            exchangeRate: 1.000000000000000000 * 1e18
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
            borrowert0Np:              2_893.468345572160133444 * 1e18,
            borrowerCollateralization: 0.727274117376371889 * 1e18
        });

        // borrowers exits from auction by bucket take: lender adds quote token at a higher priced bucket and calls deposit take
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  60_000 * 1e18,
            index:   2000
        });

        skip(32 hours);

        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2502,
            collateralArbed:  0.878616868279129171 * 1e18,
            quoteTokenAmount: 3_360.978096272017407037 * 1e18,
            bondChange:       37.576877470760315517 * 1e18,
            isReward:         true,
            lpAwardTaker:     0,
            lpAwardKicker:    22.612473883102005275 * 1e18
        });

        _assertBucket({
            index:        2502,
            lpBalance:    2_022.521149682188763275 * 1e18,
            collateral:   0.878616868279129171 * 1e18,
            deposit:      0.000000000000001612 * 1e18,
            exchangeRate: 1.661776489605633371 * 1e18
        }); 
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              6_743.269509053983393196 * 1e18,
            borrowerCollateral:        1.121383131720870829 * 1e18,
            borrowert0Np:              3_456.840697666413087238 * 1e18,
            borrowerCollateralization: 7.479616124596050273 * 1e18
        });

        _assertCollateralInvariants();

        // bucket take on borrower
        _depositTake({
            from:             _lender,
            borrower:         _borrower,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.146617724350579337 * 1e18,
            quoteTokenAmount: 6_858.286469719939684040 * 1e18,
            bondChange:       76.677973777304187687 * 1e18,
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
                totalBondEscrowed: 148.374406222773030563 * 1e18,
                auctionPrice:      0,
                debtInAuction:     10_066.670727855240484714 * 1e18,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5475,
            lpBalance:    0.001354767131866582 * 1e18,
            collateral:   0.974765407370291492 * 1e18,
            deposit:      0,
            exchangeRate: 1.000000000000000024 * 1e18
        });

        // bucket take on borrower 2
        _depositTake({
            from:             _lender,
            borrower:         _borrower2,
            kicker:           _lender,
            index:            2000,
            collateralArbed:  0.218877853231731145 * 1e18,
            quoteTokenAmount: 10_238.373470803340954507 * 1e18,
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
                totalBondEscrowed: 35.848216222734421438 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBucket({
            index:        5565,
            lpBalance:    0.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      0,
            exchangeRate: 1.0000000000000000000 * 1e18
        });

        _assertCollateralInvariants();

        // tokens used to settle auction are moved to pool claimable array
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(0), 3);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(1), 1);
        assertEq(ERC721Pool(address(_pool)).bucketTokenIds(2), 73);

        _assertBucket({
            index:        2000,
            lpBalance:    59_996.986301369863020000 * 1e18,
            collateral:   0.365495577582310482 * 1e18,
            deposit:      42_903.026973134782007115 * 1e18,
            exchangeRate: 1.000045012465703431 * 1e18
        });

        // lender adds liquidity in bucket 6171 and 6252 and merge / removes the other 3 NFTs
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  2_000 * 1e18,
            index:   5475
        });
        _addLiquidityNoEventCheck({
            from:    _lender,
            amount:  2_000 * 1e18,
            index:   5565
        });
        uint256[] memory removalIndexes = new uint256[](4);
        removalIndexes[0] = 2000;
        removalIndexes[1] = 2502;
        removalIndexes[2] = 5475;
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
            amount:   0.001354767131866582 * 1e18,
            index:    5475,
            newLup:   MAX_PRICE,
            lpRedeem: 0.001354767131866582 * 1e18
        });

        _removeAllLiquidity({
            from:     _borrower2,
            amount:   0.001085634145829627 * 1e18,
            index:    5475,
            newLup:   MAX_PRICE,
            lpRedeem: 0.001085634145829627 * 1e18
        });

        // remove lps for both borrower and borrower 2
        _removeAllLiquidity({
            from:     _lender,
            amount:   1_999.909589041095890000 * 1e18,
            index:    5565,
            newLup:   MAX_PRICE,
            lpRedeem: 1_999.909589041095890000 * 1e18
        });
    }
}
