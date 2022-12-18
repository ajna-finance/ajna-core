// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/base/PoolHelper.sol';

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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 15_000 * 1e18,
                index:  2500
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  2501
            }
        );

        // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

        // borrower deposits two NFTs into the subset pool and borrows
        _drawDebtNoCheckLup(
            {
                from:           _borrower,
                borrower:       _borrower,
                amountToBorrow: 5_000 * 1e18,
                limitIndex:     5000,
                tokenIds:       tokenIdsToAdd
            }
        );

        // second borrower deposits three NFTs into the subset pool and borrows
        tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 51;
        tokenIdsToAdd[1] = 53;
        tokenIdsToAdd[2] = 73;
        // borrower deposits two NFTs into the subset pool and borrows
        _drawDebtNoCheckLup(
            {
                from:           _borrower2,
                borrower:       _borrower2,
                amountToBorrow: 5_000 * 1e18,
                limitIndex:     5000,
                tokenIds:       tokenIdsToAdd
            }
        );

    }

    function testKickAndSettleSubsetPool() external { //TODO: uncomment when test pass tearDown {

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
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              5_004.807692307692310000 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              2_627.524038461538462750 * 1e18,
                borrowerCollateralization: 1.543977154129479546 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              5_004.807692307692310000 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowert0Np:              1_751.682692307692308500 * 1e18,
                borrowerCollateralization: 2.315965731194219318 * 1e18
            }
        );
        assertEq(_quote.balanceOf(address(_pool)), 6_000 * 1e18);
        assertEq(_quote.balanceOf(_lender),        104_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      5_100 * 1e18);
        assertEq(_quote.balanceOf(_borrower2),     13_000 * 1e18);


        /***********************/
        /*** Kick both loans ***/
        /***********************/

        _kickWithDeposit(
            {
                from:               _lender,
                index:              2500,
                borrower:           _borrower,
                debt:               5_067.367788461538463875 * 1e18,
                collateral:         2 * 1e18,
                bond:               1_501.442307692307693000 * 1e18,
                removedFromDeposit: 1_501.442307692307693000 * 1e18,
                transferAmount:     0,
                lup:                3_863.654368867279344664 * 1e18
            }
        );
        _kickWithDeposit(
            {
                from:               _lender,
                index:              2500,
                borrower:           _borrower2,
                debt:               5_067.367788461538463875 * 1e18,
                collateral:         3 * 1e18,
                bond:               1_501.442307692307693000 * 1e18,
                removedFromDeposit: 1_501.442307692307693000 * 1e18,
                transferAmount:     0,
                lup:                3_863.654368867279344664 * 1e18
            }
        );

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
        // TODO FIXME settle reverts with BucketPriceOutOfBounds
        // _settle(
        //     {
        //         from:        _lender,
        //         borrower:    _borrower2,
        //         maxDepth:    1,
        //         settledDebt: 5_067.367788461538463875 * 1e18
        //     }
        // );
        // _assertAuction(
        //     AuctionParams({
        //         borrower:          _borrower2,
        //         active:            false,
        //         kicker:            address(0),
        //         bondSize:          0,
        //         bondFactor:        0,
        //         kickTime:          0,
        //         kickMomp:          0,
        //         totalBondEscrowed: 24_023.076923076923088000 * 1e18,
        //         auctionPrice:      0,
        //         debtInAuction:     81_114.914934273090436935 * 1e18,
        //         thresholdPrice:    0,
        //         neutralPrice:      0
        //     })
        // );

        // // settle borrower
        // _settle(
        //     {
        //         from:        _lender,
        //         borrower:    _borrower,
        //         maxDepth:    1,
        //         settledDebt: 20_269.471153846153855500 * 1e18
        //     }
        // );
        // _assertAuction(
        //     AuctionParams({
        //         borrower:          _borrower,
        //         active:            false,
        //         kicker:            address(0),
        //         bondSize:          0,
        //         bondFactor:        0,
        //         kickTime:          0,
        //         kickMomp:          0,
        //         totalBondEscrowed: 18_017.307692307692316000 * 1e18,
        //         auctionPrice:      0,
        //         debtInAuction:     60_836.186200704817827702 * 1e18,
        //         thresholdPrice:    0,
        //         neutralPrice:      0
        //     })
        // );
    }
}