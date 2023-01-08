// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@std/Test.sol";
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { NFTCollateralToken } from '../utils/Tokens.sol';

import { ERC721Pool }         from 'src/ERC721Pool.sol';
import { ERC721PoolFactory }  from 'src/ERC721PoolFactory.sol';

import { ERC721HelperContract } from '../ERC721Pool/ERC721DSTestPlus.sol';

import 'src/PoolInfoUtils.sol';
import "./NFTTakeExample.sol";

contract ERC721TakeWithExternalLiquidityTest is ERC721HelperContract {

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _lender    = makeAddr("lender");

        // deploy collection pool
        _pool = _deployCollectionPool();

        _mintAndApproveQuoteTokens(_lender, 100_000 * 1e18);
        _mintAndApproveCollateralTokens(_borrower, 3);
        _mintAndApproveCollateralTokens(_borrower2, 5);

        _quote.approve(address(_pool), type(uint256).max);

        // lender deposits 50_000 Quote into the pool
        _addInitialLiquidity(
            {
                from:   _lender,
                amount: 50_000 * 1e18,
                index:  _i1004_98
            }
        );

        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;

        _drawDebt({
            from:           _borrower,
            borrower:       _borrower,
            amountToBorrow: 1_999 * 1e18,
            limitIndex:     3232,
            tokenIds:       tokenIdsToAdd,
            newLup:         _p1004_98
        });

        // enough time passes that the borrower becomes undercollateralized
        skip(60 days);
        // lender kicks the liquidation
        changePrank(_lender);
        _pool.kick(_borrower);
        // price becomes favorable
        skip(8 hours);
    }

    function testTakeNFTFromContractWithAtomicSwap() external {
        // instantiate and fund a hypothetical NFT marketplace
        NFTMarketPlace marketPlace = new NFTMarketPlace(_quote);
        deal(address(_quote), address(marketPlace), 25_000 * 1e18);

        // instantiate a taker contract which implements IERC721Taker and uses this marketplace
        NFTTakeExample taker = new NFTTakeExample(address(marketPlace));
        changePrank(address(taker));
        assertEq(_quote.balanceOf(address(taker)), 0);
        _quote.approve(address(_pool), type(uint256).max);
        _collateral.setApprovalForAll(address(marketPlace), true);

        // call take using taker contract
        bytes memory data = abi.encode(address(_pool));
        vm.expectEmit(true, true, false, true);
        uint256 quoteTokenPaid = 529.576903317769475648 * 1e18;
        uint256 collateralPurchased = 2 * 1e18;
        uint256 bondChange = 5.295769033177694756 * 1e18;
        emit Take(_borrower, quoteTokenPaid, collateralPurchased, bondChange, true);
        _pool.take(_borrower, 2, address(taker), data);

        // confirm we earned some quote token
        assertEq(_quote.balanceOf(address(taker)), 970.423096682230524352 * 1e18);
    }
}
