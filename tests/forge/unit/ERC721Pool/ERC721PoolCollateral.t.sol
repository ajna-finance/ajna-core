// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { ERC721HelperContract, ERC721FuzzyHelperContract } from './ERC721DSTestPlus.sol';

import { ERC721Pool }  from 'src/ERC721Pool.sol';

import 'src/PoolInfoUtils.sol';
import 'src/libraries/helpers/PoolHelper.sol';

contract ERC721PoolCollateralTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    function setUp() virtual external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy collection pool
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 100 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  52);
        _mintAndApproveCollateralTokens(_borrower2, 53);
    }

    /************************************/
    /*** ERC721 Collection Pool Tests ***/
    /************************************/

    function testPledgeCollateral() external tearDown {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(1));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(3));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(5));

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        // check token balances after add
        assertEq(_pool.pledgedCollateral(),             Maths.wad(3));
        assertEq(_collateral.balanceOf(_borrower),            49);
        assertEq(_collateral.balanceOf(address(_pool)), 3);
    }

    function testPledgeCollateralFromDifferentActor() external tearDown {
        // check initial token balances
        assertEq(_pool.pledgedCollateral(),             0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

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

        uint256[] memory tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(1));

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        1 * 1e18,
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

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

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
        _assertPullInsufficientCollateralRevert({
            from:   _lender,
            amount: 3
        });

        // borrower2 is owner of NFT
        assertEq(_collateral.ownerOf(53), _borrower2);

        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            tokenIds: tokenIdsToAdd
        });

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
        _assertPullInsufficientCollateralRevert({
            from:   _borrower,
            amount: 3
        });
    }

    function testPullCollateralToDifferentRecipient() external tearDown {
        address tokensReceiver = makeAddr("tokensReceiver");

        // check initial token balances
        assertEq(_pool.pledgedCollateral(), 0);

        assertEq(_collateral.balanceOf(_borrower),      52);
        assertEq(_collateral.balanceOf(_borrower2),     53);
        assertEq(_collateral.balanceOf(tokensReceiver), 0);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        // borrower is owner of NFTs
        assertEq(_collateral.ownerOf(1), _borrower);
        assertEq(_collateral.ownerOf(3), _borrower);
        assertEq(_collateral.ownerOf(5), _borrower);

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        // borrower2 deposits three NFTs into the pool
        tokenIdsToAdd = new uint256[](1);
        tokenIdsToAdd[0] = 53;
        _pledgeCollateral({
            from:     _borrower2,
            borrower: _borrower2,
            tokenIds: tokenIdsToAdd
        });

        // check token balances after add
        assertEq(_pool.pledgedCollateral(), Maths.wad(4));
        assertEq(_collateral.balanceOf(address(_pool)), 4);

        // pool is owner of pledged NFTs
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(5), address(_pool));
        assertEq(_collateral.ownerOf(53), address(_pool));

        // borrower removes some of their deposited NFTs from the pool and transfer to a different recipient
        changePrank(_borrower);
        ERC721Pool(address(_pool)).repayDebt(_borrower, 0, 2, tokensReceiver, MAX_FENWICK_INDEX);

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(), Maths.wad(2));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(tokensReceiver), 2);
        assertEq(_collateral.balanceOf(address(_pool)), 2);

        // pool is owner of remaining pledged NFT
        assertEq(_collateral.ownerOf(1), address(_pool));
        // recipient is owner of 2 pulled NFTs
        assertEq(_collateral.ownerOf(3), tokensReceiver);
        assertEq(_collateral.ownerOf(5), tokensReceiver);

        // borrower2 removes deposited NFT from the pool and transfer to same recipient
        changePrank(_borrower2);
        ERC721Pool(address(_pool)).repayDebt(_borrower2, 0, 1, tokensReceiver, MAX_FENWICK_INDEX);

        // check token balances after remove
        assertEq(_pool.pledgedCollateral(), Maths.wad(1));

        assertEq(_collateral.balanceOf(_borrower),      49);
        assertEq(_collateral.balanceOf(_borrower2),     52);
        assertEq(_collateral.balanceOf(tokensReceiver), 3);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        // pool is owner of remaining pledged NFT
        assertEq(_collateral.ownerOf(1), address(_pool));
        // recipient is owner of 3 pulled NFTs
        assertEq(_collateral.ownerOf(3),  tokensReceiver);
        assertEq(_collateral.ownerOf(5),  tokensReceiver);
        assertEq(_collateral.ownerOf(53), tokensReceiver);
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

        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        // pool is owner of pledged NFTs
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));
        assertEq(_collateral.ownerOf(5), address(_pool));

        // should revert if borrower attempts to remove more collateral than pledged from pool
        _assertPullInsufficientCollateralRevert({
            from:   _borrower,
            amount: 5
        });

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
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });

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

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     3_000 * 1e18,
            indexLimit: 2_551,
            newLup:     _priceAt(2550)
        });

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
                actualUtilization:    0.000000000000000000 * 1e18,
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
                actualUtilization:    0.000000000000000000 * 1e18,
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
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });

        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        // borrower deposits three NFTs into the pool
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });

        // check collateralization after pledge
        (uint256 poolDebt,,,) = _pool.debtInfo();
        assertEq(_encumberance(poolDebt, _lup()), 0);

        // borrower borrows some quote
        _borrow({
            from:       _borrower,
            amount:     9_000 * 1e18,
            indexLimit: 2_551,
            newLup:     _priceAt(2550)
        });

        // check collateralization after borrow
        (poolDebt,,,) = _pool.debtInfo();
        assertEq(_encumberance(poolDebt, _lup()), 2.992021560300836411 * 1e18);

        // should revert if borrower attempts to pull more collateral than is unencumbered
        _assertPullInsufficientCollateralRevert({
            from:   _borrower,
            amount: 2
        });
    }

    function testAddRemoveCollateral() external tearDown {
        // lender adds some liquidity
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  1692
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  1530
        });

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 5;

        // add three tokens to a single bucket
        _addCollateral({
            from:     _borrower,
            tokenIds: tokenIds,
            index:    1530,
            lpAward:  975_232.505322350083963682 * 1e18
        });

        // should revert if the actor does not have any LP to remove a token
        _assertRemoveCollateralInsufficientLPRevert({
            from:   _borrower2,
            amount: 1,
            index:  1530
        });

        // should revert if we try to remove a token from a bucket with no collateral
        _assertRemoveInsufficientCollateralRevert({
            from:   _borrower,
            amount: 1,
            index:  1692
        });

        // remove one token
        _removeCollateral({
            from:     _borrower,
            amount:   1,
            index:    1530,
            lpRedeem: 487_616.252661175041981841 * 1e18
        });

        _assertBucket({
            index:        1530,
            lpBalance:    497_616.252661175041981841 * 1e18,
            collateral:   Maths.wad(1),
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       1530,
            lpBalance:   487_616.252661175041981841 * 1e18,
            depositTime: _startTime
        });

        // remove another token
        _removeCollateral({
            from:     _borrower,
            amount:   1,
            index:    1530,
            lpRedeem: 487_616.252661175041981841 * 1e18
        });

        _assertBucket({
            index:        1530,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      10_000 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       1530,
            lpBalance:   0,
            depositTime: _startTime
        });

        // lender removes quote token
        skip(1 days); // skip to avoid penalty

        _removeAllLiquidity({
            from:     _lender,
            amount:   10_000 * 1e18,
            index:    1530,
            newLup:   MAX_PRICE,
            lpRedeem: 10_000 * 1e18
        });

        _assertBucket({
            index:        1530,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
    }

    function testMergeOrRemoveERC721Collateral() external tearDown {
        for (uint256 i = 3060; i < (3060 + 10); i++) {
            _addLiquidity({
                from:   _lender,
                amount: 20 * 1e18,
                index:  i,
                newLup: MAX_PRICE,
                lpAward: 20 * 1e18
            });
        }

        // borrower pledge collateral and draws debt
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            tokenIds: tokenIdsToAdd
        });
        _borrow({
            from:       _borrower,
            amount:     150 * 1e18,
            indexLimit: MAX_FENWICK_INDEX,
            newLup:     228.476350374240318479 * 1e18
        });

        // Borrower starts with possession of tokens 1 and 3
        uint256[] memory borrowerTokenIds = new uint256[](2);
        borrowerTokenIds[0] = 1;
        borrowerTokenIds[1] = 3;

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              150.144230769230769300 * 1e18,
            borrowerCollateral:        2.0 * 1e18,
            borrowert0Np:              86.468317660735388466 * 1e18,
            borrowerCollateralization: 3.043424968161510485 * 1e18,
            tokenIds:                  borrowerTokenIds
        });

        // skip to render borrower undercollateralized
        skip(10_000 days);
        _assertPool(
            PoolParams({
                htp:                  75.072115384615384650 * 1e18,
                lup:                  0.000000099836282890 * 1e18,
                poolSize:             200.0 * 1e18,
                pledgedCollateral:    2 * 1e18,
                encumberedCollateral: 5_917_580_766.197687035371154332 * 1e18,
                poolDebt:             590.789267398535232527 * 1e18,
                actualUtilization:    0,
                targetUtilization:    1.0 * 1e18,
                minDebtAmount:        59.078926739853523253 * 1e18,
                loans:                1,
                maxBorrower:          address(_borrower),
                interestRate:         0.05 * 1e18,
                interestRateUpdate:   block.timestamp - 10_000 days
            })
        );

        _assertBucket({
            index:        3061,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      20.0 * 1e18,
            exchangeRate: 1.000000000000000000 * 1e18
        });

        _kick({
            from:           _lender,
            borrower:       _borrower,
            debt:           590.789267398535232526 * 1e18,
            collateral:     2.0 * 1e18,
            bond:           8.968381880996266239 * 1e18,
            transferAmount: 8.968381880996266239 * 1e18
        });

        skip(32 hours);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          8.968381880996266239 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 32 hours,
                referencePrice:    340.236543104248948639 * 1e18,
                totalBondEscrowed: 8.968381880996266239 * 1e18,
                auctionPrice:      0.000081118713165342 * 1e18,
                debtInAuction:     590.789267398535232527 * 1e18,
                thresholdPrice:    295.453988355164748340 * 1e18,
                neutralPrice:      340.236543104248948639 * 1e18
            })
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  99836282890,
                poolSize:             574.548281134908793200 * 1e18,
                pledgedCollateral:    2 * 1e18,
                encumberedCollateral: 5_918_769_805.977193435161155568 * 1e18,
                poolDebt:             590.907976710329496681 * 1e18,
                actualUtilization:    0.750721153846153847 * 1e18,
                targetUtilization:    0.328577182109433013 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.055 * 1e18,
                interestRateUpdate:   block.timestamp - 32 hours
            })
        );

        // interest accumulation to assert bucket with interest
        _updateInterest();
        _assertBucket({
            index:        3060,
            lpBalance:    20 * 1e18,
            collateral:   0.0000000000000000000 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3061,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3062,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3063,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3064,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3065,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3066,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3067,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3068,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3069,
            lpBalance:    20.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      57.465578391592604940 * 1e18,
            exchangeRate: 2.873278919579630247 * 1e18
        });

        _assertBucket({
            index:        3070,
            lpBalance:    0.0 * 1e18,
            collateral:   0.0 * 1e18,
            deposit:      0.0,
            exchangeRate: 1.0 * 1e18
        });

        // Before depositTake: NFTs pledged by liquidated borrower are owned by the borrower in the pool
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));

        // exchange collateral for lpb 3060 - 3070, going down in price
        for (uint256 i = _i236_59; i < (3060 + 3); i++) {
            _depositTake({
                from:     _lender,
                borrower: _borrower,
                index:    i
            });
        }

        _assertBucket({
            index:        3060,
            lpBalance:    20.308286694556134654 * 1e18,
            collateral:   0.246630842904997686 * 1e18,
            deposit:      0.000000000000000144 * 1e18,
            exchangeRate: 2.873278919579630248 * 1e18
        });

        _assertBucket({
            index:        3061,
            lpBalance:    20.308286694556134655 * 1e18,
            collateral:   0.247863997119522673 * 1e18,
            deposit:      0.000000000000000006 * 1e18,
            exchangeRate: 2.873278919579630248 * 1e18
        });

        _assertBucket({
            index:        3070,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          8.968381880996266239 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - 32 hours,
                referencePrice:    340.236543104248948639 * 1e18,
                totalBondEscrowed: 8.968381880996266239 * 1e18,
                auctionPrice:      0.000081118713165342 * 1e18,
                debtInAuction:     418.511241535551682100 * 1e18,
                thresholdPrice:    333.103014700636165105 * 1e18,
                neutralPrice:      340.236543104248948639 * 1e18
            })
        );

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  99836282890,
                poolSize:             402.259048741148234756 * 1e18,
                pledgedCollateral:    1.256401842870359357 * 1e18,
                encumberedCollateral: 4_191_975_396.326293274519167147 * 1e18,
                poolDebt:             418.511241535551682100 * 1e18,
                actualUtilization:    0.750721153846153847 * 1e18,
                targetUtilization:    0.328577182109433013 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.0605 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        // Borrower's collateral is 0 therefore they have bad debt
        borrowerTokenIds = new uint256[](1);
        borrowerTokenIds[0] = 1;

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              418.511241535551682100 * 1e18,
            borrowerCollateral:        1.256401842870359357 * 1e18,
            borrowert0Np:              97.486777718699640528 * 1e18,
            borrowerCollateralization: 0.000000000299715939 * 1e18,
            tokenIds:                  borrowerTokenIds
        });

        // after depositTake but before take: NFTs pledged by liquidated borrower are owned by the pool
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), address(_pool));

        _take({
            from:            _lender,
            borrower:        _borrower,
            maxCollateral:   2 * 1e18,
            bondChange:      0.000001231409637086 * 1e18,
            givenAmount:     0.000081118713165342 * 1e18,
            collateralTaken: 1 * 1e18,
            isReward:        true
        });

        // Borrower has < 1 collateral, no NFTs in possession
        borrowerTokenIds = new uint256[](0);

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              418.511161648248153847 * 1e18,
            borrowerCollateral:        0.256401842870359357 * 1e18,
            borrowert0Np:              477.697595423190347016 * 1e18,
            borrowerCollateralization: 0.000000000061164932 * 1e18,
            tokenIds:                  borrowerTokenIds
        });

        // after take: NFT with ID 1, pledged by liquidated borrower is owned by the taker
        assertEq(_collateral.ownerOf(1), address(_pool));
        assertEq(_collateral.ownerOf(3), _lender);

        // subsequent take should fail as there's less than 1 NFT remaining in the loan
        _assertTakeInsufficentCollateralRevert({
            from:          _lender,
            borrower:      _borrower2,
            maxCollateral: 1 * 1e18
        });

        // 70.16 hours
        skip(4210 minutes);

        _assertAuction(
            AuctionParams({
                borrower:          _borrower,
                active:            true,
                kicker:            address(_lender),
                bondSize:          8.968383112405903325 * 1e18,
                bondFactor:        0.015180339887498948 * 1e18,
                kickTime:          block.timestamp - (32 hours + 4210 minutes),
                referencePrice:    340.236543104248948639 * 1e18,
                totalBondEscrowed: 8.968383112405903325 * 1e18,
                auctionPrice:      0,
                debtInAuction:     418.511161648248153847 * 1e18,
                thresholdPrice:    1_633.038265299714540882 * 1e18,
                neutralPrice:      340.236543104248948639 * 1e18
            })
        );

        _settle({
            from:        _lender,
            borrower:    _borrower,
            maxDepth:    11,
            settledDebt: 106.339800629932799697 * 1e18
        });

        _assertBorrower({
            borrower:                  _borrower,
            borrowerDebt:              0,
            borrowerCollateral:        0,
            borrowert0Np:              0,
            borrowerCollateralization: 1.0 * 1e18,
            tokenIds:                  borrowerTokenIds
        });

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
                referencePrice:    0,
                totalBondEscrowed: 8.968383112405903325 * 1e18,
                auctionPrice:      0,
                debtInAuction:     0,
                thresholdPrice:    0,
                neutralPrice:      0
            })
        );

        _assertBucket({
            index:        3060,
            lpBalance:    20.308286694556134654 * 1e18,
            collateral:   0.246630842904997687 * 1e18,
            deposit:      0,
            exchangeRate: 2.873278919579630252 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       3067,
            lpBalance:   0,
            depositTime: 0
        });

        assertEq(_collateral.balanceOf(_lender),        1);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 1);

        // lender merge his entitled collateral (based on their LP) in bucket 3069
        uint256[] memory removalIndexes = new uint256[](10);
        uint256 removalI = 0;
        for (uint256 i = 3060; i < (3060 + 10); i++) {
            removalIndexes[removalI] = i;
            removalI++;
        }

        // Reverts because 3059 is a higher price than 3060, must merge down in price
        _assertCannotMergeToHigherPriceRevert({
            from:                    _lender,
            toIndex:                 3059,
            noOfNFTsToRemove:        1.0,
            removeCollateralAtIndex: removalIndexes
        });

        _mergeOrRemoveCollateral({
            from:                    _lender,
            toIndex:                 3070,
            noOfNFTsToRemove:        1.0,
            collateralMerged:        1 * 1e18,
            removeCollateralAtIndex: removalIndexes,
            toIndexLps:              0
        });

        _assertBucket({
            index:        3060,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        3061,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertBucket({
            index:        3070,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       3070,
            lpBalance:   0,
            depositTime: 0
        });
        _assertBucket({
            index:        7388,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        assertEq(_collateral.balanceOf(_lender),        2);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 0);

        // lender deposit quote tokens in bucket 7388 in order to claim and merge settled collateral and to be able to remove entire NFT
        _addLiquidity({
            from:    _lender,
            amount:  10 * 1e18,
            index:   7388,
            lpAward: 10 * 1e18, // LP awarded to lender for depositing quote tokens in bucket 7388
            newLup:  MAX_PRICE
        });

        _assertLenderLpBalance({
            lender:      _lender,
            index:       7388,
            lpBalance:   10 * 1e18, // lender now owns LP in bucket 7388 which can be used to merge bucket collateral
            depositTime: _startTime + 10000 days + (32 hours + 4210 minutes)
        });

        // collateral is now splitted accross buckets 3069 and 7388
        uint256[] memory allRemovalIndexes = new uint256[](2);
        allRemovalIndexes[0] = 3070;
        allRemovalIndexes[1] = 7388;

        _assertBucket({
            index:        3060,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1.0 * 1e18
        });
        _assertBucket({
            index:        3061,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1.0 * 1e18
        });
        _assertBucket({
            index:        3070,
            lpBalance:    0,
            collateral:   0,
            deposit:      0,
            exchangeRate: 1.0 * 1e18
        });
        _assertBucket({
            index:        7388,
            lpBalance:    10 * 1e18, // LP in bucket 7388 diminished when NFT merged and removed
            collateral:   0,         // no collateral remaining as it was merged and removed
            deposit:      10 * 1e18,
            exchangeRate: 1 * 1e18
        });
        _assertLenderLpBalance({
            lender:      _lender,
            index:       7388,
            lpBalance:   10 * 1e18, // lender LP decreased with the amount used to merge NFT
            depositTime: _startTime + 10000 days + (32 hours + 4210 minutes)
        });
        _assertLenderLpBalance({
            lender:      _borrower,
            index:       7388,
            lpBalance:   0, // Borrower LP remain the same in the bucket
            depositTime: 0
        });

        _removeAllLiquidity({
            from:     _lender,
            amount:   10 * 1e18,
            index:    7388,
            newLup:   MAX_PRICE,
            lpRedeem: 10 * 1e18
        });

        _assertBucket({
            index:        7388,
            lpBalance:    0,            // LP in bucket 7388 diminished when NFT merged and removed
            collateral:   0,            // no collateral remaining as it was merged and removed
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        _assertPool(
            PoolParams({
                htp:                  0,
                lup:                  MAX_PRICE,
                poolSize:             50.000079544611684526 * 1e18,
                pledgedCollateral:    0,
                encumberedCollateral: 0,
                poolDebt:             0,
                actualUtilization:    0.750721153846153847 * 1e18,
                targetUtilization:    0.328577182109433013 * 1e18,
                minDebtAmount:        0,
                loans:                0,
                maxBorrower:          address(0),
                interestRate:         0.05445 * 1e18,
                interestRateUpdate:   block.timestamp
            })
        );

        assertEq(_collateral.balanceOf(_lender),        2);
        assertEq(_collateral.balanceOf(_borrower),      50);
        assertEq(_collateral.balanceOf(address(_pool)), 0);
    }
}

contract ERC721SubsetPoolCollateralTest is ERC721PoolCollateralTest {

    function setUp() override external {
        _startTest();

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

        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(1));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(3));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(5));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(51));
        assertTrue(ERC721Pool(address(_pool)).tokenIdsAllowed(53));
        assertTrue(!ERC721Pool(address(_pool)).tokenIdsAllowed(1337));

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveQuoteTokens(_borrower, 100 * 1e18);

        _mintAndApproveCollateralTokens(_borrower,  52);
        _mintAndApproveCollateralTokens(_borrower2, 53);
    }

    /********************************/
    /*** ERC721 Subset Pool Tests ***/
    /********************************/

    function testPledgeCollateralNotInSubset() external tearDown {
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 2;
        tokenIdsToAdd[1] = 4;
        tokenIdsToAdd[2] = 6;

        // should revert if borrower attempts to add tokens not in the pool subset
        _assertPledgeCollateralNotInSubsetRevert({
            from:     _borrower,
            tokenIds: tokenIdsToAdd
        });
    }

    function testRemoveCollateralReverts() external tearDown {
        uint256 testIndex = 6248;
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 3;
        tokenIdsToAdd[1] = 5;

        _assertAddCollateralExpiredRevert({
            from:     _lender,
            tokenIds: tokenIdsToAdd,
            index:    testIndex,
            expiry:   block.timestamp - 15
        });
    }
}

contract ERC721PoolCollateralFuzzyTest is ERC721FuzzyHelperContract {
    address internal _lender;
    function setUp() external {
        _startTest();
        // deploy collection pool
        _pool = _deployCollectionPool();

        _lender = makeAddr("lender");
        _mintAndApproveCollateralTokens(_lender, 100);
    }

    function testAddRemoveCollateralFuzzy(uint256 nftAmount, uint256 bucketIndex) external tearDown {
        nftAmount = bound(nftAmount, 1, 100);
        bucketIndex = bound(bucketIndex, 1, 7388);

        uint256[] memory tokenIds = new uint256[](nftAmount);
        for (uint256 i = 0; i < nftAmount; i++) {
            tokenIds[i] = i + 1;
        }

        uint256 bucketPrice = _poolUtils.indexToPrice(bucketIndex);
        uint256 lps = Maths.wmul(nftAmount * 1e18, bucketPrice);

        // add some collateral
        _addCollateral({
            from:     _lender,
            tokenIds: tokenIds,
            index:    bucketIndex,
            lpAward:  lps
        });

        _assertBucket({
            index:        bucketIndex,
            lpBalance:    lps,
            collateral:   nftAmount * 1e18,
            deposit:      0,
            exchangeRate: 1e18
        });

        uint256 nftToRemove = bound(nftAmount, 1, nftAmount);
        uint256 lpsRedeemed = Maths.wmul(nftToRemove * 1e18, bucketPrice);

        // remove some collateral
        _removeCollateral({
            from:     _lender,
            amount:   nftToRemove,
            index:    bucketIndex,
            lpRedeem: lpsRedeemed
        });

        uint256 lpsRemaining = lps - lpsRedeemed;
        uint256 collateralRemaining = nftAmount - nftToRemove;

        _assertBucket({
            index:        bucketIndex,
            lpBalance:    lpsRemaining,
            collateral:   collateralRemaining,
            deposit:      0,
            exchangeRate: 1e18
        });

        if (collateralRemaining > 0) {
            // remove all remaining collateral
            _removeCollateral({
                from:     _lender,
                amount:   collateralRemaining,
                index:    bucketIndex,
                lpRedeem: lpsRemaining
            });

            _assertBucket({
                index:        bucketIndex,
                lpBalance:    0,
                collateral:   0,
                deposit:      0,
                exchangeRate: 1e18
            });
        }
    }
}
