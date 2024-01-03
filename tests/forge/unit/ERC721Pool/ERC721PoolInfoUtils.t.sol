// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';
import { Token }               from '../../utils/Tokens.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/erc721/IERC721Pool.sol';

import 'src/ERC721Pool.sol';
import 'src/PoolInfoUtilsMulticall.sol';

contract ERC721PoolInfoUtilsTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;
    address internal _lender2;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        // deploy collection pool
        _pool = this.createPool();

        _mintAndApproveQuoteTokens(_lender, 200_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 52);
        _mintAndApproveCollateralTokens(_borrower2, 10);

        changePrank(_borrower);
        _quote.approve(address(_pool), 200_000 * 1e18);

        // lender deposits 10000 Quote into 3 buckets
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2550
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2551
        });
        _addInitialLiquidity({
            from:   _lender,
            amount: 10_000 * 1e18,
            index:  2552
        });

        // borrower deposits three NFTs into the subset pool
        uint256[] memory tokenIdsToAdd = new uint256[](3);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        tokenIdsToAdd[2] = 5;

        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 3_000 * 1e18,
            limitIndex:     2_551,
            tokenIds:       tokenIdsToAdd,
            newLup:         _priceAt(2550)
        });
    }

    function createPool() external returns (ERC721Pool) {
        // deploy subset pool
        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;
        return _deploySubsetPool(subsetTokenIds);
    }

    function testPoolInfoUtilsInvariantsFuzzed(uint256 depositIndex_, uint256 price_) external {
        depositIndex_ = bound(depositIndex_, 0, 7388);
        assertEq(_priceAt(depositIndex_), _poolUtils.indexToPrice(depositIndex_));

        price_ = bound(price_, MIN_PRICE, MAX_PRICE);
        assertEq(_indexOf(price_), _poolUtils.priceToIndex(price_));
    }

    function testPoolInfoUtilsMulticallPoolBalanceDetails() external {
        PoolInfoUtilsMulticall poolUtilsMulticall = new PoolInfoUtilsMulticall(_poolUtils);

        uint256 meaningfulIndex = 5000;
        address quoteTokenAddress = IPool(_pool).quoteTokenAddress();
        address collateralTokenAddress = IPool(_pool).collateralAddress();

        PoolInfoUtilsMulticall.PoolBalanceDetails memory poolBalanceDetails = poolUtilsMulticall.poolBalanceDetails(address(_pool), meaningfulIndex, quoteTokenAddress, collateralTokenAddress, true);

        assertEq(poolBalanceDetails.debt,        3_002.884615384615386000 * 1e18);
        assertEq(poolBalanceDetails.quoteTokenBalance,  27_000 * 1e18);
        assertEq(poolBalanceDetails.collateralTokenBalance,  3 * 1e18);
    }


}
