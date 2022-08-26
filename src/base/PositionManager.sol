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

    /** @dev Mapping of tokenIds to nonce values used for permit */
    mapping(uint256 => uint96) public nonces;

    /** @dev Mapping of tokenIds to pool lps */
    mapping(uint256 => mapping(uint256 => uint256)) public lps;

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

        emit Burn(msg.sender, params_.tokenId);
        delete nonces[params_.tokenId];
        delete poolKey[params_.tokenId];

        _burn(params_.tokenId);
    }

    /// TODO: (X) indexes can be memorialized at a time
    function memorializePositions(MemorializePositionsParams calldata params_) external override {
        EnumerableSet.UintSet storage positionPrice = positionPrices[params_.tokenId];

        IScaledPool pool      = IScaledPool(poolKey[params_.tokenId]);
        uint256 indexesLength = params_.indexes.length;
        for (uint256 i = 0; i < indexesLength; ) {
            // record price at which a position has added liquidity
            if (!positionPrice.contains(params_.indexes[i])) require(positionPrice.add(params_.indexes[i]), "PM:ME:ADD_FAIL");

            // update PositionManager accounting
            (uint256 lpBalance, ) = pool.bucketLenders(params_.indexes[i], params_.owner);
            lps[params_.tokenId][params_.indexes[i]] += lpBalance;

            // increment call counter in gas efficient way by skipping safemath checks
            unchecked {
                ++i;
            }
        }

        // update pool lp token accounting and transfer ownership of lp tokens to PositionManager contract
        emit MemorializePosition(params_.owner, params_.tokenId);
        pool.transferLPTokens(params_.owner, address(this), params_.indexes);
    }

    function mint(MintParams calldata params_) external override payable returns (uint256 tokenId_) {
        _safeMint(params_.recipient, (tokenId_ = _nextId++));

        // record which pool the tokenId was minted in
        poolKey[tokenId_] = params_.pool;

        emit Mint(params_.recipient, params_.pool, tokenId_);
    }

    function moveLiquidity(MoveLiquidityParams calldata params_) external override mayInteract(params_.pool, params_.tokenId) {

        IScaledPool pool = IScaledPool(params_.pool);
        uint256 maxQuote = pool.lpsToQuoteTokens(
            pool.depositAt(params_.fromIndex),  lps[params_.tokenId][params_.fromIndex], params_.fromIndex
        );

        // update prices set at which a position has liquidity
        EnumerableSet.UintSet storage positionPrice = positionPrices[params_.tokenId];
        require(positionPrice.remove(params_.fromIndex), "PM:MV:REMOVE_FAIL");
        if (!positionPrice.contains(params_.toIndex)) require(positionPrice.add(params_.toIndex), "PM:MV:ADD_FAIL");

        // move quote tokens in pool
        emit MoveLiquidity(params_.owner, params_.tokenId);
        (uint256 lpbAmount, uint256 lpbChange) = pool.moveQuoteToken(maxQuote, params_.fromIndex, params_.toIndex);

        // update tracked LPs
        lps[params_.tokenId][params_.fromIndex] -= lpbAmount;
        lps[params_.tokenId][params_.toIndex]   += lpbChange;
    }

    function reedemPositions(RedeemPositionsParams calldata params_) external override mayInteract(params_.pool, params_.tokenId) {
        EnumerableSet.UintSet storage positionPrice = positionPrices[params_.tokenId];

        IScaledPool pool      = IScaledPool(poolKey[params_.tokenId]);
        uint256 indexesLength = params_.indexes.length;
        for (uint256 i = 0; i < indexesLength; ) {
            // remove price at which a position has added liquidity
            require(positionPrice.remove(params_.indexes[i]), "PM:R:REMOVE_FAIL");

            pool.approveLpOwnership(params_.owner, params_.indexes[i], lps[params_.tokenId][params_.indexes[i]]);

            // update PositionManager accounting
            delete lps[params_.tokenId][params_.indexes[i]];

            // increment call counter in gas efficient way by skipping safemath checks
            unchecked {
                ++i;
            }
        }

        // update pool lp token accounting and transfer ownership of lp tokens from PositionManager contract
        emit RedeemPosition(params_.owner, params_.tokenId);
        pool.transferLPTokens(address(this), params_.owner, params_.indexes);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /** @dev Used for tracking nonce input to permit function */
    function _getAndIncrementNonce(uint256 tokenId_) internal override returns (uint256) {
        return uint256(nonces[tokenId_]++);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getLPTokens(uint256 tokenId_, uint256 index_) external override view returns (uint256) {
        return lps[tokenId_][index_];
    }

    function isIndexInPosition(uint256 tokenId_, uint256 index_) external override view returns (bool) {
        return positionPrices[tokenId_].contains(index_);
    }

    function tokenURI(uint256 tokenId_) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_));

        ConstructTokenURIParams memory params = ConstructTokenURIParams(tokenId_, poolKey[tokenId_], positionPrices[tokenId_].values());
        return constructTokenURI(params);
    }

    /** @notice Implementing this method allows contracts to receive ERC721 tokens
     *  @dev https://forum.openzeppelin.com/t/erc721holder-ierc721receiver-and-onerc721received/11828
     */
    function onERC721Received(address, address, uint256, bytes memory) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

}
