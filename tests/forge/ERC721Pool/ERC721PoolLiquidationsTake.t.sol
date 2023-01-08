// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolLiquidationsTakeTest is ERC721HelperContract {

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
        
        skip(5.5 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));
        // before take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_999.772712801701582812 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119.8 * 1e18);
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298417188 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 5.5 hours,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      16.875213515338743424 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.506739514062665877 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.013479028125331754 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861858811639550854 * 1e18
            }
        );

        uint256 snapshot = vm.snapshot();

        /****************************************/
        /* Take partial collateral tokens (1) ***/
        /****************************************/

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   1,
                bondChange:      0.168752135153387434 * 1e18,
                givenAmount:     16.875213515338743424 * 1e18,
                collateralTaken: 1.0 * 1e18,
                isReward:        false
            }
        );

        _assertPool(
            PoolParams({
                htp:                  8.887140410855539624 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.000966222327608000 * 1e18,
                pledgedCollateral:    4 * 1e18,
                encumberedCollateral: 2.517692578855560848 * 1e18,
                poolDebt:             24.968422683457442924 * 1e18,
                actualUtilization:    0.000342033182917498 * 1e18,
                targetUtilization:    0.811350329890505142 * 1e18,
                minDebtAmount:        1.248421134172872146 * 1e18,
                loans:                2,
                maxBorrower:          address(_borrower),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              7.749209044755361552 * 1e18,
                borrowerCollateral:        1 * 1e18,
                borrowert0Np:              7.061045370627448273 * 1e18,
                borrowerCollateralization: 1.279767365438131935 * 1e18
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
                thresholdPrice:    7.749209044755361552 * 1e18,
                neutralPrice:      0
            })
        );

        _assertKicker(
            {
                kicker:    address(0),
                claimable: 0,
                locked:    0
            }
        );

        // after take: one NFT pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), address(_pool));
        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_982.897499286362839388 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 119.8 * 1e18); // no additional tokens as there is no rounding of collateral taken (1)

        vm.revertTo(snapshot);

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2,
                bondChange:      0.227287198298417188 * 1e18,
                givenAmount:     24.624422560094104976 * 1e18,
                collateralTaken: 1.459206577606363895 * 1e18, // not a rounded collateral, difference of 2 - 1.16 collateral should go to borrower in quote tokens at auction price
                isReward:        false
            }
        );

        _assertPool(
            PoolParams({
                htp:                  6.582588772946404613 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.000966222327608000 * 1e18,
                pledgedCollateral:    3.0 * 1e18,
                encumberedCollateral: 1.736300564176668638 * 1e18,
                poolDebt:             17.219213638702081372 * 1e18,
                actualUtilization:    0.000235879635764245 * 1e18,
                targetUtilization:    0.811350329890505142 * 1e18,
                minDebtAmount:        1.721921363870208137 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 5.5 hours
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertKicker(
            {
                kicker:    address(0),
                claimable: 0,
                locked:    0 * 1e18
            }
        );

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);
        // after take: check quote token balances of taker and borrower
        assertEq(_quote.balanceOf(_lender), 46_966.022285771024095971 * 1e18);
        assertEq(_quote.balanceOf(_borrower), 128.926004470583381865 * 1e18); // borrower gets quote tokens from the difference of rounded collateral (2) and needed collateral (1.16) at auction price (19.8) = 16.6 additional tokens
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
        
        skip(10 hours);

        // before take: NFTs pledged by auctioned borrower are owned by the pool
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(1), address(_pool));
        // before take: check quote token balances of taker
        assertEq(_quote.balanceOf(_lender), 46_999.772712801701582812 * 1e18);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298417188 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      0.745786119416681408 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.507005511971773436 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.014011023943546872 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861838888763733724 * 1e18
            }
        );

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/
        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2,
                bondChange:      0.014915722388333628 * 1e18,
                givenAmount:     1.491572238833362816 * 1e18,
                collateralTaken: 2 * 1e18,
                isReward:        true
            }
        );


        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);
        // after take : Taker quote token used for buying collateral
        assertEq(_quote.balanceOf(_lender), 46_998.281140562868219996 * 1e18);

        _assertPool(
            PoolParams({
                htp:                  6.582893111996772890 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.001756788173660000 * 1e18,
                pledgedCollateral:    3 * 1e18,
                encumberedCollateral: 4.070504644882883983 * 1e18,
                poolDebt:             40.367946969368016673 * 1e18,
                actualUtilization:    0,
                targetUtilization:    0.811350329890505142 * 1e18,
                minDebtAmount:        4.036794696936801667 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower2),
                interestRate:         0.045 * 1e18,
                interestRateUpdate:   block.timestamp - 10 hours
            })
        );

        // Borrower collateral is 0 and some debt is still to be paid
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.148335279174565965 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.242202920686750816 * 1e18,
                bondFactor:        0.010000000000000000 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.917184843435912074 * 1e18, 
                totalBondEscrowed: 0.242202920686750816 * 1e18,
                auctionPrice:      0.745786119416681408 * 1e18,
                debtInAuction:     23.148335279174565965 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        // kicker bond is locked as auction is not cleared
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.242202920686750816 * 1e18
            }
        );

        _settle(
            {
                from:        _lender,
                borrower:    _borrower,
                maxDepth:    10,
                settledDebt: 20.183898781290497858 * 1e18
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
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0.242202920686750816 * 1e18,
                locked:    0
            }
        );

        // Kicker claims bond + reward
        changePrank(_lender);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 46_998.523343483554970812 * 1e18);
    }

    function testTakeCollateralSubsetPoolAndSettleByRepayAndPledge() external tearDown {
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

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.012828827714740289 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861883162446546169 * 1e18
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

        // skip enough time to accumulate debt and take to not settle auction
        skip(50 hours);

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   1,
                bondChange:      0.000000000000006781 * 1e18,
                givenAmount:     0.000000000000678144 * 1e18,
                collateralTaken: 1 * 1e18,
                isReward:        true
            }
        );
        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.227287198298423969 * 1e18,
                bondFactor:        0.01 * 1e18,
                kickTime:          block.timestamp - 50 hours,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298423969 * 1e18,
                auctionPrice:      0.000000000000678144 * 1e18,
                debtInAuction:     24.630052245331353428 * 1e18,
                thresholdPrice:    24.630052245331353428 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        uint256 snapshot = vm.snapshot();
        // borrower repays debt in order to exit from auction
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    25 * 1e18,
            amountRepaid:     24.630052245331353428 * 1e18,
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
                borrowerCollateral:        1 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        vm.revertTo(snapshot);

        // borrower repays part of debt, but not enough to exit from auction
        _repayDebt({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    5 * 1e18,
            amountRepaid:     5 * 1e18,
            collateralToPull: 0,
            newLup:           _priceAt(3696)
        });
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
                thresholdPrice:    9.815026122665676714 * 1e18,
                neutralPrice:      0
            })
        );
        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              19.630052245331353428 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              8.902861174861655548 * 1e18,
                borrowerCollateralization: 1.010408400292926569 * 1e18
            }
        );
    }
}