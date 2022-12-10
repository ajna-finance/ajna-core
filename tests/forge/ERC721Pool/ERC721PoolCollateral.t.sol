// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/base/PoolHelper.sol';

contract ERC721PoolCollateralTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](5);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        _pool = _deploySubsetPool(subsetTokenIds);

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 100 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  52);
        _mintAndApproveCollateralTokens(_borrower2, 53);
    }

    /*******************************/
    /*** ERC721 Collection Tests ***/
    /*******************************/

    /***************************/
    /*** ERC721 Subset Tests ***/
    /***************************/

    function testPledgeCollateralSubset() external tearDown {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
    }

    function testPledgeCollateralNotInSubset() external tearDown {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        _assertPledgeCollateralNotInSubsetRevert(
            {
                from:     _borrower,
                tokenIds: tokenIdsToAdd
            }
        );
    }

    function testPledgeCollateralInSubsetFromDifferentActor() external tearDown {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );

        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(1));

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        1 * 1e18,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
        _assertBorrower(
            {
                borrower:                  _borrower2,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              0,
                borrowerCollateralization: 1 * 1e18
            }
        );
    }

    function testPullCollateral() external tearDown {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        // borrower is owner of NFTs
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        assertEq(_collateral.ownerOf(5), _borrower);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(3));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        // pool is owner of pledged NFTs
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(5), address(_pool));

        // should fail if trying to pull collateral by an address without pledged collateral
        _assertPullInsufficientCollateralRevert(
            {
                from:   _lender,
                amount: 3
            }
        );

        // borrower2 is owner of NFT
        assertEq(_collateral.ownerOf(53), _borrower2);

        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral(
            {
                from:     _borrower2,
                borrower: _borrower2,
                tokenIds: tokenIdsToAdd
            }
        );

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(4));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(address(_pool)), 4);

        // pool is owner of pledged NFT
        assertEq(_collateral.ownerOf(53), address(_pool));

        // borrower removes some of their deposted NFTS from the pool
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 2
        });

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(), Maths.wad(2));

        assertEq(_collateral.balanceOf(_borrower),      51);
        assertEq(_collateral.balanceOf(address(_pool)), 2);

        // pool is owner of remaining pledged NFT
        assertEq(_collateral.ownerOf(1), address(_pool));
        // borrower is owner of 2 pulled NFTs
        assertEq(_collateral.ownerOf(3), _borrower);
        assertEq(_collateral.ownerOf(5), _borrower);


        // should fail if borrower tries to pull more NFTs than remaining in pool
        _assertPullInsufficientCollateralRevert(
            {
                from:   _borrower,
                amount: 3
            }
        );
    }

    // TODO: finish implementing
    function testPullCollateralNotInPool() external tearDown {
        // borrower is owner of NFTs
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        assertEq(_collateral.ownerOf(5), _borrower);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // pool is owner of pledged NFTs
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(5), address(_pool));

        // should revert if borrower attempts to remove more collateral than pledged from pool
        _assertPullInsufficientCollateralRevert(
            {
                from:   _borrower,
                amount: 5
            }
        );

        // borrower should be able to remove collateral in the pool
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 3
        });
        // borrower is owner of pulled NFTs
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        assertEq(_collateral.ownerOf(5), _borrower);
    }

    function testPullCollateralPartiallyEncumbered() external tearDown {
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: MAX_PRICE
            }
        );

        // check initial token balances
        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      100 * 1e18);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
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
                amount:     3_000 * 1e18,
                indexLimit: 2_551,
                newLup:     _priceAt(2550)
            }
        );

        // check token balances after borrow
        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_100 * 1e18);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  1_000.961538461538462 * 1e18,
                lup:                  _priceAt(2550),
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    Maths.wad(3),
                encumberedCollateral: 0.997340520100278804 * 1e18,
                poolDebt:             3_002.884615384615386 * 1e18,
                actualUtilization:    0.100096153846153846 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

        // borrower removes some of their deposited NFTS from the pool
        _repayDebtNoLupCheck({
            from:             _borrower,
            borrower:         _borrower,
            amountToRepay:    0,
            amountRepaid:     0,
            collateralToPull: 2
        });

        // check token balances after remove
        assertEq(_collateral.balanceOf(_borrower),      51);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        assertEq(_quote.balanceOf(address(_pool)), 27_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      3_100 * 1e18);

        // check pool state
        _assertPool(
            PoolState({
                htp:                  3_002.884615384615386000 * 1e18,
                lup:                  _priceAt(2550),
                poolSize:             30_000 * 1e18,
                pledgedCollateral:    Maths.wad(1),
                encumberedCollateral: 0.997340520100278804 * 1e18,
                poolDebt:             3_002.884615384615386 * 1e18,
                actualUtilization:    0.300288461538461539 * 1e18,
                targetUtilization:    1 * 1e18,
                minDebtAmount:        300.288461538461538600 * 1e18,
                loans:                1,
                maxBorrower:          _borrower,
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   _startTime
            })
        );

    }

    function testPullCollateralOverlyEncumbered() external tearDown {

        // lender deposits 10000 Quote into 3 buckets
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550,
                newLup: MAX_PRICE
            }
        );

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the subset pool
        _pledgeCollateral(
            {
                from:     _borrower,
                borrower: _borrower,
                tokenIds: tokenIdsToAdd
            }
        );

        // check collateralization after pledge
        (uint256 poolDebt,,) = _pool.debtInfo();
        assertEq(_encumberance(poolDebt, _lup()), 0);

        // borrower borrows some quote
        _borrow(
            {
                from:       _borrower,
                amount:     9_000 * 1e18,
                indexLimit: 2_551,
                newLup:     _priceAt(2550)
            }
        );

        // check collateralization after borrow
        (poolDebt,,) = _pool.debtInfo();
        assertEq(_encumberance(poolDebt, _lup()), 2.992021560300836411 * 1e18);

        // should revert if borrower attempts to pull more collateral than is unencumbered
        _assertPullInsufficientCollateralRevert(
            {
                from:   _borrower,
                amount: 2
            }
        );
    }

    function testAddRemoveCollateral() external tearDown {

        // lender adds some liquidity
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1692,
                newLup: MAX_PRICE
            }
        );
        _addLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1530,
                newLup: MAX_PRICE
            }
        );

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 5;

        // add three tokens to a single bucket
        _addCollateral(
            {
                from:     _borrower,
                tokenIds: tokenIds,
                index:    1530
            }
        );

        // should revert if the actor does not have any LP to remove a token
        _assertRemoveCollateralInsufficientLPsRevert(
            {
                from:   _borrower2,
                amount: 1,
                index:  1530
            }
        );

        // should revert if we try to remove a token from a bucket with no collateral
        _assertRemoveInsufficientCollateralRevert(
            {
                from:   _borrower,
                amount: 1,
                index:  1692
            }
        );

        // remove one token
        _removeCollateral(
            {
                from:     _borrower,
                amount:   1,
                index:    1530,
                lpRedeem: 487_616.252661175041981841 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    497_616.252661175041981841 * 1e27,
                collateral:   Maths.wad(1),
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       1530,
                lpBalance:   487_616.252661175041981841 * 1e27,
                depositTime: _startTime
            }
        );

        // remove another token
        _removeCollateral(
            {
                from:     _borrower,
                amount:   1,
                index:    1530,
                lpRedeem: 487_616.252661175041981841 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    10_000 * 1e27,
                collateral:   0,
                deposit:      10_000 * 1e18,
                exchangeRate: 1 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       1530,
                lpBalance:   0,
                depositTime: _startTime
            }
        );

        // lender removes quote token
        skip(1 days); // skip to avoid penalty
        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   10_000 * 1e18,
                index:    1530,
                newLup:   MAX_PRICE,
                lpRedeem: 10_000 * 1e27
            }
        );

        _assertBucket(
            {
                index:        1530,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );
    }

    function testMergeCollateral() external {

        // insert liquidity at 3060 - 3159, going down in price
        for (uint256 i = 3060; i < (3060 + 100); i++) {
            _addLiquidity(
                {
                    from:   _lender,
                    amount: 1.5 * 1e18,
                    index:  i,
                    newLup: MAX_PRICE
                }
            );
        }

        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

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
                amount:     150 * 1e18,
                indexLimit: 8191,
                newLup:     144.398795715840771153 * 1e18
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              150.144230769230769300 * 1e18,
                borrowerCollateral:        2.0 * 1e18,
                borrowert0Np:              0.000000054499533442 * 1e18,
                borrowerCollateralization: 0.000000001329871716 * 1e18
            }
        );

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           152.021033653846153916 * 1e18,
                collateral:     2.0 * 1e18,
                bond:           1.501442307692307693 * 1e18,
                transferAmount: 1.501442307692307693 * 1e18
            }
        );

        skip(110 minutes);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          1.501442307692307693 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - 110 minutes,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 1.501442307692307693 * 1e18,
                auctionPrice:      0.000001792999017408 * 1e18,
                debtInAuction:     152.021033653846153916 * 1e18,
                thresholdPrice:    76.011312222718135349 * 1e18,
                neutralPrice:      0.000000054499533442 * 1e18
            })
        );

        uint256[] memory removalIndexes = new uint256[](100);
        uint256 removalI = 0; 

        // exchange collateral for lpb 3060 - 3159, going down in price
        for (uint256 i = 3060; i < (3060 + 100); i++) {
            _depositTake(
                {
                    from:             _lender,
                    borrower:         _borrower,
                    index:            i
                }
            );
            removalIndexes[removalI] = i;
            removalI++;
        }

        _assertBucket(
            {
                index:        3060,
                lpBalance:    1.500000000000000000000000000 * 1e27,
                collateral:   0.006340042654163331 * 1e18,
                deposit:      0,
                exchangeRate: 1.000010605277267413608094245 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3061,
                lpBalance:    1.500000000000000000000000000 * 1e27,
                collateral:   0.006371742867434148 * 1e18,
                deposit:      0,
                exchangeRate: 1.000010605277267475967018790 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3159,
                lpBalance:    1.500000000000000000000000000 * 1e27,
                collateral:   0.010388008435110149 * 1e18,
                deposit:      0,
                exchangeRate: 1.000010605277267451202381880 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3160,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1.0 * 1e27
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              2.021033653846153934 * 1e18,
                borrowerCollateral:        1.180018835375524990 * 1e18,
                borrowert0Np:              0.000000054499533442 * 1e18,
                borrowerCollateralization: 0.000000058291307540 * 1e18
            }
        );

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2.0 * 1e18,
                bondChange:      0.000000021157726124 * 1e18,
                givenAmount:     0.000002115772612351 * 1e18,
                collateralTaken: 1.180018835375524990 * 1e18,
                isReward:        false
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              2.021031538073541583 * 1e18,
                borrowerCollateral:        0.180018835375524990 * 1e18,
                borrowert0Np:              0.000000054499533442 * 1e18,
                borrowerCollateralization: 0.000000008892692190 * 1e18
            }
        );
        
        // 70.16 hours
        skip(4210 minutes);

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          0.001426378618680369 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - 4320 minutes,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 0.001426378618680369 * 1e18,
                auctionPrice:      0 * 1e18,
                debtInAuction:     2.021031538073541583 * 1e18,
                thresholdPrice:    11.231275373627960261 * 1e18,
                neutralPrice:      0.000000054499533442 * 1e18
            })
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              2.021841112542319702 * 1e18,
                borrowerCollateral:        0.180018835375524990 * 1e18,
                borrowert0Np:              0.000000054499533442 * 1e18,
                borrowerCollateralization: 0.000000008889131427 * 1e18
            }
        );

        _assertAuction(
            AuctionState({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          0.001426378618680369 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - 4320 minutes,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 0.001426378618680369 * 1e18,
                auctionPrice:      0.0 * 1e18,
                debtInAuction:     2.021031538073541583 * 1e18,
                thresholdPrice:    11.231275373627960261 * 1e18,
                neutralPrice:      0.000000054499533442 * 1e18
            })
        );

        _settle(
            {
                from:        _lender,
                borrower:    _borrower,
                maxDepth:    10,
                settledDebt: 2.021010389642603383 * 1e18
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              0.000000054499533442 * 1e18,
                borrowerCollateralization: 1.0 * 1e18
            }
        );

        //repayDebt(_borrower);

        _assertAuction( 
             AuctionState({
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

        _assertBucket(
            {
                index:        3060,
                lpBalance:    1.5 * 1e27,
                collateral:   0.006340042654163331 * 1e18,
                deposit:      0,
                exchangeRate: 1.000010605277267413608094245 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3159,
                lpBalance:    1.5 * 1e27,
                collateral:   0.010388008435110149 * 1e18,
                deposit:      0,
                exchangeRate: 1.000010605277267451202381880 * 1e27
            }
        );

        _mergeCollateral({
            from:                _lender,
            toIndex:             3159,
            collateralMerged:    0.819981164624475010 * 1e18,
            removeAmountAtIndex: removalIndexes
        });

        _assertBucket(
            {
                index:        3060,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1.0 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3061,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1.0 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3159,
                lpBalance:    118.404292681446768167332184816 * 1e27,
                collateral:   0.819981164624475010 * 1e18,
                deposit:      0,
                exchangeRate: 1.0 * 1e27
            }
        );   
    }
}