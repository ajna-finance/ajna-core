// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';
import { IERC165 } from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import { IERC721PoolFactory }    from 'src/erc721/interfaces/IERC721PoolFactory.sol';
import { IERC20Token, PoolType } from 'src/base/interfaces/IPool.sol';
import { NFTTypes }              from 'src/erc721/interfaces/IERC721NonStandard.sol';

import { ERC721Pool }   from 'src/erc721/ERC721Pool.sol';
import { PoolDeployer } from 'src/base/PoolDeployer.sol';

contract ERC721PoolFactory is IERC721PoolFactory, PoolDeployer {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;

    /// @dev Default bytes32 hash used by ERC721 Non-NFTSubset pool types
    bytes32 public constant ERC721_NON_SUBSET_HASH = keccak256("ERC721_NON_SUBSET_HASH");

    constructor(address ajna_) {
        if (ajna_ == address(0)) revert DeployWithZeroAddress();

        ajna = ajna_;

        implementation = new ERC721Pool();
    }

    function deployPool(
        address collateral_, address quote_, uint256[] memory tokenIds_, uint256 interestRate_
    ) external canDeploy(getNFTSubsetHash(tokenIds_), collateral_, quote_, interestRate_) returns (address pool_) {
        uint256 quoteTokenScale = 10**(18 - IERC20Token(quote_).decimals());

        NFTTypes nftType;
        // CryptoPunks NFTs
        if (collateral_ == 0xb47e3cd837dDF8e4c57F05d70Ab865de6e193BBB ) {
            nftType = NFTTypes.CRYPTOPUNKS;
        }
        // CryptoKitties and CryptoFighters NFTs
        else if (collateral_ == 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d || collateral_ ==  0x87d598064c736dd0C712D329aFCFAA0Ccc1921A1) {
            nftType = NFTTypes.CRYPTOKITTIES;
        }
        // All other NFTs that support the EIP721 standard
        else {
            // Here 0x80ac58cd is the ERC721 interface Id
            // Neither a standard NFT nor a non-standard supported NFT(punk, kitty or fighter)
            try IERC165(collateral_).supportsInterface(0x80ac58cd) returns (bool supportsERC721Interface) {
                if (!supportsERC721Interface) revert NFTNotSupported();
            } catch {
                revert NFTNotSupported();
            }

            nftType = NFTTypes.STANDARD_ERC721;
        }

        bytes memory data = abi.encodePacked(
            PoolType.ERC721,
            ajna,
            collateral_,
            quote_,
            quoteTokenScale,
            tokenIds_.length,
            nftType
        );

        ERC721Pool pool = ERC721Pool(address(implementation).clone(data));

        pool_ = address(pool);

        // Track the newly deployed pool
        deployedPools[getNFTSubsetHash(tokenIds_)][collateral_][quote_] = pool_;
        deployedPoolsList.push(pool_);

        emit PoolCreated(pool_);

        pool.initialize(tokenIds_, interestRate_);
    }

    /*******************************/
    /*** Pool Creation Functions ***/
    /*******************************/

    function getNFTSubsetHash(uint256[] memory tokenIds_) public pure returns (bytes32) {
        if (tokenIds_.length == 0) return ERC721_NON_SUBSET_HASH;
        else return keccak256(abi.encodePacked(tokenIds_));
    }
}
