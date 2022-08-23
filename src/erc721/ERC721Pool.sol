// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Clone } from "@clones/Clone.sol";

import { ERC20 }         from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 }     from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC721 }        from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { IERC721Pool } from "./interfaces/IERC721Pool.sol";

import { ScaledPool } from "../base/ScaledPool.sol";

// Added
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ERC721Pool is IERC721Pool, ScaledPool {
    using SafeERC20     for ERC20;
    using EnumerableSet for EnumerableSet.UintSet;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Set of tokenIds that are currently being used as collateral
    EnumerableSet.UintSet internal _collateralTokenIdsAdded;

    /**
     *  @notice Mapping of price to Set of NFT Token Ids that have been deposited into the bucket
     *  @dev price [WAD] -> collateralDeposited
     */
    mapping(uint256 => EnumerableSet.UintSet) internal _collateralDeposited;

    /// @dev Set of tokenIds that can be used for a given NFT Subset type pool
    /// @dev Defaults to length 0 if the whole collection is to be used
    EnumerableSet.UintSet internal _tokenIdsAllowed;

    // TODO: rename
    /// @dev Internal visibility is required as it contains a nested struct
    // borrowers book: borrower address -> NFTBorrower
    mapping(address => NFTBorrower) internal _NFTborrowers;

    /****************************/
    /*** Initialize Functions ***/
    /****************************/

    function initialize(uint256 rate_) external {
        require(poolInitializations == 0, "P:INITIALIZED");

        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = 10**18;
        lastInflatorSnapshotUpdate = block.timestamp;
        lenderInterestFactor       = 0.9 * 10**18;
        interestRate               = rate_;
        interestRateUpdate         = block.timestamp;
        minFee                     = 0.0005 * 10**18;

        // increment initializations count to ensure these values can't be updated
        poolInitializations += 1;
    }

    function initializeSubset(uint256[] memory tokenIds_, uint256 rate_) external override {
        this.initialize(rate_);

        // add subset of tokenIds allowed in the pool
        for (uint256 id; id < tokenIds_.length;) {
            _tokenIdsAllowed.add(tokenIds_[id]);
            unchecked {
                ++id;
            }
        }
    }

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    function removeCollateral(uint256[] calldata tokenIds_, uint256 index_) external returns (uint256 lpRedemption_) {
        // TODO backport
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function isTokenIdAllowed(uint256 tokenId_) external view override returns (bool) {
        return _tokenIdsAllowed.contains(tokenId_);
    }

    /************************/
    /*** Helper Functions ***/
    /************************/

    /** @dev Collateral tokens are always non-fungible
     *  @dev Pure function used to facilitate accessing token via clone state
     */
    function collateral() public pure returns (ERC721) {
        return ERC721(_getArgAddress(0));
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
