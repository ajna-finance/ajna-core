// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC721HelperContract } from './ERC721DSTestPlus.sol';

import 'src/ERC721Pool.sol';
import 'src/ERC721PoolFactory.sol';

interface ICryptoFighters {
    function transferFrom(address from_, address to_, uint256 tokenId_) external;
    function transfer(address to_, uint256 tokenId_) external;
    function approve(address to_, uint256 tokenId_) external;
    function ownerOf(uint256 tokenId_) external returns(address);
    function fighterIndexToApproved(uint256 tokenId_) external returns(address);
}

contract ERC721PoolNonStandardNftTest is ERC721HelperContract {
    address internal _borrower;
    address cryptoKittiesAddress = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
    ICryptoKitties cryptoKittiesContract = ICryptoKitties(cryptoKittiesAddress);
    address cryptoFightersAddress = 0x87d598064c736dd0C712D329aFCFAA0Ccc1921A1;
    ICryptoFighters cryptoFightersContract = ICryptoFighters(cryptoFightersAddress);
    address cryptoPunksAddress = 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB;
    ICryptoPunks cryptoPunksContract = ICryptoPunks(cryptoPunksAddress);

    function setUp() external {
        // Borrower has Crypto Kitties/Fighters/Punks in his wallet at specified block 
        vm.createSelectFork(vm.envString("ETH_RPC_URL"), 16167859);
    }

    function testCryptoKittiesNftTransfer() external {
        uint256[] memory tokenIds;
        _pool = ERC721Pool(new ERC721PoolFactory(_ajna).deployPool(cryptoKittiesAddress, address(_quote), tokenIds, 0.05 * 10**18));

        _borrower = 0xDAd45d13472568181B83A731D1e170f4c6e95a83;
        changePrank(_borrower);

        assertEq(cryptoKittiesContract.ownerOf(1777317), _borrower);
        // Borrower approves Nft 
        cryptoKittiesContract.approve(address(_pool), 1777317);

        assertEq(cryptoKittiesContract.kittyIndexToApproved(1777317), address(_pool));

        tokenIds = new uint256[](1);
        tokenIds[0] = 1777317; 

        // Pledge Collateral
        ERC721Pool(address(_pool)).drawDebt(_borrower, 0, 0, tokenIds);

        // Check Pool is owner of NFT
        assertEq(cryptoKittiesContract.ownerOf(1777317), address(_pool));

        // Pull collateral
        ERC721Pool(address(_pool)).repayDebt(_borrower, 0, 1);

        // Check Borrower is owner of NFT
        assertEq(cryptoKittiesContract.ownerOf(1777317), _borrower); 

    }

    function testCryptoFightersNftTransfer() external {
        uint256[] memory tokenIds;
        _pool = ERC721Pool(new ERC721PoolFactory(_ajna).deployPool(cryptoFightersAddress, address(_quote), tokenIds, 0.05 * 10**18));

        _borrower = 0x4E2EAE6ABA4E61Eb16c2D7905a4747323Ca7a504;
        changePrank(_borrower);

        assertEq(cryptoFightersContract.ownerOf(1), _borrower);
        // Borrower approves Nft 
        cryptoFightersContract.approve(address(_pool), 1);

        assertEq(cryptoFightersContract.fighterIndexToApproved(1), address(_pool));

        tokenIds = new uint256[](1);
        tokenIds[0] = 1; 

        // Pledge Collateral
        ERC721Pool(address(_pool)).drawDebt(_borrower, 0, 0, tokenIds);

        // Check Pool is owner of NFT
        assertEq(cryptoFightersContract.ownerOf(1), address(_pool));

        // Pull collateral
        ERC721Pool(address(_pool)).repayDebt(_borrower, 0, 1);

        // Check Borrower is owner of NFT
        assertEq(cryptoFightersContract.ownerOf(1), _borrower); 

    }

    function testCryptoPunksNftTransfer() external {
        uint256[] memory tokenIds;
        _pool = ERC721Pool(new ERC721PoolFactory(_ajna).deployPool(cryptoPunksAddress, address(_quote), tokenIds, 0.05 * 10**18));


        _borrower = 0xB88F61E6FbdA83fbfffAbE364112137480398018;
        changePrank(_borrower);

        // Check Borrower is owner of NFT
        assertEq(cryptoPunksContract.punkIndexToAddress(1), _borrower);

        // Borrower approves Nft 
        cryptoPunksContract.offerPunkForSaleToAddress(1, 0, address(_pool));

        tokenIds = new uint256[](1);
        tokenIds[0] = 1; 

        // Pledge Collateral
        ERC721Pool(address(_pool)).drawDebt(_borrower, 0, 0, tokenIds);

        // Check Pool is owner of NFT
        assertEq(cryptoPunksContract.punkIndexToAddress(1), address(_pool));

        // Pull collateral
        ERC721Pool(address(_pool)).repayDebt(_borrower, 0, 1);

        // Check Borrower is owner of NFT
        assertEq(cryptoPunksContract.punkIndexToAddress(1), _borrower);

    }
}
