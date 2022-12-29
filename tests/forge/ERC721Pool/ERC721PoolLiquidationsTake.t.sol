// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from "./ERC721DSTestPlus.sol";

import 'src/base/PoolHelper.sol';

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

    // TODO fix this, borrower 1 needs more collateral to pledge
    function testTakeCollateralSubsetPool() external {

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
                auctionPrice:      317.349914989949186368 * 1e18,
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
        
        skip(5 hours);

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
                kickTime:          block.timestamp - 5 hours,
                kickMomp:          9.917184843435912074 * 1e18,
                totalBondEscrowed: 0.227287198298417188 * 1e18,
                auctionPrice:      19.834369686871824160 * 1e18,
                debtInAuction:     23.012828827714740289 * 1e18,
                thresholdPrice:    11.506709959118993144 * 1e18,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              23.013419918237986289 * 1e18,
                borrowerCollateral:        2 * 1e18,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0.861861025320848319 * 1e18
            }
        );

        /**************************************/
        /*** Take all collateral tokens (2) ***/
        /**************************************/
        uint256 snapshot = vm.snapshot();

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2,
                bondChange:      0.227287198298417188 * 1e18,
                givenAmount:     39.668739373743648320 * 1e18,
                collateralTaken: 2 * 1e18, // not a rounded collateral, difference of 2 - 1.16 collateral should go to borrower in quote tokens at auction price
                isReward:        false
            }
        );

        // _assertPool(
        //     PoolParams({
        //         htp:                  6.582554958364903034 * 1e18,
        //         lup:                  9.917184843435912074 * 1e18,
        //         poolSize:             73_000.000878382806067000 * 1e18,
        //         pledgedCollateral:    3.0 * 1e18,
        //         encumberedCollateral: 2.539854773908686639 * 1e18,
        //         poolDebt:             25.188209268335572366 * 1e18,
        //         actualUtilization:    0.000345043958428149 * 1e18,
        //         targetUtilization:    0.811350329890505142 * 1e18,
        //         minDebtAmount:        2.518820926833557237 * 1e18,
        //         loans:                1,
        //         maxBorrower:          address(_borrower2),
        //         interestRate:         0.045 * 1e18,
        //         interestRateUpdate:   block.timestamp - 5 hours
        //     })
        // );

        // _assertBorrower(
        //     {
        //         borrower:                  _borrower,
        //         borrowerDebt:              7.969039857008983299 * 1e18,
        //         borrowerCollateral:        0,
        //         borrowert0Np:              10.404995192307692312 * 1e18,
        //         borrowerCollateralization: 1 * 1e18
        //     }
        // );

        // _assertAuction(
        //     AuctionParams({
        //         borrower:          _borrower,
        //         active:            true,
        //         kicker:            _lender,
        //         bondSize:          0.227287198298417188 * 1e18,
        //         bondFactor:        0.01 * 1e18,
        //         kickTime:          block.timestamp - 5 hours,
        //         kickMomp:          9.917184843435912074 * 1e18,
        //         totalBondEscrowed: 0.227287198298417188 * 1e18,
        //         auctionPrice:      19.834369686871824160 * 1e18,
        //         debtInAuction:     23.012828827714740289 * 1e18,
        //         thresholdPrice:    11.506709959118993144 * 1e18,
        //         neutralPrice:      11.932577910666902372 * 1e18
        //     })
        // );

        // _assertKicker(
        //     {
        //         kicker:    address(0),
        //         claimable: 0,
        //         locked:    0 * 1e18
        //     }
        // );

        // // after take: NFTs pledged by liquidated borrower are owned by the taker
        // assertEq(_collateral.ownerOf(3), _lender);
        // assertEq(_collateral.ownerOf(1), _lender);
        // // after take: check quote token balances of taker and borrower
        // assertEq(_quote.balanceOf(_lender), 46_960.103973427957934499 * 1e18);
        // assertEq(_quote.balanceOf(_borrower), 134.844380061229002984 * 1e18); // borrower gets quote tokens from the difference of rounded collateral (2) and needed collateral (1.16) at auction price (19.8) = 16.6 additional tokens

        // vm.revertTo(snapshot);


        // /****************************************/
        // /* Take partial collateral tokens (1) ***/
        // /****************************************/

        // _take(
        //     {
        //         from:            _lender,
        //         borrower:        _borrower,
        //         maxCollateral:   1,
        //         bondChange:      0.198343696868718242 * 1e18,
        //         givenAmount:     19.834369686871824160 * 1e18,
        //         collateralTaken: 1 * 1e18,
        //         isReward:        false
        //     }
        // );

        // _assertPool(
        //     PoolParams({
        //         htp:                  6.582554958364903034 * 1e18,
        //         lup:                  9.917184843435912074 * 1e18,
        //         poolSize:             73_000.000878382806067000 * 1e18,
        //         pledgedCollateral:    4 * 1e18,
        //         encumberedCollateral: 2.056855848178945039 * 1e18,
        //         poolDebt:             20.398219642692751196 * 1e18,
        //         actualUtilization:    0.000279427662976004 * 1e18,
        //         targetUtilization:    0.811350329890505142 * 1e18,
        //         minDebtAmount:        1.019910982134637560 * 1e18,
        //         loans:                2,
        //         maxBorrower:          address(_borrower2),
        //         interestRate:         0.045 * 1e18,
        //         interestRateUpdate:   block.timestamp - 5 hours
        //     })
        // );

        // _assertBorrower(
        //     {
        //         borrower:                  _borrower,
        //         borrowerDebt:              3.179050231366162129 * 1e18,
        //         borrowerCollateral:        1 * 1e18,
        //         borrowert0Np:              10.404995192307692312 * 1e18,
        //         borrowerCollateralization: 3.119543298054183364 * 1e18
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
        //         totalBondEscrowed: 0,
        //         auctionPrice:      0,
        //         debtInAuction:     0,
        //         thresholdPrice:    3.179050231366162129 * 1e18,
        //         neutralPrice:      0
        //     })
        // );

        // _assertKicker(
        //     {
        //         kicker:    address(0),
        //         claimable: 0,
        //         locked:    0
        //     }
        // );

        // // after take: one NFT pledged by liquidated borrower is owned by the taker
        // assertEq(_collateral.ownerOf(3), _lender);
        // assertEq(_collateral.ownerOf(1), address(_pool));
        // // after take: check quote token balances of taker and borrower
        // assertEq(_quote.balanceOf(_lender), 46_979.938343114829758652 * 1e18);
        // assertEq(_quote.balanceOf(_borrower), 119.8 * 1e18); // no additional tokens as there is no rounding of collateral taken (1)
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
                auctionPrice:      317.349914989949186368 * 1e18,
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
                auctionPrice:      0.619824052714744512 * 1e18,
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
                bondChange:      0.01239648105429489 * 1e18,
                givenAmount:     1.239648105429489024 * 1e18,
                collateralTaken: 2 * 1e18,
                isReward:        true
            }
        );

        // after take: NFTs pledged by liquidated borrower are owned by the taker
        assertEq(_collateral.ownerOf(3), _lender);
        assertEq(_collateral.ownerOf(1), _lender);
        // after take : Taker quote token used for buying collateral
        assertEq(_quote.balanceOf(_lender), 46_998.533064696272093788 * 1e18);

        _assertPool(
            PoolParams({
                htp:                  6.582893111996772890 * 1e18,
                lup:                  9.917184843435912074 * 1e18,
                poolSize:             73_000.001756788173660000 * 1e18,
                pledgedCollateral:    3 * 1e18,
                encumberedCollateral: 6.416272751787860151 * 1e18,
                poolDebt:             63.631362885381398599 * 1e18,
                actualUtilization:    0,
                targetUtilization:    0.811350329890505142 * 1e18,
                minDebtAmount:        6.363136288538139860 * 1e18,
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
                borrowerDebt:              46.411751195187947890 * 1e18,
                borrowerCollateral:        0,
                borrowert0Np:              10.404995192307692312 * 1e18,
                borrowerCollateralization: 0 * 1e18
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            _lender,
                bondSize:          0.239683679352712078 * 1e18,
                bondFactor:        0.010000000000000000 * 1e18,
                kickTime:          block.timestamp - 10 hours,
                kickMomp:          9.917184843435912074 * 1e18, 
                totalBondEscrowed: 0.239683679352712078 * 1e18,
                auctionPrice:      0.619824052714744512 * 1e18,
                debtInAuction:     46.411751195187947890 * 1e18,
                thresholdPrice:    0,
                neutralPrice:      11.932577910666902372 * 1e18
            })
        );

        // kicker bond is locked as auction is not cleared
        _assertKicker(
            {
                kicker:    _lender,
                claimable: 0,
                locked:    0.239683679352712078 * 1e18
            }
        );

        _settle(
            {
                from:        _lender,
                borrower:    _borrower,
                maxDepth:    10,
                settledDebt: 40.468140671388945316 * 1e18
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
                claimable: 0.239683679352712078 * 1e18,
                locked:    0
            }
        );

        // Kicker claims bond + reward
        changePrank(_lender);
        _pool.withdrawBonds();
        assertEq(_quote.balanceOf(_lender), 46_998.772748375624805866 * 1e18);
    }
}