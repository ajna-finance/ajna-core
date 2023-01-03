// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/Multicall.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

import './interfaces/IPool.sol';
import './interfaces/IPositionManager.sol';

import '../erc20/interfaces/IERC20Pool.sol';
import '../erc721/interfaces/IERC721Pool.sol';

import '../erc20/ERC20PoolFactory.sol';
import '../erc721/ERC721PoolFactory.sol';

import './PermitERC721.sol';
import './PoolHelper.sol';

import '../libraries/Buckets.sol';
import '../libraries/Maths.sol';
import '../libraries/external/PositionNFTSVG.sol';

import { tokenSymbol } from '../libraries/SafeTokenNamer.sol';

contract PositionManager is ERC721, PermitERC721, IPositionManager, Multicall, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for ERC20;

    ERC20PoolFactory private immutable erc20PoolFactory;
    ERC721PoolFactory private immutable erc721PoolFactory;

    constructor(ERC20PoolFactory erc20Factory_, ERC721PoolFactory erc721Factory_) PermitERC721("Ajna Positions NFT-V1", "AJNA-V1-POS", "1") {
        erc20PoolFactory = erc20Factory_;
        erc721PoolFactory = erc721Factory_;
    }

    /***********************/
    /*** State Variables ***/
    /***********************/

    /** @dev Mapping of tokenIds to Pool address */
    mapping(uint256 => address) public poolKey;

    /** @dev Mapping of tokenIds to nonce values used for permit */
    mapping(uint256 => uint96) public nonces;

    /** @dev Mapping of tokenIds => bucket index => lpb */
    mapping(uint256 => mapping(uint256 => uint256)) public lps;

    /** @dev Mapping of tokenIds to set of price indexes associated with a Position */
    mapping(uint256 => EnumerableSet.UintSet) internal positionIndexes;

    /** @dev The ID of the next token that will be minted. Skips 0 */
    uint176 private _nextId = 1;

    /*****************/
    /*** Modifiers ***/
    /*****************/

    modifier mayInteract(address pool_, uint256 tokenId_) {
        _requireMinted(tokenId_);
        if (!_isApprovedOrOwner(msg.sender, tokenId_)) revert NoAuth();
        if (pool_ != poolKey[tokenId_]) revert WrongPool();
        _;
    }

    /************************/
    /*** Lender Functions ***/
    /************************/

    function burn(BurnParams calldata params_) external override payable mayInteract(params_.pool, params_.tokenId) {
        if (positionIndexes[params_.tokenId].length() != 0) revert LiquidityNotRemoved();

        delete nonces[params_.tokenId];
        delete poolKey[params_.tokenId];

        emit Burn(msg.sender, params_.tokenId);
        _burn(params_.tokenId);
    }

    function memorializePositions(MemorializePositionsParams calldata params_) external override {
        address owner = ownerOf(params_.tokenId);
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        IPool pool = IPool(poolKey[params_.tokenId]);
        uint256 indexesLength = params_.indexes.length;

        for (uint256 i = 0; i < indexesLength; ) {
            // record price at which a position has added liquidity
            // slither-disable-next-line unused-return
            positionIndex.add(params_.indexes[i]);

            // update PositionManager accounting
            (uint256 lpBalance,) = pool.lenderInfo(params_.indexes[i], owner);
            lps[params_.tokenId][params_.indexes[i]] += lpBalance;

            // increment call counter in gas efficient way by skipping safemath checks
            unchecked { ++i; }
        }

        // update pool lp token accounting and transfer ownership of lp tokens to PositionManager contract
        emit MemorializePosition(owner, params_.tokenId);
        pool.transferLPTokens(owner, address(this), params_.indexes);
    }

    function mint(MintParams calldata params_) external override returns (uint256 tokenId_) {
        tokenId_ = _nextId++;

        // check that the params_.pool is a valid Ajna pool
        if (!_isAjnaPool(params_.pool, params_.poolSubsetHash)) revert NotAjnaPool();

        // record which pool the tokenId was minted in
        poolKey[tokenId_] = params_.pool;

        emit Mint(params_.recipient, params_.pool, tokenId_);
        _safeMint(params_.recipient, tokenId_);
    }

    function moveLiquidity(MoveLiquidityParams calldata params_) external override mayInteract(params_.pool, params_.tokenId) nonReentrant {
        address owner = ownerOf(params_.tokenId);

        (uint256 bucketLPs, uint256 bucketCollateral, , uint256 bucketDeposit, ) = IPool(params_.pool).bucketInfo(params_.fromIndex);
        uint256 maxQuote = _lpsToQuoteToken(
            bucketLPs,
            bucketCollateral,
            bucketDeposit,
            lps[params_.tokenId][params_.fromIndex],
            bucketDeposit,
            _priceAt(params_.fromIndex)
        );

        // update prices set at which a position has liquidity
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];
        if (!positionIndex.remove(params_.fromIndex)) revert RemoveLiquidityFailed();
        // slither-disable-next-line unused-return
        positionIndex.add(params_.toIndex);

        // move quote tokens in pool
        emit MoveLiquidity(owner, params_.tokenId);
        (uint256 lpbAmountFrom, uint256 lpbAmountTo) = IPool(params_.pool).moveQuoteToken(maxQuote, params_.fromIndex, params_.toIndex);

        // update tracked LPs
        lps[params_.tokenId][params_.fromIndex] -= lpbAmountFrom;
        lps[params_.tokenId][params_.toIndex]   += lpbAmountTo;
    }

    function reedemPositions(RedeemPositionsParams calldata params_) external override mayInteract(params_.pool, params_.tokenId) {
        address owner = ownerOf(params_.tokenId);
        EnumerableSet.UintSet storage positionIndex = positionIndexes[params_.tokenId];

        IPool pool = IPool(poolKey[params_.tokenId]);
        uint256 indexesLength = params_.indexes.length;

        for (uint256 i = 0; i < indexesLength; ) {
            // remove price index at which a position has added liquidity
            if (!positionIndex.remove(params_.indexes[i])) revert RemoveLiquidityFailed();

            // update PositionManager accounting
            uint256 lpAmount = lps[params_.tokenId][params_.indexes[i]];
            delete lps[params_.tokenId][params_.indexes[i]];

            pool.approveLpOwnership(owner, params_.indexes[i], lpAmount);

            // increment call counter in gas efficient way by skipping safemath checks
            unchecked { ++i; }
        }

        // update pool lp token accounting and transfer ownership of lp tokens from PositionManager contract
        emit RedeemPosition(owner, params_.tokenId);
        pool.transferLPTokens(address(this), owner, params_.indexes);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /** @dev Used for tracking nonce input to permit function */
    function _getAndIncrementNonce(uint256 tokenId_) internal override returns (uint256) {
        return uint256(nonces[tokenId_]++);
    }

    /** @dev Used for checking that a provided pool address was deployed by an Ajna factory */
    function _isAjnaPool(address pool_, bytes32 subsetHash_) internal view returns (bool) {
        address collateralAddress = IPool(pool_).collateralAddress();
        address quoteAddress = IPool(pool_).quoteTokenAddress();

        address erc20DeployedPoolAddress = erc20PoolFactory.deployedPools(subsetHash_, collateralAddress, quoteAddress);
        address erc721DeployedPoolAddress = erc721PoolFactory.deployedPools(subsetHash_, collateralAddress, quoteAddress);

        if (pool_ == erc20DeployedPoolAddress || pool_ == erc721DeployedPoolAddress) return true;
        return false;
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    function getLPTokens(uint256 tokenId_, uint256 index_) external override view returns (uint256) {
        return lps[tokenId_][index_];
    }

    function getPositionIndexes(uint256 tokenId_) external view override returns (uint256[] memory) {
        return positionIndexes[tokenId_].values();
    }

    function isIndexInPosition(uint256 tokenId_, uint256 index_) external override view returns (bool) {
        return positionIndexes[tokenId_].contains(index_);
    }

    function tokenURI(uint256 tokenId_) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId_));

        address collateralTokenAddress = IPool(poolKey[tokenId_]).collateralAddress();
        address quoteTokenAddress      = IPool(poolKey[tokenId_]).quoteTokenAddress();

        PositionNFTSVG.ConstructTokenURIParams memory params = PositionNFTSVG.ConstructTokenURIParams({
            collateralTokenSymbol: tokenSymbol(collateralTokenAddress),
            quoteTokenSymbol: tokenSymbol(quoteTokenAddress),
            tokenId: tokenId_,
            pool: poolKey[tokenId_],
            owner: ownerOf(tokenId_),
            indexes: positionIndexes[tokenId_].values()
        });

        return PositionNFTSVG.constructTokenURI(params);
    }

}
