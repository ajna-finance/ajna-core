// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';
import '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import '../base/interfaces/IPoolFactory.sol';
import '../base/PoolDeployer.sol';

import './interfaces/IERC721PoolFactory.sol';
import './ERC721Pool.sol';

contract ERC721PoolFactory is IERC721PoolFactory, PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;

    /// @dev Default bytes32 hash used by ERC721 Non-NFTSubset pool types
    bytes32 public constant ERC721_NON_SUBSET_HASH = keccak256("ERC721_NON_SUBSET_HASH");

    constructor(address ajna_) {
        if (ajna_ == address(0)) revert DeployWithZeroAddress();

        ajna           = ajna_;
        implementation = new ERC721Pool();
    }

    function deployPool(
        address collateral_, address quote_, uint256[] memory tokenIds_, uint256 interestRate_
    ) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_, interestRate_) returns (address pool_) {
        uint256 quoteTokenScale = 10**(18 - IERC20Token(quote_).decimals());

        NFTTypes nftType;
        // CryptoPunks NFTs
        if ( collateral_ == 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB ) {
            nftType = NFTTypes.CRYPTOPUNKS;
        }
        // CryptoKitties and CryptoFighters NFTs
        else if ( collateral_ == 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d || collateral_ ==  0x87d598064c736dd0C712D329aFCFAA0Ccc1921A1 ){
            nftType = NFTTypes.CRYPTOKITTIES;
        }
        // All other NFTs that support the EIP721 standard 
        else {
            // Here 0x80ac58cd is the ERC721 interface Id
            bool supportsERC721Interface = IERC165(collateral_).supportsInterface(0x80ac58cd);

            // Neither a standard NFT nor a non-standard supported NFT(punk, kitty or fighter)
            if (!supportsERC721Interface) revert NFTNotSupported();

            nftType = NFTTypes.STANDARD_ERC721;
        }

        bytes memory data = abi.encodePacked(
            collateral_,
            quote_,
            quoteTokenScale,
            ajna,
            tokenIds_.length,
            nftType
        );

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));
        pool_ = address(pool);
        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = pool_;
        emit PoolCreated(pool_);

        pool.initialize(tokenIds_, interestRate_);
    }

    /*********************************/
    /*** Pool Creation Functions ***/
    /*********************************/

    function getNFTSubsetHash(uint256[] memory tokenIds_) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(tokenIds_));
    }
}
