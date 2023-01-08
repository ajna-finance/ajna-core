// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/PoolInfoUtils.sol';
import 'src/libraries/helpers/PoolHelper.sol';

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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
            }
        );

        // check initial token balances
        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        assertEq(_quote.balanceOf(address(_pool)), 30_000 * 1e18);
        assertEq(_quote.balanceOf(_borrower),      100 * 1e18);

        // check pool state
        _assertPool(
            PoolParams({
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
            PoolParams({
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
            PoolParams({
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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2552
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2551
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  2550
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
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1692
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 10_000 * 1e18,
                index:  1530
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
                index:    1530,
                lpAward:  975_232.505322350083963682 * 1e27
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

    function testMergeOrRemoveCollateral() external tearDown {
        for (uint256 i = 3060; i < (3060 + 10); i++) {
            _addLiquidity(
                {
                    from:   _lender,
                    amount: 20 * 1e18,
                    index:  i,
                    newLup: MAX_PRICE,
                    lpAward: 20 * 1e27
                }
            );
        }

        // borrower pledge collateral and draws debt
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
                newLup:     228.476350374240318479 * 1e18
            }
        );

        // Borrower starts with possession of tokens 1 and 3
        uint256[] memory borrowerTokenIds = new uint256[](2);
        borrowerTokenIds[0] = 1;
        borrowerTokenIds[1] = 3;

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              150.144230769230769300 * 1e18,
                borrowerCollateral:        2.0 * 1e18,
                borrowert0Np:              78.825721153846153882 * 1e18,
                borrowerCollateralization: 3.043424968161510485 * 1e18,
                tokenIds:                  borrowerTokenIds
            }
        );

        // skip to render borrower undercollateralized
        skip(10000 days);

        _kick(
            {
                from:           _lender,
                borrower:       _borrower,
                debt:           598.174133241016922933 * 1e18,
                collateral:     2.0 * 1e18,
                bond:           5.907892673985352325 * 1e18,
                transferAmount: 5.907892673985352325 * 1e18
            }
        );

        skip(32 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          5.907892673985352325 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - 32 hours,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 5.907892673985352325 * 1e18,
                auctionPrice:      0.000004621809202112 * 1e18,
                debtInAuction:     598.174133241016922932 * 1e18,
                thresholdPrice:    299.147163209604307694 * 1e18,
                neutralPrice:      310.164365384230997074 * 1e18
            })
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  99836282890,
                poolSize:             200 * 1e18,
                pledgedCollateral:    2 * 1e18,
                encumberedCollateral: 5_992_754_428.551908353085520210 * 1e18,
                poolDebt:             598.294326419208615388 * 1e18,
                actualUtilization:    0,
                targetUtilization:    2995775262.849776174319954472 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   block.timestamp - 32 hours
            })
        );

        // Before depositTake: NFTs pledged by liquidated borrower are owned by the borrower in the pool
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));

        // exchange collateral for lpb 3060 - 3070, going down in price
        for (uint256 i = _i236_59; i < (3060 + 10); i++) {
            _depositTake(
                {
                    from:     _lender,
                    borrower: _borrower,
                    index:    i
                }
            );
        }

        _assertBucket(
            {
                index:        3060,
                lpBalance:    20.2 * 1e27,
                collateral:   0.085430491711717314 * 1e18,
                deposit:      0,
                exchangeRate: 1.000610882095524250072170475 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3061,
                lpBalance:    20.2 * 1e27,
                collateral:   0.085857644170275899 * 1e18,
                deposit:      0,
                exchangeRate: 1.000610882095524239992886155 * 1e27
            }
        );

        _assertBucket(
            {
                index:        3070,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1 * 1e27
            }
        );

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          5.907892673985352325 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - 32 hours,
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 5.907892673985352325 * 1e18,
                auctionPrice:      0.000004621809202112 * 1e18,
                debtInAuction:     440.072765067090279852 * 1e18,
                thresholdPrice:    390.753889954564976957 * 1e18,
                neutralPrice:      310.164365384230997074 * 1e18
            })
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  99836282890,
                poolSize:             0,
                pledgedCollateral:    1.126214674710621229 * 1e18,
                encumberedCollateral: 4407944209.541175956055268556 * 1e18,
                poolDebt:             440.072765067090279852 * 1e18,
                actualUtilization:    0,
                targetUtilization:    3_123_578_486.651416548727612650 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0605 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // Borrower's collateral is < 2 therefore they have possession of token ID 1
        borrowerTokenIds = new uint256[](1);
        borrowerTokenIds[0] = 1;

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              440.072765067090279852 * 1e18,
                borrowerCollateral:        1.126214674710621229 * 1e18,
                borrowert0Np:              78.825721153846153882 * 1e18,
                borrowerCollateralization: 0.000000000255496581 * 1e18,
                tokenIds:                  borrowerTokenIds
            }
        );
        
        // after depositTake but before take: NFTs pledged by liquidated borrower are owned by the pool
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));

        _take(
            {
                from:            _lender,
                borrower:        _borrower,
                maxCollateral:   2.0 * 1e18,
                bondChange:      0.000000052051493471 * 1e18,
                givenAmount:     0.000005205149347131 * 1e18,
                collateralTaken: 1.126214674710621229 * 1e18,
                isReward:        true
            }
        );

        // Borrower has < 1 collateral, no NFTs in possession
        borrowerTokenIds = new uint256[](0);

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              440.072759913992426192 * 1e18,
                borrowerCollateral:        0.126214674710621229 * 1e18,
                borrowert0Np:              78.825721153846153882 * 1e18,
                borrowerCollateralization: 0.000000000028633456 * 1e18,
                tokenIds:                  borrowerTokenIds
            }
        );

        // after take: NFT with ID 1, pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), _lender);

        // 70.16 hours
        skip(4210 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          5.907892726036845796 * 1e18,
                bondFactor:        0.010 * 1e18,
                kickTime:          block.timestamp - (32 hours + 4210 minutes),
                kickMomp:          0.000000099836282890 * 1e18,
                totalBondEscrowed: 5.907892726036845796 * 1e18,
                auctionPrice:      0 * 1e18,
                debtInAuction:     440.072759913992426192 * 1e18,
                thresholdPrice:    3_488.390484128255500242 * 1e18,
                neutralPrice:      310.164365384230997074 * 1e18
            })
        );

        _settle(
            {
                from:        _lender,
                borrower:    _borrower,
                maxDepth:    10,
                settledDebt: 111.818402566884385900 * 1e18
            }
        );

        _assertBorrower(
            {
                borrower:                  _borrower,
                borrowerDebt:              0,
                borrowerCollateral:        0,
                borrowert0Np:              78.825721153846153882 * 1e18,
                borrowerCollateralization: 1.0 * 1e18,
                tokenIds:                  borrowerTokenIds
            }
        );

        // after take: NFT, 1 pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), _lender);

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

        _assertBucket(
            {
                index:        3060,
                lpBalance:    20.2 * 1e27,
                collateral:   0.085430491711717314 * 1e18,
                deposit:      0,
                exchangeRate: 1.000610882095524250072170475 * 1e27
            }
        );
        _assertBucket(
            {
                index:        3069,
                lpBalance:    20.2 * 1e27,
                collateral:   0.089352655062849951 * 1e18,
                deposit:      0,
                exchangeRate: 1.000610882095524241676916623 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       3069,
                lpBalance:   20.2 * 1e27,
                depositTime: _startTime + 10000 days + 32 hours
            }
        );
        _assertBucket(
            {
                index:        7388,
                lpBalance:    0.000000012600803969278909906 * 1e27, // LPs awarded to borrower for settled collateral
                collateral:   0.126214674710621229 * 1e18,          // settled collateral amount
                deposit:      0,
                exchangeRate: 1.000000000000000000006624324 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       7388,
                lpBalance:   0.000000012600803969278909906 * 1e27,
                depositTime: _startTime + 10000 days + 32 hours + 4210 minutes
            }
        );
        assertEq(_collateral.balanceOf(_lender),        1);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        // lender merge his entitled collateral (based on their LPs) in bucket 3069
        uint256[] memory removalIndexes = new uint256[](10);
        uint256 removalI = 0;
        for (uint256 i = 3060; i < (3060 + 10); i++) {
            removalIndexes[removalI] = i;
            removalI++;
        }
        // Reverts because 3059 is a higher price than 3060, must merge down in price
        _assertCannotMergeToHigherPriceRevert(
            {
                from:                    _lender,
                toIndex:                 3059,
                noOfNFTsToRemove:        1.0,
                removeCollateralAtIndex: removalIndexes
            }
        );

        _mergeOrRemoveCollateral(
            {
                from:                    _lender,
                toIndex:                 3069,
                noOfNFTsToRemove:        1.0,
                collateralMerged:        0.873785325289378771 * 1e18,
                removeCollateralAtIndex: removalIndexes,
                toIndexLps:              197.657763058028917103677822434 * 1e27
            }
        );

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
                index:        3069,
                lpBalance:    197.657763058028917103677822434 * 1e27, // new LPs amount accounting collateral merged in bucket
                collateral:   0.873785325289378771 * 1e18,            // reflects collateral merged in the bucket
                deposit:      0,
                exchangeRate: 0.999999999999999999999999999 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       3069,
                lpBalance:   197.657763058028917103677822434 * 1e27,
                depositTime: _startTime + 10000 days +  32 hours + 4210 minutes
            }
        );
        _assertBucket(
            {
                index:        7388,
                lpBalance:    0.000000012600803969278909906 * 1e27, // LPs awarded to borrower for settled collateral
                collateral:   0.126214674710621229 * 1e18,          // settled collateral amount
                deposit:      0,
                exchangeRate: 1.000000000000000000006624324 * 1e27
            }
        );

        assertEq(_collateral.balanceOf(_lender),        1);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        // lender deposit quote tokens in bucket 7388 in order to claim and merge settled collateral and to be able to remove entire NFT
        _addLiquidity(
            {
                from:    _lender,
                amount:  10 * 1e18,
                index:   7388,
                lpAward: 9.999999999999999999933756760 * 1e27, // LPs awarded to lender for depositing quote tokens in bucket 7388
                newLup:  MAX_PRICE
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       7388,
                lpBalance:   9.999999999999999999933756760 * 1e27, // lender now owns LPs in bucket 7388 which can be used to merge bucket collateral
                depositTime: _startTime + 10000 days + (32 hours + 4210 minutes)
            }
        );

        // collateral is now splitted accross buckets 3069 and 7388
        uint256[] memory allRemovalIndexes = new uint256[](2);
        allRemovalIndexes[0] = 3069;
        allRemovalIndexes[1] = 7388;

        _mergeOrRemoveCollateral(
            {
                from:                    _lender,
                toIndex:                 7388,
                noOfNFTsToRemove:        1,
                collateralMerged:        1 * 1e18,
                removeCollateralAtIndex: allRemovalIndexes,
                toIndexLps:              0
            }
        );

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
                index:        3069,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1.0 * 1e27
            }
        );   
        _assertBucket(
            {
                index:        7388,
                lpBalance:    10.000000000000000000212666669 * 1e27, // LPs in bucket 7388 diminished when NFT merged and removed
                collateral:   0,                                    // no collateral remaining as it was merged and removed
                deposit:      10 * 1e18,
                exchangeRate: 0.999999999999999999978733333 * 1e27
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender,
                index:       7388,
                lpBalance:   9.999999987399196030933756763 * 1e27, // lender LPs decreased with the amount used to merge NFT
                depositTime: _startTime + 10000 days + (32 hours + 4210 minutes)
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _borrower,
                index:       7388,
                lpBalance:   0.000000012600803969278909906 * 1e27, // Borrower LPs remain the same in the bucket
                depositTime: _startTime + 10000 days + (32 hours + 4210 minutes)
            }
        );

        _removeAllLiquidity(
            {
                from:     _lender,
                amount:   9.987201910492245717 * 1e18,
                index:    7388,
                newLup:   MAX_PRICE,
                lpRedeem: 9.999999987399196030933756763 * 1e27
            }
        );

        _assertBucket(
            {
                index:        7388,
                lpBalance:    0.000000012600803969278909906 * 1e27, // LPs in bucket 7388 diminished when NFT merged and removed
                collateral:   0,                                    // no collateral remaining as it was merged and removed
                deposit:      0.000000012600803969 * 1e18,
                exchangeRate: 0.999999999977865705499427682 * 1e27
            }
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             0.000000012600803969 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0,
                targetUtilization:    3123578486.651416548727612650 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.06655 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        assertEq(_collateral.balanceOf(_lender),        2);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

    }
}
