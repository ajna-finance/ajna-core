// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import { NFTNoopTakeExample } from "../../interactions/NFTTakeExample.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _withdrawRecipient;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _borrower2         = makeAddr("borrower2");
        _lender            = makeAddr("lender");
        _withdrawRecipient = makeAddr("withdrawRecipient");

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
            newLup:     9.917184843435912074 * 1e18
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
            newLup:     9.917184843435912074 * 1e18
        });

        /*****************************/
        /*** Assert pre-kick state ***/
        /*****************************/

        _assertPool(
            PoolParams({
                htp:                  9.889500000000000005 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
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
    }

    function testTakeCollateralSubsetPool() external tearDown {
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
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.810387715504679661 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874423213519591818 * 1e18
        });

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

        assertEq(_quote.balanceOf(_lender), 46_999.756152452262525972 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      3_228.008668236108393472 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.243847547737474028 * 1e18
        });
        
        skip(5.5 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        // before take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_999.756152452262525972 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119 * 1e18);

        // debt to collateral increases slightly due to interest
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 5.5 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      14.995198732643899296 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.811003942355969738 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874398508418213347 * 1e18
        });

        uint256 snapshot = vm.snapshot();

        /****************************************/
        /* Take partial collateral tokens (1) ***/
        /****************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      0.167651418511552261 * 1e18,
            givenAmount:     14.995198732643899296 * 1e18,
            collateralTaken: 1.0 * 1e18,
            isReward:        false
        });

        // borrower still under liquidation
        _assertPool(
            PoolParams({
                htp:                  5.969327394750054875 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.914563174737216441 * 1e18,
                pledgedCollateral:    4 * 1e18,
                encumberedCollateral: 2.546887671650764282 * 1e18,
                poolDebt:             24.286495976181480207 * 1e18,
                actualUtilization:    0.000403556882317336 * 1e18,
                targetUtilization:    0.754866915220293599 * 1e18,
                minDebtAmount:        2.428649597618148021 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              7.067282337479398835 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              7.125397766163924279 * 1e18,
            borrowerCollateralization: 1.349281690159688237 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.076196129225921767 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 5.5 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.076196129225921767 * 1e18,
                auctionPrice:      14.995198732643899296 * 1e18,
                debtInAuction:     7.067282337479398835 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertKicker({
            kicker:    address(0),
            claimable: 0,
            locked:    0
        });

        // after take: one NFT pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), address(_pool));

        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_984.760953719618626676 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119 * 1e18); // no additional tokens as there is no rounding of collateral taken (1)

        vm.revertTo(snapshot);

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      0.243847547737474028 * 1e18,
            givenAmount:     22.183024574062103590 * 1e18,
            collateralTaken: 2.0 * 1e18,
            isReward:        false
        });

        _assertPool(
            PoolParams({
                htp:                  5.969327394750054875 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.914563174737216441 * 1e18,
                pledgedCollateral:    3.0 * 1e18,
                encumberedCollateral: 1.805752586743735384 * 1e18,
                poolDebt:             17.219213638702081372 * 1e18,
                actualUtilization:    0.000403556882317336 * 1e18,
                targetUtilization:    0.754866915220293599 * 1e18,
                minDebtAmount:        1.721921363870208137 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

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
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertKicker({
            kicker:    address(0),
            claimable: 0,
            locked:    0 * 1e18
        });

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_969.765754986974727382 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 126.807372891225695000 * 1e18); // borrower gets quote tokens from the difference of rounded collateral (2) and needed collateral (1.49) at auction price (15.5) = 7.9 additional tokens
    }

    function testTakeCollateralAndSettleSubsetPool() external tearDown {
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
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.810387715504679661 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874423213519591818 * 1e18
        });

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

        assertEq(_quote.balanceOf(_lender), 46_999.756152452262525972 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      3_228.008668236108393472 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.243847547737474028 * 1e18
        });
        
        skip(10 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));

        // before take: check quote token balances of taker
        assertEq(_quote.balanceOf(_lender), 46_999.756152452262525972 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      3.152352215074324604 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.811508140911704231 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874378295672619020 * 1e18
        });

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2,
            bondChange:      0.070488738419282267 * 1e18,
            givenAmount:     6.304704430148649208 * 1e18,
            collateralTaken: 2 * 1e18,
            isReward:        true
        });

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);

        // after take: Taker quote token used for buying collateral
        assertEq(_quote.balanceOf(_lender), 46_993.451448022113876764 * 1e18);

        _assertPool(
            PoolParams({
                htp:                  5.969465385933729579 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.915330108312950970 * 1e18,
                pledgedCollateral:    3 * 1e18,
                encumberedCollateral: 3.439361153737805799 * 1e18,
                poolDebt:             32.796904139375787999 * 1e18,
                actualUtilization:    0.000365195584296466 * 1e18,
                targetUtilization:    0.751903493883837161 * 1e18,
                minDebtAmount:        3.279690413937578800 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        // Borrower collateral is 0 and some debt is still to be paid
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              15.577292449182337291 * 1e18,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 0
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.314336286156756295 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                referencePrice:    12.609408860297298412 * 1e18, 
                totalBondEscrowed: 0.314336286156756295 * 1e18,
                auctionPrice:      3.152352215074324604 * 1e18,
                debtInAuction:     15.577292449182337291 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        // kicker bond is locked as auction is not cleared
        _assertKicker({
            kicker:    _lender,
            claimable: 0,
            locked:    0.314336286156756295 * 1e18
        });

        // settle auction
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 15.577292449182337290 * 1e18
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
                totalBondEscrowed: 0.314336286156756295 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertKicker({
            kicker:    _lender,
            claimable: 0.314336286156756295 * 1e18,
            locked:    0
        });

        changePrank(_lender);
        skip(1 minutes);
        // Kicker claims bond + reward and transfer to a different address
        _pool.withdrawBonds(_withdrawRecipient, 0.1 * 1e18);
        assertEq(_quote.balanceOf(_withdrawRecipient), 0.1 * 1e18);

        // Kicker claims remaining bond + reward to his own address
        _pool.withdrawBonds(_lender, type(uint256).max);
        assertEq(_quote.balanceOf(_lender), 46_993.665784308270633059 * 1e18);
    }

    function testTakeCollateralSubsetPoolAndSettleWithDebt() external tearDown {
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
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.810387715504679661 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874423213519591818 * 1e18
        }); 

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           21.810387715504679660 * 1e18,
            collateral:     2 * 1e18,
            bond:           0.243847547737474028 * 1e18,
            transferAmount: 0.243847547737474028 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.810387715504679661 * 1e18,
            borrowerCollateral:        2 * 1e18,
            borrowert0Np:              10.995179713174208507 * 1e18,
            borrowerCollateralization: 0.874423213519591818 * 1e18
        });
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737474028 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737474028 * 1e18,
                auctionPrice:      3_228.008668236108393472 * 1e18,
                debtInAuction:     21.810387715504679661 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );

        // skip enough time to accumulate debt and take to not settle auction
        skip(50 hours);

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1,
            bondChange:      0.000000000000128218 * 1e18,
            givenAmount:     0.000000000011468190 * 1e18,
            collateralTaken: 1 * 1e18,
            isReward:        true
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737602246 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 50 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737602246 * 1e18,
                auctionPrice:      0.000000000011468190 * 1e18,
                debtInAuction:     21.815990418133811604 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.815990418133811604 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              21.990359426336986406 * 1e18,
            borrowerCollateralization: 0.437099323678820406 * 1e18
        });

        // confirm borrower cannot repay while in liquidation
        _assertRepayAuctionActiveRevert(_borrower, 25 * 1e18);

        // confirm borrower cannot recollateralize while in liquidation
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 5;
        _assertPledgeCollateralAuctionActiveRevert(_borrower, tokenIdsToAdd);

        // ensure auction state did not change
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.243847547737602246 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 50 hours,
                referencePrice:    12.609408860297298412 * 1e18,
                totalBondEscrowed: 0.243847547737602246 * 1e18,
                auctionPrice:      0.000000000011468190 * 1e18,
                debtInAuction:     21.815990418133811604 * 1e18,
                debtToCollateral:  10.905193857752339830 * 1e18,
                neutralPrice:      12.609408860297298412 * 1e18
            })
        );
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              21.815990418133811604 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              21.990359426336986406 * 1e18,
            borrowerCollateralization: 0.437099323678820406 * 1e18
        });

        // settle the auction with debt
        skip(22 hours + 1);
        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    10,
            settledDebt: 21.818209514194938031 * 1e18
        });
    }

    function testTakeCollateralWithAtomicSwapSubsetPool() external tearDown {
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

        skip(5.5 hours);

        uint256 initialBalance = 10_000 * 1e18;

        // instantiate a NOOP taker contract which implements IERC721Taker
        NFTNoopTakeExample taker = new NFTNoopTakeExample();
        deal(address(_quote), address(taker), initialBalance);
        changePrank(address(taker));
        _quote.approve(address(_pool), type(uint256).max);

        bytes memory data = abi.encode(address(_pool));
        _pool.take(_borrower, 2, address(taker), data);

        // check that token ids are the same as id pledged by borrower
        assertEq(taker.tokenIdsReceived(0), 3);
        assertEq(taker.tokenIdsReceived(1), 1);

        // check that the amount of quote tokens passed to taker contract is the same as the one deducted from taker balance
        uint256 currentBalance = _quote.balanceOf(address(taker));
        assertEq(initialBalance - taker.quoteAmountDueReceived(), currentBalance);

        // check address received is the address of current ajna pool
        assertEq(taker.poolAddressReceived(), address(_pool));
    }
}

contract ERC721PoolLiquidationsHighTakeTest is ERC721HelperContract {

    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _startTest();

        _borrower          = makeAddr("borrower");
        _lender            = makeAddr("lender");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](2);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 2;

        _pool = _deploySubsetPool(subsetTokenIds);

       _mintAndApproveQuoteTokens(_lender,    300_000_000_000 * 1e18);
       _mintAndApproveQuoteTokens(_borrower,  100 * 1e18);

       _mintAndApproveCollateralTokens(_borrower,  6);

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _lender,
            amount: 1_000_000_000.0 * 1e18,
            index:  1
        });

       // first borrower adds collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 1;

        // borrower deposits one NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     960_550_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });


        skip(100 days);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              974_735_101.867470788027259956 * 1e18,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              1_111_728_407.735735366471916722 * 1e18,
            borrowerCollateralization: 0.986430865620282143 * 1e18
        });
    }


    function testTakeHighPrice() external tearDown {

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           974_735_101.867470788027259955 * 1e18,
            collateral:     1 * 1e18,
            bond:           10_897_869.739154233968795067 * 1e18,
            transferAmount: 10_897_869.739154233968795067 * 1e18
        });

        skip(1 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          10_897_869.739154233968795067 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 1 minutes,
                referencePrice:    1_127_062_351.229373656878717077 * 1e18,
                totalBondEscrowed: 10_897_869.739154233968795067 * 1e18,
                auctionPrice:      278_699_640_324.071955737458053632 * 1e18, // auction price exceeds top bucket
                debtInAuction:     974_735_101.867470788027259956 * 1e18,
                debtToCollateral:  974_735_101.867470788027259955 * 1e18,
                neutralPrice:      1_127_062_351.229373656878717077 * 1e18
            })
        );

        // top bucket price
        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      10_897_869.739154233968795067 * 1e18,
            givenAmount:     991_360_820.988112939930817798 * 1e18,
            collateralTaken: 1.0 * 1e18,
            isReward:        false
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
                totalBondEscrowed: 0,
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
            borrowerCollateralization: 1.0 * 1e18
        });

        assertEq(_collateral.ownerOf(1), address(_lender));
    }

    function testTakeMultipleNFTHighPrice() external tearDown {

        _addLiquidity({
            from:    _lender,
            amount:  1_000_000_000.0 * 1e18,
            index:   1,
            lpAward: 988_807_719.662757027238723574 * 1e18,
            newLup:  999_969_141.897027226245329498 * 1e18
        });

        // first borrower adds another collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 2;

        // borrower deposits and additional NFT into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        _borrow({
            from:       _borrower,
            amount:     947_300_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_922_945_967.252086173079859956 * 1e18,
            borrowerCollateral:        2.000000000000000000 * 1e18,
            borrowert0Np:              1_096_602_376.501712863397587463 * 1e18,
            borrowerCollateralization: 1.000037241461975329 * 1e18
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
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        skip(1 days);

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_180_947.482590772745713575 * 1e18,
            exchangeRate: 1.011272786422610071 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           1_923_209_402.550975799525343720 * 1e18,
            collateral:     2 * 1e18,
            bond:           21_502_134.795353695767188920 * 1e18,
            transferAmount: 21_502_134.795353695767188920 * 1e18
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_041.846142986663199620 * 1e18,
            exchangeRate: 1.011398540211305519 * 1e18
        });

        skip(1 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          21_502_134.795353695767188920 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp - 1 minutes,
                referencePrice:    1_111_879_990.262346637742836677 * 1e18,
                totalBondEscrowed: 21_502_134.795353695767188920 * 1e18,
                auctionPrice:      274_945_350_655.745057322116218624 * 1e18, // auction price exceeds top bucket
                debtInAuction:     1_923_209_402.550975799525343721 * 1e18,
                debtToCollateral:  961_604_701.275487899762671860 * 1e18,
                neutralPrice:      1_111_879_990.262346637742836677 * 1e18
            })
        );

        // top bucket price
        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   1 * 1e18,
            bondChange:      21_502_134.795353695767188920 * 1e18,
            givenAmount:     1_956_012_919.399533852112525653 * 1e18,
            collateralTaken: 1.0 * 1e18,
            isReward:        false
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_215.177575407462265845 * 1e18,
            exchangeRate: 1.011398627366745639 * 1e18
        });

        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(2), address(_lender));

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

    }

    function testLenderKickTakeHighPrice() external tearDown {

        _addLiquidity({
            from:    _lender,
            amount:  1_000_000_000.0 * 1e18,
            index:   1,
            lpAward: 988_807_719.662757027238723574 * 1e18,
            newLup:  999_969_141.897027226245329498 * 1e18
        });

        // first borrower adds another collateral token and borrows
        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 2;

        // borrower deposits two NFTs into the subset pool and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     947_300_000.0 * 1e18,
            indexLimit: _i9_91,
            newLup:     999_969_141.897027226245329498 * 1e18
        });
        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_922_945_967.252086173079859956 * 1e18,
            borrowerCollateral:        2.000000000000000000 * 1e18,
            borrowert0Np:              1_096_602_376.501712863397587463 * 1e18,
            borrowerCollateralization: 1.000037241461975329 * 1e18
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
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        skip(1 days);

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_180_947.482590772745713575 * 1e18,
            exchangeRate: 1.011272786422610071 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days
        });

        _lenderKick({
            from:       _lender,
            index:      1,
            borrower:   _borrower,
            debt:       1_923_209_402.550975799525343720 * 1e18,
            collateral: 2.00000000000000000 * 1e18,
            bond:       21_502_134.795353695767188920 * 1e18
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_041.846142986663199620 * 1e18,
            exchangeRate: 1.011398540211305519 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              1_923_209_402.550975799525343721 * 1e18,
            borrowerCollateral:        2.0 * 1e18,
            borrowert0Np:              1_096_602_376.501712863397587463 * 1e18,
            borrowerCollateralization: 0.999900259441579706 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          21_502_134.795353695767188920 * 1e18,
                bondFactor:        0.011180339887498948 * 1e18,
                kickTime:          block.timestamp,
                referencePrice:    1111879990.262346637742836677 * 1e18,
                totalBondEscrowed: 21_502_134.795353695767188920 * 1e18,
                auctionPrice:      284_641_277_507.160739262166189312 * 1e18, // auction price exceeds top bucket
                debtInAuction:     1_923_209_402.550975799525343721 * 1e18,
                debtToCollateral:  961_604_701.275487899762671860 * 1e18,
                neutralPrice:      1111879990.262346637742836677 * 1e18
            })
        );

        // top bucket price
        assertEq(1_004_968_987.606512354182109771 * 1e18, _priceAt(0));

        skip(1 minutes);

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      21_502_134.795353695767188920 * 1e18,
            givenAmount:     1_956_012_919.399533852112525653 * 1e18,
            collateralTaken: 1.0 * 1e18,
            isReward:        false
        });

        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(2), address(_lender));

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            false,
                kicker:            address(0),
                bondSize:          0,
                bondFactor:        0,
                kickTime:          0,
                referencePrice:    0,
                totalBondEscrowed: 0,
                auctionPrice:      0,
                debtInAuction:     0,
                debtToCollateral:  0,
                neutralPrice:      0
            })
        );

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1.0 * 1e18,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18
        });

        _assertBucket({
            index:        1,
            lpBalance:    1_988_762_057.562300406238723574 * 1e18,
            collateral:   0,
            deposit:      2_011_431_215.177575407462265845 * 1e18,
            exchangeRate: 1.011398627366745639 * 1e18
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       1,
            lpBalance:   1_988_762_057.562300406238723574 * 1e18,
            depositTime: block.timestamp - 1 days - 1 minutes
        });
    }
}