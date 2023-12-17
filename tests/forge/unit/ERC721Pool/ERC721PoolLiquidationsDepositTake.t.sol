// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsDepositTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;
    address internal _taker;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");
        _taker     = makeAddr("taker");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender,  120_000 * 1e18);
        _mintAndApproveQuoteTokens(_lender2, 120_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 10 * 1e18);

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

        uint256 expectedNewLup = 9.917184843435912074 * 1e18;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     19.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     expectedNewLup
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
            newLup:     expectedNewLup
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.889500000000000005 * 1e18,
                lup:                  expectedNewLup,
                poolSize:             72_996.666666666666667000 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 3.568956368038954464 * 1e18,
                poolDebt:             34.032692307692307708 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        1.701634615384615385 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              19.018269230769230778 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 1.002799417911513430 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              15.014423076923076930 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.786936691144320266 * 1e18,
            borrowerCollateralization: 1.905318894031875518 * 1e18
        });

        assertEq(_quote.balanceOf(_lender), 47_000 * 1e18);

        // Skip to make borrower undercollateralized
        skip(1000 days);

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           21.810387715504679660 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.243847547737474028 * 1e18,
            transferAmount: 0.243847547737474028 * 1e18
        });

        /******************************/
        /*** Assert Post-kick state ***/
        /******************************/

        _assertPool(
            PoolParams({
                htp:                  5.969158743190754433 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.913625835553743442 * 1e18,
                pledgedCollateral:    5 * 1e18,
                encumberedCollateral: 4.092923555878202698 * 1e18,
                poolDebt:             39.029114859324163603 * 1e18,
                actualUtilization:    0.000466222553189995 * 1e18,
                targetUtilization:    0.758474474342854060 * 1e18,
                minDebtAmount:        3.902911485932416360 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.810387715504679661 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874423213519591818 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower2,
            borrowerDebt:              17.218727143819483943 * 1e18,
            borrowerCollateral:        3 * 1e18,
            borrowert0Np:              5.786936691144320266 * 1e18,
            borrowerCollateralization: 1.661404105687224454 * 1e18
        });
    }

    function testDepositTakeNFTAndSettleAuction() external {
        _addLiquidity({
            from:    _lender,
            amount:  15.0 * 1e18,
            index:   _i1505_26,
            lpAward: 14.999383561643835615 * 1e18,
            newLup:  9.917184843435912074 * 1e18
        });

        skip(6 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      12.609408860297298412 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.811059963842150618 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874396262534517775 * 1e18
        });

        // before deposit take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        _depositTake({
            from:             _taker,
            borrower:         _borrower,
            kicker:           _lender,
            index:            _i1505_26,
            collateralArbed:  0.009964621805481374 * 1e18,
            quoteTokenAmount: 14.999383771703071343 * 1e18,
            bondChange:       0.167698208670676263 * 1e18,
            isReward:         false,
            lpAwardTaker:     0,
            lpAwardKicker:    0
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.076149339066797765 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 6 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.076149339066797765 * 1e18,
                auctionPrice:      12.609408860297298412 * 1e18,
                debtInAuction:     7.063223505145093670 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        // borrower is compensated LP for fractional collateral
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       3519,
            lpBalance:   0 * 1e18,
            depositTime: 0
        });
        _assertBucket({
            index:        _i1505_26,
            lpBalance:    14.999383561643835615 * 1e18,
            collateral:   0.009964621805481374 * 1e18,
            deposit:      0.000000000000000301 * 1e18,
            exchangeRate: 1.000000014004524598 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              7.063223505145093670 * 1e18,
            borrowerCollateral:        1.990035378194518626 * 1e18,
            borrowert0Np:              3.578472696722346497 * 1e18,
            borrowerCollateralization: 2.686661283150441203 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _taker,
            index:       _i1505_26,
            lpBalance:   0,
            depositTime: 0
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       _i1505_26,
            lpBalance:   14.999383561643835615 * 1e18,
            depositTime: block.timestamp - 6 hours
        });

        // borrower cannot repay amidst auction
        _assertRepayAuctionActiveRevert({
            from:      _borrower,
            maxAmount: 4 * 1e18
        });

        // ensure borrower is not left with fraction of NFT upon settlement
        skip(72 hours);
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    5,
            settledDebt: 7.065836413456418044 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              0 * 1e18,
            borrowerCollateralization: 1 * 1e18
        });
    }
}
