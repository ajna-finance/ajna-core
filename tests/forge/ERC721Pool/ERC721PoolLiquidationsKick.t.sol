// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsKickTest is ERC721HelperContract {

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

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 2_000 * 1e18,
                index:  _i9_91
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 5_000 * 1e18,
                index:  _i9_81
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 11_000 * 1e18,
                index:  _i9_72
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 25_000 * 1e18,
                index:  _i9_62
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 30_000 * 1e18,
                index:  _i9_52
            }
        );

       // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower,
                amount:     19.8 * 1e18,
                indexLimit: _i9_91,
                newLup:     9.917184843435912074 * 1e18
            }
        );

        // second borrower deposits three NFTs into the subset pool and borrows
        tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 51;
        tokenIdsToAdd[1] = 53;
        tokenIdsToAdd[2] = 73;
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                tokenIds: tokenIdsToAdd
            }
        );
        _borrow(
            {
                from:       _borrower2,
                amount:     15 * 1e18,
                indexLimit: _i9_72,
                newLup:     9.917184843435912074 * 1e18
            }
        );

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
                actualUtilization:    0.000477170706006322 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        1.741673076923076924 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.819038461538461548 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 1.000773560501591181 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              15.014423076923076930 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowert0Np:              5.255048076923076925 * 1e18,
                borrowerCollateralization: 1.981531649793150539 * 1e18
            }
        );
        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);
    }

    function testKickSubsetPool() external tearDown {

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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      0
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              22.728719829841718804 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.872656701977127996 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           23.012828827714740289 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.227287198298417188 * 1e18,
                transferAmount: 0.227287198298417188 * 1e18
            }
        );

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  6.582216822103492762 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 4.056751649452525709 * 1e18,
                poolDebt:             40.231555971534224231 * 1e18,
                actualUtilization:    0.000551117205089510 * 1e18,
                targetUtilization:    0.811350329890505142 * 1e18,
                minDebtAmount:        4.023155597153422423 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.012828827714740289 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861883162446546169 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              17.218727143819483942 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowert0Np:              5.255048076923076925 * 1e18,
                borrowerCollateralization: 1.727860269914713433 * 1e18
            }
        );
        assertEq(_quote.balanceOf(_lender), 46_999.772712801701582812 * 1e18);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298417188 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      381.842493141340875904 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.506414413857370144 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.227287198298417188 * 1e18
            }
        );

        // kick should fail if borrower in liquidation
        _assertKickAuctionActiveRevert(
            {
                from:       _lender,
                borrower:   _borrower
            }
        );

        // kick should fail if borrower properly collateralized
        _assertKickCollateralizedBorrowerRevert(
            {
                from:       _lender,
                borrower:   _borrower2
            }
        );

        // check locked pool actions if auction kicked for more than 72 hours and auction head not cleared
        skip(80 hours);
        _assertRemoveLiquidityAuctionNotClearedRevert(
            {
                from:   _lender,
                amount: 1_000 * 1e18,
                index:  _i9_91
            }
        );
        _assertRemoveCollateralAuctionNotClearedRevert(
            {
                from:   _lender,
                amount: 10 * 1e18,
                index:  _i9_91
            }
        );
    }

    function testKickSubsetPoolAndSettleByRepayAndPledge() external tearDown {
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
                kickMomp:          0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    11.364359914920859402 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              22.728719829841718804 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.872656701977127996 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           23.012828827714740289 * 1e18,
                collateral:     2 * 1e18,
                bond:           0.227287198298417188 * 1e18,
                transferAmount: 0.227287198298417188 * 1e18
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298417188 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      381.842493141340875904 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.506414413857370144 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.012828827714740289 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861883162446546169 * 1e18
            }
        );

        uint256 snapshot = vm.snapshot();
        // borrower repays debt in order to exit from auction
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    25 * 1e18,
            amountRepaid:     23.012828827714740289 * 1e18,
            collateralToPull: 0,
            newLup:           _priceAt(3696)
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
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        vm.revertTo(snapshot);

        // borrower pledge one more NFT to exit from auction
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 5;
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
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
                thresholdPrice:    7.670942942571580096 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.012828827714740289 * 1e18,
                borrowerCollateral:        3 * 1e18,
                borrowert0Np:              6.989927127403846156 * 1e18,
                borrowerCollateralization: 1.292824743669819254 * 1e18
            }
        );
    }

}