// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import { ERC20 }           from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { IERC20 }          from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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
    _lpToQuoteToken,
    _priceAt
}                      from './libraries/helpers/PoolHelper.sol';
import { tokenSymbol } from './libraries/helpers/SafeTokenNamer.sol';

import { PositionNFTSVG } from './libraries/external/PositionNFTSVG.sol';

/**
 *  @title  Position Manager Contract
 *  @notice Used by Pool lenders to optionally mint `NFT` that represents their positions.
 *          `Lenders` can:
 *          - `mint` positions `NFT` token for a specific pool
 *          - `memorialize` positions for given buckets
 *          - `move liquidity` in pool
 *          - `redeem` positions for given buckets
 *          - `burn` positions `NFT`
 */
contract PositionManager is PermitERC721, IPositionManager, Multicall, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20     for ERC20;

    /***********************/
    /*** State Variables ***/
    /***********************/

    /// @dev Mapping tracking information of position tokens minted.
    mapping(uint256 tokenId => TokenInfo) internal positionTokens;

    /// @dev Id of the next token that will be minted. Skips `0`.
    uint176 private _nextId = 1;

    /******************/
    /*** Immutables ***/
    /******************/

    /// @dev The `ERC20` pools factory contract, used to check if address is an `Ajna` pool.
    ERC20PoolFactory  private immutable erc20PoolFactory;
    /// @dev The `ERC721` pools factory contract, used to check if address is an `Ajna` pool.
    ERC721PoolFactory private immutable erc721PoolFactory;

    /*************************/
    /*** Local Var Structs ***/
    /*************************/

    /// @dev Struct used for `moveLiquidity` function local vars.
    struct MoveLiquidityLocalVars {
        uint256 bucketLP;         // [WAD] amount of LP in from bucket
        uint256 bucketCollateral; // [WAD] amount of collateral in from bucket
        uint256 bankruptcyTime;   // from bucket bankruptcy time
        uint256 bucketDeposit;    // [WAD] from bucket deposit
        uint256 fromDepositTime;  // lender deposit time in from bucket
        uint256 fromLP;           // [WAD] the LP memorialized in from position
        uint256 toDepositTime;    // lender deposit time in to bucket
        uint256 maxQuote;         // [WAD] max amount that can be moved from bucket
        uint256 lpbAmountFrom;    // [WAD] the LP redeemed from bucket
        uint256 lpbAmountTo;      // [WAD] the LP awarded in to bucket
    }

    /// @dev Struct used for `memorializePositions` function Lenders Local vars
    struct LendersBucketLocalVars {
        uint256 lpBalance;   // Lender lp balance in a bucket
        uint256 depositTime; // Lender deposit time in a bucket
        uint256 allowance;   // Lp allowance for a bucket
    }

    /*****************/
    /*** Modifiers ***/
    /*****************/

    /**
     *  @dev   Modifier used to check if sender can interact with token id.
     *  @param pool_    `Ajna` pool address.
     *  @param tokenId_ Id of positions `NFT`.
     */
    modifier mayInteract(address pool_, uint256 tokenId_) {

        // revert if token id is not a valid / minted id
        _requireMinted(tokenId_);

        // revert if sender is not owner of or entitled to operate on token id
        if (!_isApprovedOrOwner(msg.sender, tokenId_)) revert NoAuth();

        // revert if the token id is not minted for given pool address
        if (pool_ != positionTokens[tokenId_].pool) revert WrongPool();

        _;
    }

    /*******************/
    /*** Constructor ***/
    /*******************/

    constructor(
        ERC20PoolFactory erc20Factory_,
        ERC721PoolFactory erc721Factory_
    ) PermitERC721("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {
        if (
            address(erc20Factory_) == address(0) || address(erc721Factory_) == address(0)
        ) revert DeployWithZeroAddress();

        erc20PoolFactory  = erc20Factory_;
        erc721PoolFactory = erc721Factory_;
    }

    /********************************/
    /*** Owner External Functions ***/
    /********************************/

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev    === Write state ===
     *  @dev    `_nonces`: remove `tokenId` nonce
     *  @dev    `tokenInfo`: remove `tokenId => TokenInfo` mapping
     *  @dev    === Revert on ===
     *  @dev    - `mayInteract`:
     *  @dev       token id is not a valid / minted id
     *  @dev       sender is not owner `NoAuth()`
     *  @dev       token id not minted for given pool `WrongPool()`
     *  @dev    - positions token to burn has liquidity `LiquidityNotRemoved()`
     *  @dev    === Emit events ===
     *  @dev    - `Burn`
     */
    function burn(
        address pool_,
        uint256 tokenId_
    ) external override mayInteract(pool_, tokenId_) {
        // revert if trying to burn an positions token that still has liquidity
        if (positionTokens[tokenId_].positionIndexes.length() != 0) revert LiquidityNotRemoved();

        // remove permit nonces and pool mapping for burned token
        delete _nonces[tokenId_];
        delete positionTokens[tokenId_];

        _burn(tokenId_);

        emit Burn(msg.sender, tokenId_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev    External calls to `Pool` contract:
     *  @dev    - `lenderInfo()`: get lender position in bucket
     *  @dev    - `transferLP()`: transfer `LP` ownership to `PositionManager` contract
     *  @dev    === Write state ===
     *  @dev    `TokenInfo.positionIndexes`: add bucket index
     *  @dev    `TokenInfo.positions`: update `tokenId => bucket id` position
     *  @dev    === Revert on ===
     *  @dev    - `mayInteract`:
     *  @dev       token id is not a valid / minted id
     *  @dev       sender is not owner `NoAuth()`
     *  @dev       token id not minted for given pool `WrongPool()`
     *  @dev    - owner supplied insufficient allowance for the lp transfer `AllowanceTooLow()`
     *  @dev    === Emit events ===
     *  @dev    - `TransferLP`
     *  @dev    - `MemorializePosition`
     */
    function memorializePositions(
        address pool_,
        uint256 tokenId_,
        uint256[] calldata indexes_
    ) external mayInteract(pool_, tokenId_) override {
        TokenInfo storage tokenInfo = positionTokens[tokenId_];
        EnumerableSet.UintSet storage positionIndexes = tokenInfo.positionIndexes;

        IPool   pool  = IPool(pool_);
        address owner = ownerOf(tokenId_);

        LendersBucketLocalVars memory vars;

        // local vars used in for loop for reduced gas
        uint256 index;
        uint256 indexesLength = indexes_.length;

        // loop through all bucket indexes and memorialize lp balance and deposit time to the Position.
        for (uint256 i = 0; i < indexesLength; ) {
            index = indexes_[i];

            // record bucket index at which a position has added liquidity
            // slither-disable-next-line unused-return
            positionIndexes.add(index);

            (vars.lpBalance, vars.depositTime) = pool.lenderInfo(index, owner);

            // check that specified allowance is at least equal to the lp balance
            vars.allowance = pool.lpAllowance(index, address(this), owner);

            if (vars.allowance < vars.lpBalance) revert AllowanceTooLow();

            Position memory position = tokenInfo.positions[index];

            // check for previous deposits
            if (position.depositTime != 0) {
                // check that bucket didn't go bankrupt after prior memorialization
                if (_bucketBankruptAfterDeposit(pool, index, position.depositTime)) {
                    // if bucket did go bankrupt, zero out the LP tracked by position manager
                    position.lps = 0;
                }
            }

            // update token position LP
            position.lps += vars.lpBalance;
            // set token's position deposit time to the original lender's deposit time
            position.depositTime = vars.depositTime;

            // save position in storage
            tokenInfo.positions[index] = position;

            unchecked { ++i; }
        }

        // update pool LP accounting and transfer ownership of LP to PositionManager contract
        pool.transferLP(owner, address(this), indexes_);

        emit MemorializePosition(owner, tokenId_, indexes_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev    === Write state ===
     *  @dev    `tokenInfo`: update `tokenId => TokenInfo` mapping
     *  @dev    === Revert on ===
     *  @dev    provided pool not valid `NotAjnaPool()`
     *  @dev    === Emit events ===
     *  @dev    - `Mint`
     *  @dev    - `Transfer`
     */
    function mint(
        address pool_,
        address recipient_,
        bytes32 poolSubsetHash_
    ) external override nonReentrant returns (uint256 tokenId_) {
        // revert if the address is not a valid Ajna pool
        if (!_isAjnaPool(pool_, poolSubsetHash_)) revert NotAjnaPool();

        tokenId_ = _nextId++;

        // record which pool the tokenId was minted in
        positionTokens[tokenId_].pool = pool_;

        _mint(recipient_, tokenId_);

        emit Mint(recipient_, pool_, tokenId_);
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev    External calls to `Pool` contract:
     *  @dev    `bucketInfo()`: get from bucket info
     *  @dev    `moveQuoteToken()`: move liquidity between buckets
     *  @dev    === Write state ===
     *  @dev    `TokenInfo.positionIndexes`: remove from bucket index
     *  @dev    `TokenInfo.positionIndexes`: add to bucket index
     *  @dev    `TokenInfo.positions`: update from bucket position
     *  @dev    `TokenInfo.positions`: update to bucket position
     *  @dev    === Revert on ===
     *  @dev    - `mayInteract`:
     *  @dev      token id is not a valid / minted id
     *  @dev      sender is not owner `NoAuth()`
     *  @dev      token id not minted for given pool `WrongPool()`
     *  @dev    - positions token to burn has liquidity `RemovePositionFailed()`
     *  @dev    - tried to move from bankrupt bucket `BucketBankrupt()`
     *  @dev    === Emit events ===
     *  @dev    - `MoveQuoteToken`
     *  @dev    - `MoveLiquidity`
     */
    function moveLiquidity(
        address pool_,
        uint256 tokenId_,
        uint256 fromIndex_,
        uint256 toIndex_,
        uint256 expiry_,
        bool    revertIfBelowLup_
    ) external override nonReentrant mayInteract(pool_, tokenId_) {
        TokenInfo storage tokenInfo    = positionTokens[tokenId_];
        Position  storage fromPosition = tokenInfo.positions[fromIndex_];

        MoveLiquidityLocalVars memory vars;
        vars.fromDepositTime = fromPosition.depositTime;
        vars.fromLP = fromPosition.lps;

        // owner attempts to move liquidity from index without LP or they've already moved it
        if (vars.fromDepositTime == 0) revert RemovePositionFailed();

        // ensure bucketDeposit accounts for accrued interest
        IPool(pool_).updateInterest();

        // retrieve info of bucket from which liquidity is moved  
        (
            vars.bucketLP,
            vars.bucketCollateral,
            vars.bankruptcyTime,
            vars.bucketDeposit,
        ) = IPool(pool_).bucketInfo(fromIndex_);

        // check that from bucket hasn't gone bankrupt since memorialization
        if (vars.fromDepositTime <= vars.bankruptcyTime) revert BucketBankrupt();

        // calculate the max amount of quote tokens that can be moved, given the tracked LP
        vars.maxQuote = _lpToQuoteToken(
            vars.bucketLP,
            vars.bucketCollateral,
            vars.bucketDeposit,
            vars.fromLP,
            vars.bucketDeposit,
            _priceAt(fromIndex_)
        );

        // move quote tokens in pool
        (
            vars.lpbAmountFrom,
            vars.lpbAmountTo,
        ) = IPool(pool_).moveQuoteToken(
            vars.maxQuote,
            fromIndex_,
            toIndex_,
            expiry_,
            revertIfBelowLup_
        );

        EnumerableSet.UintSet storage positionIndexes = tokenInfo.positionIndexes;

        // 1. update FROM memorialized position
        if (!positionIndexes.remove(fromIndex_)) revert RemovePositionFailed(); // revert if FROM position is not in memorialized indexes
        if (vars.fromLP != vars.lpbAmountFrom) revert RemovePositionFailed(); // bucket has collateral and quote therefore LP is not redeemable for full quote token amount

        delete tokenInfo.positions[fromIndex_]; // remove memorialized FROM position

        // 2. update TO memorialized position
        // slither-disable-next-line unused-return
        positionIndexes.add(toIndex_); // record the TO memorialized position

        Position storage toPosition = tokenInfo.positions[toIndex_];
        vars.toDepositTime = toPosition.depositTime;

        // reset LP in TO memorialized position if bucket went bankrupt after memorialization
        if (_bucketBankruptAfterDeposit(IPool(pool_), toIndex_, vars.toDepositTime)) {
            toPosition.lps = vars.lpbAmountTo;
        } else {
            toPosition.lps += vars.lpbAmountTo;
        }

        // update TO memorialized position deposit time with the renewed to bucket deposit time
        (, vars.toDepositTime) = IPool(pool_).lenderInfo(toIndex_, address(this));
        toPosition.depositTime = vars.toDepositTime;

        emit MoveLiquidity(
            ownerOf(tokenId_),
            tokenId_,
            fromIndex_,
            toIndex_,
            vars.lpbAmountFrom,
            vars.lpbAmountTo
        );
    }

    /**
     *  @inheritdoc IPositionManagerOwnerActions
     *  @dev    External calls to `Pool` contract:
     *  @dev    `increaseLPAllowance()`: approve ownership for transfer
     *  @dev    `transferLP()`: transfer `LP` ownership from `PositionManager` contract
     *  @dev    === Write state ===
     *  @dev    `positionIndexes`: remove from bucket index
     *  @dev    `positions`: delete bucket position
     *  @dev    === Revert on ===
     *  @dev    - `mayInteract`:
     *  @dev      token id is not a valid / minted id
     *  @dev      sender is not owner `NoAuth()`
     *  @dev      token id not minted for given pool `WrongPool()`
     *  @dev    - position not tracked `RemovePositionFailed()`
     *  @dev    - tried to redeem bankrupt bucket `BucketBankrupt()`
     *  @dev    === Emit events ===
     *  @dev    - `TransferLP`
     *  @dev    - `RedeemPosition`
     */
    function redeemPositions(
        address pool_,
        uint256 tokenId_,
        uint256[] calldata indexes_
    ) external override mayInteract(pool_, tokenId_) {
        TokenInfo storage tokenInfo = positionTokens[tokenId_];

        IPool pool = IPool(pool_);

        // local vars used in for loop for reduced gas
        uint256 index;
        uint256 indexesLength = indexes_.length;
        uint256[] memory lpAmounts = new uint256[](indexesLength);

        // retrieve LP amounts from each bucket index associated with token id
        for (uint256 i = 0; i < indexesLength; ) {
            index = indexes_[i];

            Position memory position = tokenInfo.positions[index];

            if (position.lps == 0 || position.depositTime == 0) revert RemovePositionFailed();

            // check that bucket didn't go bankrupt after memorialization
            if (_bucketBankruptAfterDeposit(pool, index, position.depositTime)) revert BucketBankrupt();

            // remove bucket index at which a position has added liquidity
            if (!tokenInfo.positionIndexes.remove(index)) revert RemovePositionFailed();

            lpAmounts[i] = position.lps;

            // remove LP tracked by position manager at bucket index
            delete tokenInfo.positions[index];

            unchecked { ++i; }
        }

        address owner = ownerOf(tokenId_);

        // approve owner to take over the LP ownership (required for transferLP pool call)
        pool.increaseLPAllowance(owner, indexes_, lpAmounts);
        // update pool lps accounting and transfer ownership of lps from PositionManager contract
        pool.transferLP(address(this), owner, indexes_);

        emit RedeemPosition(owner, tokenId_, indexes_);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /**
     *  @notice Checks that a provided pool address was deployed by an `Ajna` factory.
     *  @param  pool_       Address of the `Ajna` pool.
     *  @param  subsetHash_ Factory's subset hash pool.
     *  @return `True` if a valid `Ajna` pool, `false` otherwise.
     */
    function _isAjnaPool(
        address pool_,
        bytes32 subsetHash_
    ) internal view returns (bool) {
        address collateralAddress = IPool(pool_).collateralAddress();
        address quoteAddress      = IPool(pool_).quoteTokenAddress();

        address erc20DeployedPoolAddress  = erc20PoolFactory.deployedPools(
            subsetHash_,
            collateralAddress,
            quoteAddress
        );
        address erc721DeployedPoolAddress = erc721PoolFactory.deployedPools(
            subsetHash_,
            collateralAddress,
            quoteAddress
        );

        return (pool_ == erc20DeployedPoolAddress || pool_ == erc721DeployedPoolAddress);
    }

    /**
     *  @notice Checks that a bucket index associated with a given `NFT` didn't go bankrupt after memorialization.
     *  @param  pool_        The address of the pool of memorialized position.
     *  @param  index_       The bucket index to check deposit time for.
     *  @param  depositTime_ The recorded deposit time of the position.
     *  @return isBankrupt_  `True` if the bucket went bankrupt after that position memorialzied their `LP`.
     */
    function _bucketBankruptAfterDeposit(
        IPool pool_,
        uint256 index_,
        uint256 depositTime_
    ) internal view returns (bool isBankrupt_) {
        (, , uint256 bankruptcyTime, , ) = pool_.bucketInfo(index_);
        // Only check against deposit time if bucket has gone bankrupt
        if (bankruptcyTime != 0) isBankrupt_ = depositTime_ <= bankruptcyTime;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @inheritdoc IPositionManagerDerivedState
    function getLP(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (uint256) {
        TokenInfo storage tokenInfo = positionTokens[tokenId_];
        Position memory position = tokenInfo.positions[index_];
        return _bucketBankruptAfterDeposit(IPool(tokenInfo.pool), index_, position.depositTime) ? 0 : position.lps;
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionIndexes(
        uint256 tokenId_
    ) external view override returns (uint256[] memory) {
        return positionTokens[tokenId_].positionIndexes.values();
    }

    /// @inheritdoc IPositionManagerDerivedState
    function getPositionIndexesFiltered(
        uint256 tokenId_
    ) external view override returns (uint256[] memory filteredIndexes_) {
        TokenInfo storage tokenInfo = positionTokens[tokenId_];
        uint256[] memory indexes = tokenInfo.positionIndexes.values();
        uint256 indexesLength = indexes.length;

        // filter out bankrupt buckets
        filteredIndexes_ = new uint256[](indexesLength);
        uint256 filteredIndexesLength = 0;
        IPool pool = IPool(tokenInfo.pool);
        for (uint256 i = 0; i < indexesLength; ) {
            if (!_bucketBankruptAfterDeposit(pool, indexes[i], tokenInfo.positions[indexes[i]].depositTime)) {
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
        Position memory position = positionTokens[tokenId_].positions[index_];
        return (
            position.lps,
            position.depositTime
        );
    }

    /// @inheritdoc IPositionManagerDerivedState
    function poolKey(uint256 tokenId_) external view override returns (address) {
        return positionTokens[tokenId_].pool;
    }

    /// @inheritdoc IPositionManagerDerivedState
    function isAjnaPool(
        address pool_,
        bytes32 subsetHash_
    ) external override view returns (bool) {
        return _isAjnaPool(pool_, subsetHash_);
    }

    /// @inheritdoc IPositionManagerDerivedState
    function isPositionBucketBankrupt(
        uint256 tokenId_,
        uint256 index_
    ) external view override returns (bool) {
        TokenInfo storage tokenInfo = positionTokens[tokenId_];
        return _bucketBankruptAfterDeposit(IPool(tokenInfo.pool), index_, tokenInfo.positions[index_].depositTime);
    }

    /// @inheritdoc IPositionManagerDerivedState
    function isIndexInPosition(
        uint256 tokenId_,
        uint256 index_
    ) external override view returns (bool) {
        return positionTokens[tokenId_].positionIndexes.contains(index_);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId_
    ) public view override returns (string memory) {
        if (!_exists(tokenId_)) revert NoToken();

        TokenInfo storage tokenInfo = positionTokens[tokenId_];
        address pool = tokenInfo.pool;

        address collateralTokenAddress = IPool(pool).collateralAddress();
        address quoteTokenAddress      = IPool(pool).quoteTokenAddress();

        PositionNFTSVG.ConstructTokenURIParams memory params = PositionNFTSVG.ConstructTokenURIParams({
            collateralTokenSymbol: tokenSymbol(collateralTokenAddress),
            quoteTokenSymbol:      tokenSymbol(quoteTokenAddress),
            tokenId:               tokenId_,
            pool:                  pool,
            owner:                 ownerOf(tokenId_),
            indexes:               tokenInfo.positionIndexes.values()
        });

        return PositionNFTSVG.constructTokenURI(params);
    }

}
