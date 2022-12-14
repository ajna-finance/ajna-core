// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

/**
 * @title ERC721 Pool Events
 */
interface IERC721PoolEvents {

    /**
     *  @notice Emitted when actor adds unencumbered collateral to a bucket.
     *  @param  actor     Recipient that added collateral.
     *  @param  price     Price at which collateral were added.
     *  @param  tokenIds  Array of tokenIds to be added to the pool.
     *  @param  lpAwarded Amount of LP awarded for the deposit. 
     */
    event AddCollateralNFT(
        address indexed actor,
        uint256 indexed price,
        uint256[] tokenIds,
        uint256   lpAwarded
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
     *  @notice Emitted when borrower draws debt from the pool, or adds collateral to the pool.
     *  @param  borrower          `msg.sender`.
     *  @param  amountBorowed     Amount of quote tokens borrowed from the pool.
     *  @param  tokenIdsPledged   Array of tokenIds to be added to the pool.
     *  @param  lup               LUP after borrow.
     */
    event DrawDebtNFT(
        address indexed borrower,
        uint256   amountBorowed,
        uint256[] tokenIdsPledged,
        uint256   lup
    );
}
