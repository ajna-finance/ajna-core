// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { ERC20 }           from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 }          from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { EnumerableSet }   from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeERC20 }       from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IScaledPool }      from "./interfaces/IScaledPool.sol";
import { IPositionManager } from "./interfaces/IPositionManager.sol";

import { IERC20Pool }  from "../erc20/interfaces/IERC20Pool.sol";
import { IERC721Pool } from "../erc721/interfaces/IERC721Pool.sol";

import { Multicall }   from "./Multicall.sol";
import { PermitERC20 } from "./PermitERC20.sol";
import { PositionNFT } from "./PositionNFT.sol";

import { Maths } from "../libraries/Maths.sol";

contract PositionManager is IPositionManager, Multicall, PositionNFT, PermitERC20, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for ERC20;

    constructor() PositionNFT("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {}

    /***********************/
    /*** State Variables ***/
    /***********************/

    /** @dev Mapping of tokenIds to Pool address */
    mapping(uint256 => address) public poolKey;

    /** @dev Mapping of tokenIds to Position struct */
    mapping(uint256 => Position) public positions;

    /** @dev Mapping of tokenIds to set of prices associated with a Position */
    mapping(uint256 => EnumerableSet.UintSet) internal positionPrices;

    /** @dev The ID of the next token that will be minted. Skips 0 */
    uint176 private _nextId = 1;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier mayInteract(address pool_, uint256 tokenId_) {
        require(_isApprovedOrOwner(msg.sender, tokenId_), "PM:NO_AUTH");
        require(pool_ == poolKey[tokenId_], "PM:W_POOL");
        _;
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    function burn(BurnParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) {
        require(positionPrices[params_.tokenId].length() == 0, "PM:B:LIQ_NOT_REMOVED");

        IScaledPool pool = IScaledPool(params_.pool);
        emit Burn(msg.sender, pool.indexToPrice(params_.index));

        delete positions[params_.tokenId];
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) nonReentrant {
        uint256 curPos        = positions[params_.tokenId].lpTokens[params_.index];
        uint256 lpTokensToUse = params_.lpTokens;
        require(lpTokensToUse <= curPos, "PM:DL:INSUF_LP_BAL");

        // Positions accounting
        if (curPos == lpTokensToUse) {
            positionPrices[params_.tokenId].remove(params_.index);
        } else {
            positions[params_.tokenId].lpTokens[params_.index] = curPos - lpTokensToUse;
        }

        // Pool interactions
        IERC20Pool pool = IERC20Pool(params_.pool);
        // calculate equivalent underlying collateral for given lpTokens
        uint256 collateralToRemove = pool.lpsToCollateral(lpTokensToUse, params_.index);

        if (collateralToRemove != 0) {
            // claim any unencumbered collateral accrued to the price bucket
            lpTokensToUse -= pool.removeCollateral(collateralToRemove, params_.index);

            // transfer claimed collateral to recipient
            ERC20(pool.collateralTokenAddress()).safeTransfer(params_.recipient, collateralToRemove);
        }

        // calculate equivalent quote tokens for remaining lpTokens
        uint256 quoteTokensToRemove = pool.lpsToQuoteTokens(lpTokensToUse, params_.index);
        // remove and transfer quote tokens to recipient
        uint256 quoteRemoved = pool.removeQuoteToken(quoteTokensToRemove, params_.index);
        ERC20(pool.quoteTokenAddress()).safeTransfer(params_.recipient, quoteRemoved);
        emit DecreaseLiquidity(params_.recipient, pool.indexToPrice(params_.index), collateralToRemove, quoteRemoved);
    }

    function decreaseLiquidityNFT(DecreaseLiquidityNFTParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) nonReentrant {
        require(params_.lpTokens <= positions[params_.tokenId].lpTokens[params_.index], "PM:DL:INSUF_LP_BAL");

        IERC721Pool pool = IERC721Pool(params_.pool);

        // calculate equivalent underlying collateral for given lpTokens
        uint256 collateralToRemove = pool.lpsToCollateral(params_.lpTokens, params_.index);

        uint256[] memory tokensToRemove;
        uint256 lpTokensClaimed;

        // enable lenders to remove quote token from a bucket that no debt is added to
        if (collateralToRemove != 0) {
            // slice incoming tokens to only use as many as are required
            uint256 indexToUse = Maths.wadToIntRoundingDown(collateralToRemove);
            tokensToRemove = new uint256[](indexToUse);
            tokensToRemove = params_.tokenIdsToRemove[:indexToUse];

            // claim any unencumbered collateral accrued to the price bucket
            lpTokensClaimed = pool.removeCollateral(tokensToRemove, params_.index);

            // transfer claimed collateral to recipient
            uint256 tokensToRemoveLength = tokensToRemove.length;
            for (uint256 i = 0; i < tokensToRemoveLength; ) {
                ERC721(pool.collateralTokenAddress()).safeTransferFrom(address(this), params_.recipient, tokensToRemove[i]);
                unchecked {
                    ++i;
                }
            }
        } else {
            tokensToRemove = new uint[](0);
        }

        // update position with newly removed lp tokens
        positions[params_.tokenId].lpTokens[params_.index] -= (params_.lpTokens + lpTokensClaimed);

        // update price set for liquidity removed
        if (positions[params_.tokenId].lpTokens[params_.index] == 0) {
            positionPrices[params_.tokenId].remove(params_.index);
        }

        // remove and transfer quote tokens to recipient
        uint256 quoteRemoved = pool.removeQuoteToken(params_.lpTokens, params_.index);
        ERC20(pool.quoteTokenAddress()).safeTransfer(params_.recipient, quoteRemoved);
        emit DecreaseLiquidityNFT(params_.recipient, pool.indexToPrice(params_.index), tokensToRemove, quoteRemoved);
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) {
        // transfer quote tokens from the sender to the position manager escrow
        IScaledPool pool = IScaledPool(params_.pool);
        ERC20(pool.quoteTokenAddress()).safeTransferFrom(params_.recipient, address(this), params_.amount);
        
        // Call out to pool contract to add quote tokens
        uint256 lpTokensAdded = pool.addQuoteToken(params_.amount, params_.index);
        require(lpTokensAdded != 0, "PM:IL:NO_LP_TOKENS");

        // update position with newly added lp shares
        positions[params_.tokenId].lpTokens[params_.index] += lpTokensAdded;

        // record price at which a position has added liquidity
        positionPrices[params_.tokenId].add(params_.index);

        emit IncreaseLiquidity(params_.recipient, pool.indexToPrice(params_.index), params_.amount);
    }

    /// TODO: (X) indexes can be memorialized at a time
    function memorializePositions(MemorializePositionsParams calldata params_) external override {
        Position storage position = positions[params_.tokenId];
        IScaledPool pool = IScaledPool(poolKey[params_.tokenId]);

        uint256 indexesLength = params_.indexes.length;
        for (uint256 i = 0; i < indexesLength; ) {
            // update PositionManager accounting
            position.lpTokens[params_.indexes[i]] = pool.lpBalance(
                params_.indexes[i],
                params_.owner
            );

            // record price at which a position has added liquidity
            positionPrices[params_.tokenId].add(params_.indexes[i]);

            // increment call counter in gas efficient way by skipping safemath checks
            unchecked {
                ++i;
            }
        }

        // update pool lp token accounting and transfer ownership of lp tokens to PositionManager contract
        pool.transferLPTokens(params_.owner, address(this), params_.indexes);

        emit MemorializePosition(params_.owner, params_.tokenId);
    }

    function mint(MintParams calldata params_) external override payable returns (uint256 tokenId_) {
        _safeMint(params_.recipient, (tokenId_ = _nextId++));

        // create a new position associated with the newly minted tokenId
        positions[tokenId_].pool = params_.pool;

        // record which pool the tokenId was minted in
        poolKey[tokenId_] = params_.pool;

        // approve spending of quote tokens if it hasn't occured already
        ERC20(IScaledPool(params_.pool).quoteTokenAddress()).approve(params_.pool, type(uint256).max);

        emit Mint(params_.recipient, params_.pool, tokenId_);
    }

    function moveLiquidity(MoveLiquidityParams calldata params_) external override mayInteract(params_.pool, params_.tokenId) {
        IScaledPool pool = IScaledPool(params_.pool);

        uint256 maxQuote = pool.lpsToQuoteTokens(
            positions[params_.tokenId].lpTokens[params_.fromIndex], params_.fromIndex
        );
        pool.moveQuoteToken(maxQuote, params_.fromIndex, params_.toIndex);

        // update prices set at which a position has liquidity
        positionPrices[params_.tokenId].remove(params_.fromIndex);
        positionPrices[params_.tokenId].add(params_.toIndex);


        emit MoveLiquidity(params_.owner, params_.tokenId);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     * @notice Override ERC721 afterTokenTransfer hook to ensure that transferred NFT's are properly tracked within the PositionManager data struct
     * @dev    This call also executes upon Mint
    */
    function _afterTokenTransfer(address, address to_, uint256 tokenId_) internal virtual override(ERC721) {
        positions[tokenId_].owner = to_;
    }

    /** @dev Used for tracking nonce input to permit function */
    function _getAndIncrementNonce(uint256 tokenId_) internal override returns (uint256) {
        return uint256(positions[tokenId_].nonce++);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getLPTokens(uint256 tokenId_, uint256 index_) external override view returns (uint256) {
        return positions[tokenId_].lpTokens[index_];
    }

    function tokenURI(uint256 tokenId_) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_));

        ConstructTokenURIParams memory params = ConstructTokenURIParams(tokenId_, positions[tokenId_].pool, positionPrices[tokenId_].values());

        return constructTokenURI(params);
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
