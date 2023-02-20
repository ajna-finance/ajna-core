// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { ERC20 }           from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC20 }          from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { ERC721 }          from '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import { IERC165 }         from '@openzeppelin/contracts/utils/introspection/IERC165.sol';
import { Address }         from '@openzeppelin/contracts/utils/Address.sol';
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
 *          - track positions for given buckets
 *          - move liquidity in pool
 *          - untrack positions for given buckets
 *          - transfer LPs to the new NFT owner on position NFT transfer
 *          - burn positions NFT
 */
contract PositionManager is ERC721, PermitERC721, IPositionManager, Multicall, ReentrancyGuard {

    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20     for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    mapping(uint256 => address) public override poolKey; // token id => ajna pool address for which token was minted

    mapping(uint256 => uint96)                internal nonces;          // token id => nonce value used for permit
    mapping(uint256 => EnumerableSet.UintSet) internal positionIndexes; // token id => bucket indexes associated with position

    mapping(address => mapping(address => mapping(uint256 => bool))) internal lenderTrackedPoolPositions; // lender address => pool address => position index => bool tracked

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
     *          - positions token to burn has tracked positions PositionNotUntracked()
     *  @dev emit events:
     *          - Burn
     */
    function burn(
        BurnParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) {
        // revert if trying to burn an positions token that still has liquidity
        if (positionIndexes[params_.tokenId].length() != 0) revert PositionNotUntracked();

        // remove permit nonces and pool mapping for burned token
        delete nonces[params_.tokenId];
        delete poolKey[params_.tokenId];

        _burn(params_.tokenId);

        emit Burn(msg.sender, params_.tokenId);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev write state:
     *          - positionIndexes: add bucket index
     *  @dev emit events:
     *          - TrackPositions
     */
    function trackPositions(
        TrackPositionsParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) {
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        address owner = ownerOf(params_.tokenId);

        mapping(uint256 => bool) storage trackedPositions = lenderTrackedPoolPositions[owner][params_.pool];

        uint256 indexesLength = params_.indexes.length;
        uint256 index;

        for (uint256 i = 0; i < indexesLength; ) {
            index = params_.indexes[i];

            // revert if this contract is not approved as LP manager
            if (IPool(params_.pool).lpManagers(owner, index) != address(this)) revert NotLPsManager();

            if (trackedPositions[index]) revert PositionAlreadyTracked();

            // slither-disable-next-line unused-return
            positionIndex.add(index);

            trackedPositions[index] = true;

            unchecked { ++i; }
        }

        emit TrackPositions(owner, params_.tokenId, params_.indexes);
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
    ) external override nonReentrant returns (uint256 tokenId_) {
        tokenId_ = _nextId++;

        // revert if the address is not a valid Ajna pool
        if (!_isAjnaPool(params_.pool, params_.poolSubsetHash)) revert NotAjnaPool();

        // record which pool the tokenId was minted in
        poolKey[tokenId_] = params_.pool;

        _safeMint(params_.recipient, tokenId_);

        emit Mint(params_.recipient, params_.pool, tokenId_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - bucketInfo(): get from bucket info
     *          - lenderInfo(): get lender info
     *          - moveQuoteToken(): move liquidity between buckets
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *          - positionIndexes: add to bucket index
     *  @dev revert on:
     *          - mayInteract:
     *              - token id is not a valid / minted id
     *              - sender is not owner NoAuth()
     *              - token id not minted for given pool WrongPool()
     *  @dev emit events:
     *          - MoveLiquidity
     */
    function moveLiquidity(
        MoveLiquidityParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) nonReentrant {
        address lender = ownerOf(params_.tokenId);

        // revert if this contract is not approved as LP manager for from and to indexes
        if (
            IPool(params_.pool).lpManagers(lender, params_.fromIndex) != address(this) ||
            IPool(params_.pool).lpManagers(lender, params_.toIndex)   != address(this)
        ) revert NotLPsManager();

        // retrieve info of bucket from which liquidity is moved  
        (
            uint256 bucketLPs,
            uint256 bucketCollateral,
            ,
            uint256 bucketDeposit,
        ) = IPool(params_.pool).bucketInfo(params_.fromIndex);

        (uint256 lpBalance, ) = IPool(params_.pool).lenderInfo(params_.fromIndex, lender);

        // calculate the max amount of quote tokens that can be moved, given the tracked LPs
        uint256 maxQuote = _lpsToQuoteToken(
            bucketLPs,
            bucketCollateral,
            bucketDeposit,
            lpBalance,
            bucketDeposit,
            _priceAt(params_.fromIndex)
        );

        // move quote tokens in pool
        IPool(params_.pool).moveQuoteToken(
            ownerOf(params_.tokenId),
            maxQuote,
            params_.fromIndex,
            params_.toIndex,
            params_.expiry
        );

        emit MoveLiquidity(ownerOf(params_.tokenId), params_.tokenId);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *  @dev revert on:
     *          - mayInteract:
     *              - token id is not a valid / minted id
     *              - sender is not owner NoAuth()
     *              - token id not minted for given pool WrongPool()
     *          - position not tracked UntrackPositionFailed()
     *  @dev emit events:
     *          - UntrackPositions
     */
    function untrackPositions(
        UntrackPositionsParams calldata params_
    ) external override mayInteract(params_.pool, params_.tokenId) {
        address owner = ownerOf(params_.tokenId);

        // untrack positions
        _untrackPositions(
            owner,
            params_.pool,
            params_.tokenId,
            params_.indexes
        );

        // revoke itself as a position manager for the given indexes
        IPool(params_.pool).revokeLpManager(owner, params_.indexes);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @dev    Transfer LPs from old owner to new owner of the token on NFT transfer.
     *  @param  from_    Address of the lender (owner) that transfers the position NFT.
     *  @param  to_      Address of the lender (new owner) that receives the position NFT.
     *  @param  tokenId_ The id of position NFT that is transferred.
     */
    function _afterTokenTransfer(
        address from_,
        address to_,
        uint256 tokenId_
    ) internal override {
        if (from_ != address(0) && to_ != address(0)) {
            // if from or to are rewards manager we don't transfer the LPs as we're going to end up with rewards manager contract centralizing LPs for all staked positions
            if (!_isRewardsManager(from_) && !_isRewardsManager(to_)) {
                uint256[] memory trackedIndexes = positionIndexes[tokenId_].values();

                address pool = poolKey[tokenId_];

                // revoke itself as a position manager for the given indexes for the old owner
                _untrackPositions(from_, pool, tokenId_, trackedIndexes);

                // transfer LPs at tracked indexes to the new owner. Transfer LPs also revokes the lp manager
                IPool(pool).transferLPs(from_, to_, trackedIndexes);
            }
        }
    }

    /**
     *  @dev    Helper function to check if a given address supports RewardsManager interface.
     *  @param  address_ The address to check if RewardsManager contract.
     *  @return True if the address supports RewardsManager interface.
     */
    function _isRewardsManager(address address_) internal view returns (bool) {
        if (!Address.isContract(address_)) return false;

        try IERC165(address_).supportsInterface(0x03000336) returns (bool isSupported) {
            return isSupported;
        } catch {
            return false;
        }
    }

    /**
     *  @dev    Helper function for untracking positions by removing them from internal set and revoking contract as LP manager (external call to pool contract).
     *  @param  owner_   The owner of the position NFT.
     *  @param  pool_    The pool that position NFT tracks positions in.
     *  @param  tokenId_ The id of position NFT.
     *  @param  indexes_ The array of indexes to be untracked and revoked.
     */
    function _untrackPositions(
        address owner_,
        address pool_,
        uint256 tokenId_,
        uint256[] memory indexes_
    ) internal {
        EnumerableSet.UintSet storage positionIndex = positionIndexes[tokenId_];

        mapping(uint256 => bool) storage trackedPositions = lenderTrackedPoolPositions[owner_][pool_];

        uint256 indexesLength = indexes_.length;
        uint256 index;

        for (uint256 i = 0; i < indexesLength; ) {
            index = indexes_[i];

            // remove bucket index at which a position has added liquidity
            if (!positionIndex.remove(index)) revert UntrackPositionFailed();

            delete trackedPositions[index];

            unchecked { ++i; }
        }

        emit UntrackPositions(owner_, tokenId_, indexes_);
    }

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
    function getLPs(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (uint256 lpBalance_) {
        address lender  = ownerOf(tokenId_);
        address pool    = poolKey[tokenId_];
        (lpBalance_, ) = IPool(pool).lenderInfo(index_, lender);
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
