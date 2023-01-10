// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { ERC20 }           from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC20 }          from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ERC721 }          from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { EnumerableSet }   from '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import { Multicall }       from '@openzeppelin/contracts/utils/Multicall.sol';
import { ReentrancyGuard } from '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import { SafeERC20 }       from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import { IPool }                        from './interfaces/pool/IPool.sol';
import { IPositionManager }             from './interfaces/position/IPositionManager.sol';
import { IPositionManagerOwnerActions } from './interfaces/position/IPositionManagerOwnerActions.sol';
import { IPositionManagerDerivedState } from './interfaces/position/IPositionManagerDerivedState.sol';

import { ERC20PoolFactory }  from './ERC20PoolFactory.sol';
import { ERC721PoolFactory } from './ERC721PoolFactory.sol';

import { PermitERC721 } from './base/PermitERC721.sol';

import {
    _lpsToQuoteToken,
    _priceAt
}                      from './libraries/helpers/PoolHelper.sol';
import { tokenSymbol } from './libraries/helpers/SafeTokenNamer.sol';

import { PositionNFTSVG } from './libraries/external/PositionNFTSVG.sol';

/**
 *  @title  Position Manager Contract
 *  @notice Used by Pool lenders to optionally mint NFT that represents their positions.
 *          Lenders can:
 *          - mint positions NFT token for a specific pool
 *          - memorialize positions for given buckets
 *          - move liquidity in pool
 *          - redeem positions for given buckets
 *          - burn positions NFT
 */
contract PositionManager is ERC721, PermitERC721, IPositionManager, Multicall, ReentrancyGuard {

    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20     for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => address)                     public override poolKey;     // token id => ajna pool address for which token was minted
    mapping(uint256 => mapping(uint256 => uint256)) public override positionLPs; // token id => bucket index => LPs

    mapping(uint256 => uint96)                internal nonces;          // token id => nonce value used for permit
    mapping(uint256 => EnumerableSet.UintSet) internal positionIndexes; // token id => bucket indexes associated with position

    uint176 private _nextId = 1; // id of the next token that will be minted. Skips 0

    /******************/
    /*** Immutables ***/
    /******************/

    ERC20PoolFactory  private immutable erc20PoolFactory;  // The ERC20 pools factory contract, used to check if address is an Ajna pool
    ERC721PoolFactory private immutable erc721PoolFactory; // The ERC721 pools factory contract, used to check if address is an Ajna pool

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier mayInteract(address pool_, uint256 tokenId_) {

        // revert if token id is not a valid / minted id
        _requireMinted(tokenId_);

        // revert if sender is not owner of or entitled to operate on token id
        if (!_isApprovedOrOwner(msg.sender, tokenId_)) revert NoAuth();

        // revert if the token id is not minted for given pool address
        if (pool_ != poolKey[tokenId_]) revert WrongPool();

        _;
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(
        ERC20PoolFactory erc20Factory_,
        ERC721PoolFactory erc721Factory_
    ) PermitERC721("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {
        erc20PoolFactory  = erc20Factory_;
        erc721PoolFactory = erc721Factory_;
    }

    /********************************/
    /*** Owner External Functions ***/
    /********************************/

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev write state:
     *          - nonces: remove tokenId nonce
     *          - poolKey: remove tokenId => pool mapping
     *  @dev revert on:
     *          - mayInteract:
     *              - token id is not a valid / minted id
     *              - sender is not owner NoAuth()
     *              - token id not minted for given pool WrongPool()
     *          - positions token to burn has liquidity LiquidityNotRemoved()
     *  @dev emit events:
     *          - Burn
     */
    function burn(
        BurnParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) {
        // revert if trying to burn an positions token that still has liquidity
        if (positionIndexes[params_.tokenId].length() != 0) revert LiquidityNotRemoved();

        // remove permit nonces and pool mapping for burned token
        delete nonces[params_.tokenId];
        delete poolKey[params_.tokenId];

        emit Burn(msg.sender, params_.tokenId);

        _burn(params_.tokenId);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - lenderInfo(): get lender position in bucket
     *          - transferLPs(): transfer LPs ownership to PositionManager contracts
     *  @dev write state:
     *          - positionIndexes: add bucket index
     *          - positionLPs: update tokenId => bucket id mapping
     *  @dev revert on:
     *          - positions token to burn has liquidity LiquidityNotRemoved()
     *  @dev emit events:
     *          - MemorializePosition
     */
    function memorializePositions(
        MemorializePositionsParams calldata params_
    ) external override {
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        IPool pool = IPool(poolKey[params_.tokenId]);

        address owner = ownerOf(params_.tokenId);

        uint256 indexesLength = params_.indexes.length;

        for (uint256 i = 0; i < indexesLength; ) {

            // record bucket index at which a position has added liquidity
            // slither-disable-next-line unused-return
            positionIndex.add(params_.indexes[i]);

            (uint256 lpBalance,) = pool.lenderInfo(params_.indexes[i], owner);

            // update token position LPs
            positionLPs[params_.tokenId][params_.indexes[i]] += lpBalance;

            unchecked { ++i; }
        }

        emit MemorializePosition(owner, params_.tokenId);

        // update pool lp token accounting and transfer ownership of lp tokens to PositionManager contract
        pool.transferLPs(owner, address(this), params_.indexes);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev write state:
     *          - poolKey: update tokenId => pool mapping
     *  @dev revert on:
     *          - provided pool not valid NotAjnaPool()
     *  @dev emit events:
     *          - Mint
     */
    function mint(
        MintParams calldata params_
    ) external override returns (uint256 tokenId_) {
        tokenId_ = _nextId++;

        // revert if the address is not a valid Ajna pool
        if (!_isAjnaPool(params_.pool, params_.poolSubsetHash)) revert NotAjnaPool();

        // record which pool the tokenId was minted in
        poolKey[tokenId_] = params_.pool;

        emit Mint(params_.recipient, params_.pool, tokenId_);

        _safeMint(params_.recipient, tokenId_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - bucketInfo(): get from bucket info
     *          - moveQuoteToken(): move liquidity between buckets
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *          - positionIndexes: add to bucket index
     *          - positionLPs: decrement from bucket LPs
     *          - positionLPs: increment to bucket LPs
     *  @dev revert on:
     *          - mayInteract:
     *              - token id is not a valid / minted id
     *              - sender is not owner NoAuth()
     *              - token id not minted for given pool WrongPool()
     *          - positions token to burn has liquidity LiquidityNotRemoved()
     *  @dev emit events:
     *          - MoveLiquidity
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) nonReentrant {
        // retrieve info of bucket from which liquidity is moved  
        (
            uint256 bucketLPs,
            uint256 bucketCollateral,
            ,
            uint256 bucketDeposit,
        ) = IPool(params_.pool).bucketInfo(params_.fromIndex);

        // calculate the max amount of quote tokens that can be moved, given the tracked LPs
        uint256 maxQuote = _lpsToQuoteToken(
            bucketLPs,
            bucketCollateral,
            bucketDeposit,
            positionLPs[params_.tokenId][params_.fromIndex],
            bucketDeposit,
            _priceAt(params_.fromIndex)
        );

        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        // remove bucket index from which liquidity is moved from tracked positions
        if (!positionIndex.remove(params_.fromIndex)) revert RemoveLiquidityFailed();

        // update bucket set at which a position has liquidity
        // slither-disable-next-line unused-return
        positionIndex.add(params_.toIndex);

        emit MoveLiquidity(ownerOf(params_.tokenId), params_.tokenId);

        // move quote tokens in pool
        (
            uint256 lpbAmountFrom,
            uint256 lpbAmountTo
        ) = IPool(params_.pool).moveQuoteToken(
            maxQuote,
            params_.fromIndex,
            params_.toIndex
        );

        // update position LPs state
        positionLPs[params_.tokenId][params_.fromIndex] -= lpbAmountFrom;
        positionLPs[params_.tokenId][params_.toIndex]   += lpbAmountTo;
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - approveLpOwnership(): approve ownership for transfer
     *          - transferLPs(): transfer LPs ownership from PositionManager contract
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *          - positionLPs: delete bucket LPs
     *  @dev revert on:
     *          - mayInteract:
     *              - token id is not a valid / minted id
     *              - sender is not owner NoAuth()
     *              - token id not minted for given pool WrongPool()
     *          - position not tracked RemoveLiquidityFailed()
     *  @dev emit events:
     *          - RedeemPosition
     */
    function reedemPositions(
        RedeemPositionsParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) {

        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        IPool pool = IPool(poolKey[params_.tokenId]);

        uint256 indexesLength = params_.indexes.length;

        address owner = ownerOf(params_.tokenId);

        for (uint256 i = 0; i < indexesLength; ) {

            // remove bucket index at which a position has added liquidity
            if (!positionIndex.remove(params_.indexes[i])) revert RemoveLiquidityFailed();

            uint256 lpAmount = positionLPs[params_.tokenId][params_.indexes[i]];

            // remove LPs tracked by position manager at bucket index
            delete positionLPs[params_.tokenId][params_.indexes[i]];

            // approve owner to take over the LPs ownership (required for transferLPs pool call)
            pool.approveLpOwnership(owner, params_.indexes[i], lpAmount);

            unchecked { ++i; }
        }

        emit RedeemPosition(owner, params_.tokenId);

        // update pool lp token accounting and transfer ownership of lp tokens from PositionManager contract
        pool.transferLPs(address(this), owner, params_.indexes);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @dev    Retrieves token's next nonce for permit.
     *  @param  tokenId_ Address of the Ajna pool to retrieve accumulators of.
     *  @return Incremented token permit nonce.
     */
    function _getAndIncrementNonce(
        uint256 tokenId_
    ) internal override returns (uint256) {
        return uint256(nonces[tokenId_]++);
    }

    /**
     *  @dev    Checks that a provided pool address was deployed by an Ajna factory.
     *  @param  pool_       Address of the Ajna pool.
     *  @param  subsetHash_ Factory's subset hash pool.
     *  @return True if a valid Ajna pool false otherwise.
     */
    function _isAjnaPool(
        address pool_,
        bytes32 subsetHash_
    ) internal view returns (bool) {
        address collateralAddress = IPool(pool_).collateralAddress();
        address quoteAddress      = IPool(pool_).quoteTokenAddress();

        address erc20DeployedPoolAddress  = erc20PoolFactory.deployedPools(subsetHash_, collateralAddress, quoteAddress);
        address erc721DeployedPoolAddress = erc721PoolFactory.deployedPools(subsetHash_, collateralAddress, quoteAddress);

        return (pool_ == erc20DeployedPoolAddress || pool_ == erc721DeployedPoolAddress);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @inheritdoc IPositionManagerDerivedState
    function getLPTokens(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (uint256) {
        return positionLPs[tokenId_][index_];
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionIndexes(
        uint256 tokenId_
    ) external view override returns (uint256[] memory) {
        return positionIndexes[tokenId_].values();
    }

    /// @inheritdoc IPositionManagerDerivedState
    function isIndexInPosition(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (bool) {
        return positionIndexes[tokenId_].contains(index_);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId_
    ) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_));

        address collateralTokenAddress = IPool(poolKey[tokenId_]).collateralAddress();
        address quoteTokenAddress      = IPool(poolKey[tokenId_]).quoteTokenAddress();

        PositionNFTSVG.ConstructTokenURIParams memory params = PositionNFTSVG.ConstructTokenURIParams({
            collateralTokenSymbol: tokenSymbol(collateralTokenAddress),
            quoteTokenSymbol:      tokenSymbol(quoteTokenAddress),
            tokenId:               tokenId_,
            pool:                  poolKey[tokenId_],
            owner:                 ownerOf(tokenId_),
            indexes:               positionIndexes[tokenId_].values()
        });

        return PositionNFTSVG.constructTokenURI(params);
    }

}
