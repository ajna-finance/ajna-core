// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { Clone } from "@clones/Clone.sol";

import { console } from "@hardhat/hardhat-core/console.sol"; // TESTING ONLY

import { ERC20 }     from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 }    from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { BitMaps }   from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import { Interest } from "./base/Interest.sol";

import { IPool } from "./interfaces/IPool.sol";

import { Buckets }    from "./libraries/Buckets.sol";
import { BucketMath } from "./libraries/BucketMath.sol";
import { Maths }      from "./libraries/Maths.sol";


contract ERC721Pool is IPool, Clone, Interest {

    using Buckets for mapping(uint256 => Buckets.Bucket);

    // price (WAD) -> bucket
    mapping(uint256 => Buckets.Bucket) private _buckets;

    BitMaps.BitMap private _bitmap;

    uint256 public quoteTokenScale;

    uint256 public hpb; // WAD
    uint256 public lup; // WAD

    uint256 public previousRateUpdate;
    uint256 public totalCollateral;    // WAD
    uint256 public totalQuoteToken;    // WAD

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    // lenders lp token balances: lender address -> price bucket (WAD) -> lender lp (RAY)
    mapping(address => mapping(uint256 => uint256)) public lpBalance;

    /// @dev Counter used by onlyOnce modifier
    uint8 private _poolInitializations = 0;

    /// @notice Modifier to protect a clone's initialize method from repeated updates
    modifier onlyOnce() {
        if (_poolInitializations != 0) {
            revert AlreadyInitialized();
        }
        _;
    }

    function initialize() external onlyOnce {
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot           = Maths.ONE_RAY;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate               = Maths.wdiv(5, 100);
        previousRateUpdate         = block.timestamp;

        // increment initializations count to ensure these values can't be updated
        _poolInitializations += 1;
    }

    /// @dev Quote tokens are always non-fungible
    /// @dev Pure function used to facilitate accessing token via clone state
    function collateral() public pure returns (ERC721) {
        return ERC721(_getArgAddress(0));
    }

    /// @dev Quote tokens are always fungible
    /// @dev Pure function used to facilitate accessing token via clone state
    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    /// @inheritdoc IPool
    function addQuoteToken(address recipient_, uint256 amount_, uint256 price_) external returns (uint256 lpTokens_) {

    }

    /// @inheritdoc IPool
    function removeQuoteToken(address recipient_, uint256 maxAmount_, uint256 price_) external {

    }

    /// @inheritdoc IPool
    function addCollateral(uint256 amount_) external {
        // accumulatePoolInterest();

        // borrowers[msg.sender].collateralDeposited += amount_;
        // totalCollateral                           += amount_;

        // // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        // collateral().safeTransferFrom(msg.sender, address(this), amount_);
        // emit AddCollateral(msg.sender, amount_);
    }

    function removeCollateral(uint256 amount_) external {}

    function claimCollateral(address recipient_, uint256 amount_, uint256 price_) external {}

    function borrow(uint256 amount_, uint256 stopPrice_) external {}

    function repay(uint256 amount_) external {}

    function purchaseBid(uint256 amount_, uint256 price_) external {}

    function getLPTokenBalance(address owner_, uint256 price_) external view returns (uint256 lpTokens_) {

    }

    function getLPTokenExchangeValue(uint256 lpTokens_, uint256 price_) external view returns (uint256 collateralTokens_, uint256 quoteTokens_) {

    }

    function liquidate(address borrower_) external {}


    /*************************/
    /*** Bucket Management ***/
    /*************************/

    /// @notice Get a bucket struct for a given price
    /// @param price_ The price of the bucket to retrieve
    function bucketAt(uint256 price_)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 onDeposit,
            uint256 debt,
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        )
    {
        return _buckets.bucketAt(price_);
    }

}