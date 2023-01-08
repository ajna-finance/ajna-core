// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { ClonesWithImmutableArgs } from '@clones/ClonesWithImmutableArgs.sol';
import { IERC165 }                 from '@openzeppelin/contracts/utils/introspection/IERC165.sol';

import { IERC721PoolFactory } from './interfaces/pool/erc721/IERC721PoolFactory.sol';
import { NFTTypes }           from './interfaces/pool/erc721/IERC721NonStandard.sol';

import { IERC20Token, PoolType } from './interfaces/pool/IPool.sol';

import { ERC721Pool }   from './ERC721Pool.sol';
import { PoolDeployer } from './base/PoolDeployer.sol';

/**
 *  @title  ERC721 Pool Factory
 *  @notice Pool factory contract for creating ERC721 pools. If a list with token ids is provided then a subset ERC721 pool is created for the NFT.
 *  @notice Pool creators can: create pool by providing a fungible token for quote, a non fungible token for collateral and an interest rate between 1-10%
 *  @dev    Reverts if pool is already created or if params to deploy new pool are invalid.
 */
contract ERC721PoolFactory is PoolDeployer, IERC721PoolFactory {

    using ClonesWithImmutableArgs for address;

    ERC721Pool public implementation;

    /// @dev Default bytes32 hash used by ERC721 Non-NFTSubset pool types
    bytes32 public constant ERC721_NON_SUBSET_HASH = keccak256("ERC721_NON_SUBSET_HASH");

    constructor(address ajna_) {
        if (ajna_ == address(0)) revert DeployWithZeroAddress();

        ajna = ajna_;

        implementation = new ERC721Pool();
    }

    /**
     *  @inheritdoc IERC721PoolFactory
     *  @dev  immutable args:
     *          - pool type; ajna, collateral and quote address; quote scale; number of token ids in subset; NFT type
     *  @dev  write state:
     *          - deployedPools mapping
     *          - deployedPoolsList array
     *  @dev reverts on:
     *          - 0x address provided as quote or collateral DeployWithZeroAddress()
     *          - pool with provided quote / collateral pair already exists PoolAlreadyExists()
     *          - invalid interest rate provided PoolInterestRateInvalid()
     *          - not supported NFT provided NFTNotSupported()
     *  @dev emit events:
     *          - PoolCreated
     */
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
