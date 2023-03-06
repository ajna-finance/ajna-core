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
import { Position }                     from './interfaces/position/IPositionManagerState.sol';

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

    mapping(uint256 => address) public override poolKey;     // token id => ajna pool address for which token was minted

    mapping(uint256 => mapping(uint256 => Position)) internal positions; // token id => bucket index => Position struct
    mapping(uint256 => uint96)                       internal nonces;          // token id => nonce value used for permit
    mapping(uint256 => EnumerableSet.UintSet)        internal positionIndexes; // token id => bucket indexes associated with position

    uint176 private _nextId = 1; // id of the next token that will be minted. Skips 0

    /******************/
    /*** Immutables ***/
    /******************/

    ERC20PoolFactory  private immutable erc20PoolFactory;  // The ERC20 pools factory contract, used to check if address is an Ajna pool
    ERC721PoolFactory private immutable erc721PoolFactory; // The ERC721 pools factory contract, used to check if address is an Ajna pool

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    struct MoveLiquidityLocalVars {
        uint256 bucketLPs;        // [WAD] amount of LPs in from bucket
        uint256 bucketCollateral; // [WAD] amount of collateral in from bucket
        uint256 bankruptcyTime;   // from bucket bankruptcy time
        uint256 bucketDeposit;    // [WAD] from bucket deposit
        uint256 depositTime;      // lender deposit time in from bucekt
        uint256 maxQuote;         // [WAD] max amount that can be moved from bucket
        uint256 lpbAmountFrom;    // [WAD] the LPs redeemed from bucket
        uint256 lpbAmountTo;      // [WAD] the LPs awarded in to bucket
    }

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

        _burn(params_.tokenId);

        emit Burn(msg.sender, params_.tokenId);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - lenderInfo(): get lender position in bucket
     *          - transferLPs(): transfer LPs ownership to PositionManager contracts
     *  @dev write state:
     *          - positionIndexes: add bucket index
     *          - positions: update tokenId => bucket id position
     *  @dev revert on:
     *          - positions token to burn has liquidity LiquidityNotRemoved()
     *  @dev emit events:
     *          - MemorializePosition
     */
    function memorializePositions(
        MemorializePositionsParams calldata params_
    ) external override {
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        IPool   pool  = IPool(poolKey[params_.tokenId]);
        address owner = ownerOf(params_.tokenId);

        uint256 indexesLength = params_.indexes.length;
        uint256 index;

        for (uint256 i = 0; i < indexesLength; ) {
            index = params_.indexes[i];

            // record bucket index at which a position has added liquidity
            // slither-disable-next-line unused-return
            positionIndex.add(index);

            (uint256 lpBalance, uint256 depositTime) = pool.lenderInfo(index, owner);

            Position memory position = positions[params_.tokenId][index];

            // check for previous deposits
            if (position.depositTime != 0) {
                // check that bucket didn't go bankrupt after prior memorialization
                if (_bucketBankruptAfterDeposit(pool, index, position.depositTime)) {
                    // if bucket did go bankrupt, zero out the LPs tracked by position manager
                    position.lps = 0;
                }
            }

            // update token position LPs
            position.lps += lpBalance;
            // set token's position deposit time to the original lender's deposit time
            position.depositTime = depositTime;

            // save position in storage
            positions[params_.tokenId][index] = position;

            unchecked { ++i; }
        }

        // update pool lps accounting and transfer ownership of lps to PositionManager contract
        pool.transferLPs(owner, address(this), params_.indexes);

        emit MemorializePosition(owner, params_.tokenId, params_.indexes);
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

        _mint(params_.recipient, tokenId_);

        emit Mint(params_.recipient, params_.pool, tokenId_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - bucketInfo(): get from bucket info
     *          - moveQuoteToken(): move liquidity between buckets
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *          - positionIndexes: add to bucket index
     *          - positions: update from bucket position
     *          - positions: update to bucket position
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
        Position storage fromPosition = positions[params_.tokenId][params_.fromIndex];

        MoveLiquidityLocalVars memory vars;
        vars.depositTime = fromPosition.depositTime;

        // handle the case where owner attempts to move liquidity after they've already done so
        if (vars.depositTime == 0) revert RemovePositionFailed();

        // retrieve info of bucket from which liquidity is moved  
        (
            vars.bucketLPs,
            vars.bucketCollateral,
            vars.bankruptcyTime,
            vars.bucketDeposit,
        ) = IPool(params_.pool).bucketInfo(params_.fromIndex);

        // check that bucket hasn't gone bankrupt since memorialization
        if (vars.depositTime <= vars.bankruptcyTime) revert BucketBankrupt();

        // calculate the max amount of quote tokens that can be moved, given the tracked LPs
        vars.maxQuote = _lpsToQuoteToken(
            vars.bucketLPs,
            vars.bucketCollateral,
            vars.bucketDeposit,
            fromPosition.lps,
            vars.bucketDeposit,
            _priceAt(params_.fromIndex)
        );

        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        // remove bucket index from which liquidity is moved from tracked positions
        if (!positionIndex.remove(params_.fromIndex)) revert RemovePositionFailed();

        // update bucket set at which a position has liquidity
        // slither-disable-next-line unused-return
        positionIndex.add(params_.toIndex);

        // move quote tokens in pool
        (
            vars.lpbAmountFrom,
            vars.lpbAmountTo,
        ) = IPool(params_.pool).moveQuoteToken(
            vars.maxQuote,
            params_.fromIndex,
            params_.toIndex,
            params_.expiry
        );

        Position storage toPosition = positions[params_.tokenId][params_.toIndex];

        // update position LPs state
        fromPosition.lps -= vars.lpbAmountFrom;
        toPosition.lps   += vars.lpbAmountTo;
        // update position deposit time to the from bucket deposit time
        toPosition.depositTime = vars.depositTime;

        emit MoveLiquidity(
            ownerOf(params_.tokenId),
            params_.tokenId,
            params_.fromIndex,
            params_.toIndex
        );
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev External calls to Pool contract:
     *          - increaseLPAllowance(): approve ownership for transfer
     *          - transferLPs(): transfer LPs ownership from PositionManager contract
     *  @dev write state:
     *          - positionIndexes: remove from bucket index
     *          - positions: delete bucket position
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

        IPool pool = IPool(params_.pool);

        uint256 indexesLength = params_.indexes.length;
        uint256[] memory lpAmounts = new uint256[](indexesLength);

        uint256 index;

        for (uint256 i = 0; i < indexesLength; ) {
            index = params_.indexes[i];

            Position memory position = positions[params_.tokenId][index];

            if (position.depositTime == 0 || position.lps == 0) revert RemovePositionFailed();

            // check that bucket didn't go bankrupt after memorialization
            if (_bucketBankruptAfterDeposit(pool, index, position.depositTime)) revert BucketBankrupt();

            // remove bucket index at which a position has added liquidity
            if (!positionIndex.remove(index)) revert RemovePositionFailed();

            lpAmounts[i] = position.lps;

            // remove LPs tracked by position manager at bucket index
            delete positions[params_.tokenId][index];

            unchecked { ++i; }
        }

        address owner = ownerOf(params_.tokenId);

        // approve owner to take over the LPs ownership (required for transferLPs pool call)
        pool.increaseLPAllowance(owner, params_.indexes, lpAmounts);
        // update pool lps accounting and transfer ownership of lps from PositionManager contract
        pool.transferLPs(address(this), owner, params_.indexes);

        emit RedeemPosition(owner, params_.tokenId, params_.indexes);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Retrieves token's next nonce for permit.
     *  @param  tokenId_ Address of the Ajna pool to retrieve accumulators of.
     *  @return Incremented token permit nonce.
     */
    function _getAndIncrementNonce(
        uint256 tokenId_
    ) internal override returns (uint256) {
        return uint256(nonces[tokenId_]++);
    }

    /**
     *  @notice Checks that a provided pool address was deployed by an Ajna factory.
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

    /**
     *  @notice Checks that a bucket index associated with a given NFT didn't go bankrupt after memorialization.
     *  @param  pool_        The address of the pool of memorialized position.
     *  @param  index_       The bucket index to check deposit time for.
     *  @param  depositTime_ The recorded deposit time of the position.
     *  @return True if the bucket went bankrupt after that position memorialzied their lpb.
     */
    function _bucketBankruptAfterDeposit(
        IPool pool_,
        uint256 index_,
        uint256 depositTime_
    ) internal view returns (bool) {
        (, , uint256 bankruptcyTime, , ) = pool_.bucketInfo(index_);
        return depositTime_ <= bankruptcyTime;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @inheritdoc IPositionManagerDerivedState
    function getLPs(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (uint256) {
        Position memory position = positions[tokenId_][index_];
        return _bucketBankruptAfterDeposit(IPool(poolKey[tokenId_]), index_, position.depositTime) ? 0 : position.lps;
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionIndexes(
        uint256 tokenId_
    ) external view override returns (uint256[] memory) {
        return positionIndexes[tokenId_].values();
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionIndexesFiltered(
        uint256 tokenId_
    ) external view override returns (uint256[] memory filteredIndexes_) {
        uint256[] memory indexes = positionIndexes[tokenId_].values();
        uint256 indexesLength = indexes.length;

        // filter out bankrupt buckets
        filteredIndexes_ = new uint256[](indexesLength);
        uint256 filteredIndexesLength = 0;
        IPool pool = IPool(poolKey[tokenId_]);
        for (uint256 i = 0; i < indexesLength; ) {
            if (!_bucketBankruptAfterDeposit(pool, indexes[i], positions[tokenId_][indexes[i]].depositTime)) {
                filteredIndexes_[filteredIndexesLength++] = indexes[i];
            }
            unchecked { ++i; }
        }

        // resize array
        assembly { mstore(filteredIndexes_, filteredIndexesLength) }
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionInfo(
        uint256 tokenId_,
        uint256 index_
    ) external view override returns (uint256, uint256) {
        return (
            positions[tokenId_][index_].lps,
            positions[tokenId_][index_].depositTime
        );
    }

    /// @inheritdoc IPositionManagerDerivedState
    function isPositionBucketBankrupt(
        uint256 tokenId_,
        uint256 index_
    ) external view override returns (bool) {
        return _bucketBankruptAfterDeposit(IPool(poolKey[tokenId_]), index_, positions[tokenId_][index_].depositTime);
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
