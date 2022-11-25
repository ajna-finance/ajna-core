// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Events
 */
interface IERC721PoolEvents {

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor    Recipient that added collateral.
     *  @param  price    Price at which collateral were added.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    event AddCollateralNFT(
        address indexed actor,
        uint256 indexed price,
        uint256[] tokenIds
    );

    /**
     *  @notice Emitted when NFT auction is completed.
     *  @param  borrower   Address of borrower that exits auction.
     *  @param  collateral Borrower's remaining collateral when auction completed.
     *  @param  lps        Amount of LPs given to the borrower to compensate fractional collateral (if any).
     *  @param  index      Index of the bucket with LPs to compensate fractional collateral.
     */
    event AuctionNFTSettle(
        address indexed borrower,
        uint256 collateral,
        uint256 lps,
        uint256 index
    );

    /**
     *  @notice Emitted when borrower locks collateral in the pool.
     *  @param  borrower `msg.sender`.
     *  @param  tokenIds Array of tokenIds to be added to the pool.
     */
    event PledgeCollateralNFT(
        address indexed borrower,
        uint256[] tokenIds
    );

}