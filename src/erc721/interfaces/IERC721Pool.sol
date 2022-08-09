// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { IScaledPool } from "../../base/interfaces/IScaledPool.sol";

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title Ajna ERC20 Pool
 */
interface IERC721Pool is IScaledPool {

    /**************************/
    /*** ERC721Pool Structs ***/
    /**************************/

     /**
     *  @notice Struct holding borrower related info per price bucket, for borrowers using NFTs as collateral.
     *  @param  debt                Borrower debt, WAD units.
     *  @param  collateralDeposited OZ Enumberable Set tracking the tokenIds of collateral that have been deposited
     *  @param  inflatorSnapshot    Current borrower inflator snapshot, RAY units.
     */
    struct NFTBorrower {
        uint256               debt;                // [WAD]
        EnumerableSet.UintSet collateralDeposited;
        uint256               inflatorSnapshot;    // [WAD]
    }

    /*****************************/
    /*** Initialize Functions ***/
    /*****************************/

    /**
     *  @notice Called by deployNFTSubsetPool()
     *  @dev Used to initialize pools that only support a subset of tokenIds
     */
    function initializeSubset(uint256[] memory tokenIds_, uint256 interestRate_) external;

    /*********************************/
    /*** Lender External Functions ***/
    /*********************************/

    /**
     *  @notice Called by lenders to claim multiple unencumbered collateral from a price bucket.
     *  @param  tokenIds_  NFT token ids to be claimed from the pool.
     *  @param  price_     The bucket from which unencumbered collateral will be claimed.
     *  @return lpTokens_  The actual amount of lpTokens claimed.
     */
    function claimCollateral(uint256[] calldata tokenIds_, uint256 price_) external returns (uint256 lpTokens_);

    /**********************/
    /*** View Functions ***/
    /**********************/

    /**
     *  @notice Check if a token id is allowed as collateral in pool.
     *  @param  tokenId_ The token id to check.
     *  @return allowed_ True if token id is allowed in pool
     */
    function isTokenIdAllowed(uint256 tokenId_) external view returns (bool allowed_);
}
