// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }               from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken } from "../utils/Tokens.sol";

contract ERC721ScaledBorrowTest is ERC721DSTestPlus {

    uint256 public constant LARGEST_AMOUNT = type(uint256).max / 10**27;

    address internal _borrower;
    address internal _borrower2;
    address internal _borrower3;
    address internal _lender;
    address internal _lender2;

    address internal _collectionPoolAddress;
    address internal _subsetPoolAddress;

    NFTCollateralToken internal _collateral;
    QuoteToken         internal _quote;
    ERC721Pool         internal _collectionPool;
    ERC721Pool         internal _subsetPool;

    function setUp() external {
        // deploy token and user contracts; mint and set balances
        _collateral = new NFTCollateralToken();
        _quote      = new QuoteToken();

        _borrower  = makeAddr("borrower");
        _borrower2 = makeAddr("borrower2");
        _borrower3 = makeAddr("borrower3");
        _lender    = makeAddr("lender");
        _lender2   = makeAddr("lender2");

        _collateral.mint(address(_borrower),  52);
        _collateral.mint(address(_borrower2), 10);
        _collateral.mint(address(_borrower3), 13);

        deal(address(_quote), _lender, 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Collection State ***/
        /*******************************/

        _collectionPoolAddress = new ERC721PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _collectionPool        = ERC721Pool(_collectionPoolAddress);

        vm.startPrank(_borrower);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_borrower3);
        _collateral.setApprovalForAll(address(_collectionPool), true);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_collectionPool), 200_000 * 1e18);

        /*******************************/
        /*** Setup NFT Subset State ***/
        /*******************************/

        uint256[] memory subsetTokenIds = new uint256[](6);
        subsetTokenIds[0] = 1;
        subsetTokenIds[1] = 3;
        subsetTokenIds[2] = 5;
        subsetTokenIds[3] = 51;
        subsetTokenIds[4] = 53;
        subsetTokenIds[5] = 73;

        _subsetPoolAddress = new ERC721PoolFactory().deploySubsetPool(address(_collateral), address(_quote), subsetTokenIds, 0.05 * 10**18);
        _subsetPool        = ERC721Pool(_subsetPoolAddress);

        changePrank(_borrower);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_borrower2);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_borrower3);
        _collateral.setApprovalForAll(address(_subsetPool), true);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);

        changePrank(_lender);
        _quote.approve(address(_subsetPool), 200_000 * 1e18);
    }

    // TODO: finish implementing
    function testAddCollateral() external {

    }

}