// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PRBMathUD60x18} from "@prb-math/contracts/PRBMathUD60x18.sol";
import {IPriceBuckets, PriceBuckets} from "./PriceBuckets.sol";

import "./libraries/Maths.sol";
import "./libraries/BucketMath.sol";

interface IPool {
    function addQuoteToken(uint256 _amount, uint256 _price) external;

    function removeQuoteToken(uint256 _amount, uint256 _price) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function claimCollateral(uint256 _amount, uint256 _price) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function repay(uint256 _amount) external;

    function purchaseBid(uint256 _amount, uint256 _price) external;
}

contract ERC20Pool is IPool {
    using SafeERC20 for IERC20;

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot; // last updated inflator rate for a given borrower
    }

    // TODO: add returns to position modifiers to enable usage by a proxy layer
    struct LenderInfo {
        uint256 amount;
        uint256 lpTokens;
    }

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;

    IERC20 public immutable collateral;
    IERC20 public immutable quoteToken;

    uint256 public hdp;
    uint256 public lup;

    IPriceBuckets private immutable _buckets;

    // lenders lp token balances: lender address -> price bucket -> lender lp
    mapping(address => mapping(uint256 => uint256)) public lpBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public inflatorSnapshot = Maths.ONE_WAD;
    uint256 public lastInflatorSnapshotUpdate = block.timestamp;
    uint256 public previousRate = Maths.wdiv(5, 100);
    uint256 public previousRateUpdate = block.timestamp;

    uint256 public totalCollateral;

    uint256 public totalQuoteToken;
    uint256 public totalDebt;

    event AddQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event RemoveQuoteToken(
        address indexed lender,
        uint256 indexed price,
        uint256 amount,
        uint256 lup
    );
    event AddCollateral(address indexed borrower, uint256 amount);
    event RemoveCollateral(address indexed borrower, uint256 amount);
    event ClaimCollateral(
        address indexed claimer,
        uint256 indexed price,
        uint256 amount,
        uint256 lps
    );
    event Borrow(address indexed borrower, uint256 lup, uint256 amount);
    event Repay(address indexed borrower, uint256 lup, uint256 amount);
    event UpdateInterestRate(uint256 oldRate, uint256 newRate);
    event Purchase(
        address indexed bidder,
        uint256 indexed price,
        uint256 amount,
        uint256 collateral
    );

    constructor(IERC20 _collateral, IERC20 _quoteToken) {
        collateral = _collateral;
        quoteToken = _quoteToken;

        _buckets = new PriceBuckets();
    }

    /// @notice Called by lenders to add an amount of credit at a specified price bucket
    /// @param _amount The amount of quote token to be added by a lender
    /// @param _price The bucket to which the quote tokens will be added
    function addQuoteToken(uint256 _amount, uint256 _price) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        accumulatePoolInterest();

        // create bucket if doesn't exist
        hdp = _buckets.ensureBucket(hdp, _price);

        // deposit amount
        uint256 lpTokens;
        uint256 newLup;
        bool reallocate = (totalDebt != 0 && _price >= lup);
        (newLup, lpTokens) = _buckets.addQuoteToken(
            _price,
            _amount,
            lup,
            inflatorSnapshot,
            reallocate
        );

        if (reallocate) {
            lup = newLup;
        }

        // update lender lp balance for current price bucket
        lpBalance[msg.sender][_price] += lpTokens;

        // update quote token accumulator
        totalQuoteToken += _amount;

        quoteToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddQuoteToken(msg.sender, _price, _amount, lup);
    }

    /// @notice Called by lenders to remove an amount of credit at a specified price bucket
    /// @param _amount The amount of quote token to be removed by a lender
    /// @param _price The bucket from which quote tokens will be removed
    function removeQuoteToken(uint256 _amount, uint256 _price) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        require(
            totalQuoteToken - totalDebt >= _amount,
            "ajna/amount-greater-than-claimable"
        );

        accumulatePoolInterest();

        // remove from bucket
        uint256 lpTokens;
        uint256 newLup;
        (newLup, lpTokens) = _buckets.removeQuoteToken(
            _price,
            _amount,
            lpBalance[msg.sender][_price],
            inflatorSnapshot
        );

        // move lup down only if removal happened at lup and new lup different than current
        if (_price == lup && newLup < lup) {
            lup = newLup;
        }

        totalQuoteToken -= _amount;
        require(
            getPoolCollateralization() >= Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        lpBalance[msg.sender][_price] -= lpTokens;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit RemoveQuoteToken(msg.sender, _price, _amount, lup);
    }

    function addCollateral(uint256 _amount) external {
        accumulatePoolInterest();
        borrowers[msg.sender].collateralDeposited += _amount;
        totalCollateral += _amount;

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        collateral.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddCollateral(msg.sender, _amount);
    }

    /// @notice Called by borrowers to remove an amount of collateral
    /// @param _amount The amount of collateral in deposit tokens to be removed from a position
    function removeCollateral(uint256 _amount) external {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        uint256 encumberedBorrowerCollateral;
        if (borrower.debt != 0) {
            encumberedBorrowerCollateral = Maths.wdiv(borrower.debt, lup);
        }

        require(
            borrower.collateralDeposited - encumberedBorrowerCollateral >=
                _amount,
            "ajna/not-enough-collateral"
        );

        borrower.collateralDeposited -= _amount;
        totalCollateral -= _amount;

        collateral.safeTransfer(msg.sender, _amount);
        emit RemoveCollateral(msg.sender, _amount);
    }

    /// @notice Called by lenders to claim unencumbered collateral from a price bucket
    /// @param _amount The amount of unencumbered collateral to claim
    /// @param _price The bucket from which unencumbered collateral will be claimed
    function claimCollateral(uint256 _amount, uint256 _price) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        uint256 maxClaim = lpBalance[msg.sender][_price];
        require(maxClaim != 0, "ajna/no-claim-to-bucket");

        uint256 claimedLpTokens = _buckets.claimCollateral(
            _price,
            _amount,
            maxClaim
        );

        lpBalance[msg.sender][_price] -= claimedLpTokens;

        collateral.safeTransfer(msg.sender, _amount);
        emit ClaimCollateral(msg.sender, _price, _amount, claimedLpTokens);
    }

    /// @notice Called by a borrower to open or expand a position
    /// @param _amount The amount of quote token to borrow
    /// @param _stopPrice Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position
    function borrow(uint256 _amount, uint256 _stopPrice) external {
        require(
            _amount <= totalQuoteToken - totalDebt,
            "ajna/not-enough-liquidity"
        );

        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[msg.sender];
        accumulateBorrowerInterest(borrower);

        // if first loan then borrow at hdp
        uint256 curLup = lup;
        if (curLup == 0) {
            curLup = hdp;
        }

        // TODO: make value explicit for use in comparison operator against collateralDeposited below
        uint256 encumberedBorrowerCollateral;
        if (borrower.debt != 0) {
            encumberedBorrowerCollateral = Maths.wdiv(borrower.debt, lup);
        }
        require(
            borrower.collateralDeposited > encumberedBorrowerCollateral,
            "ajna/not-enough-collateral"
        );

        uint256 loanCost;
        (lup, loanCost) = _buckets.borrow(
            _amount,
            _stopPrice,
            curLup,
            inflatorSnapshot
        );

        require(
            borrower.collateralDeposited >
                Maths.wdiv(borrower.debt + _amount, lup) &&
                borrower.collateralDeposited - Maths.wdiv(borrower.debt, lup) >
                loanCost,
            "ajna/not-enough-collateral"
        );
        borrower.debt += _amount;

        totalDebt += _amount;
        require(
            getPoolCollateralization() >= Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        quoteToken.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, lup, _amount);
    }

    /// @notice Called by a borrower to repay some amount of their borrowed quote tokens
    /// @param _amount The amount of quote token to repay
    function repay(uint256 _amount) external {
        uint256 availableAmount = quoteToken.balanceOf(msg.sender);
        require(availableAmount >= _amount, "ajna/no-funds-to-repay");

        BorrowerInfo storage borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "ajna/no-debt-to-repay");
        accumulatePoolInterest();
        accumulateBorrowerInterest(borrower);

        uint256 debtToPay;
        (lup, debtToPay) = _buckets.repay(_amount, lup, inflatorSnapshot);

        if (debtToPay < borrower.debt && _amount >= borrower.debt) {
            debtToPay = borrower.debt;
        }

        if (debtToPay >= borrower.debt) {
            borrower.debt = 0;
            borrower.inflatorSnapshot = 0;
        } else {
            borrower.debt -= debtToPay;
        }

        totalDebt -= Maths.min(totalDebt, debtToPay);

        quoteToken.safeTransferFrom(msg.sender, address(this), debtToPay);
        emit Repay(msg.sender, lup, debtToPay);
    }

    /// @notice Exchanges collateral for quote token
    /// @param _amount The amount of quote token to purchase
    /// @param _price The purchasing price of quote token
    function purchaseBid(uint256 _amount, uint256 _price) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        uint256 collateralRequired = Maths.wdiv(_amount, _price);
        require(
            collateral.balanceOf(msg.sender) >= collateralRequired,
            "ajna/not-enough-collateral-balance"
        );

        accumulatePoolInterest();

        require(
            _amount <= totalQuoteToken - totalDebt,
            "ajna/not-enough-liquidity"
        );

        uint256 newLup = _buckets.purchaseBid(
            _price,
            _amount,
            collateralRequired,
            inflatorSnapshot
        );

        // move lup down only if removal happened at lup or higher and new lup different than current
        if (_price >= lup && newLup < lup) {
            lup = newLup;
        }

        totalQuoteToken -= _amount;
        require(
            getPoolCollateralization() >= Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        // move required collateral from sender to pool
        collateral.safeTransferFrom(
            msg.sender,
            address(this),
            collateralRequired
        );

        // move quote token amount from pool to sender
        quoteToken.safeTransfer(msg.sender, _amount);
        emit Purchase(msg.sender, _price, _amount, collateralRequired);
    }

    /// @notice Called by lenders to update interest rate of the pool when actual > target utilization
    function updateInterestRate() external {
        uint256 actualUtilization = getPoolActualUtilization();
        if (actualUtilization != 0 && previousRateUpdate < block.timestamp) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(
                previousRate,
                (Maths.sub(actualUtilization, getPoolTargetUtilization()) +
                    Maths.ONE_WAD)
            );
            previousRateUpdate = block.timestamp;
            emit UpdateInterestRate(oldRate, previousRate);
        }
    }

    /// @notice Update the global borrower inflator
    /// @dev Requires time to have passed between update calls
    function accumulatePoolInterest() private {
        if (block.timestamp - lastInflatorSnapshotUpdate != 0) {
            uint256 pendingInflator = getPendingInflator();

            totalDebt += Maths.wmul(
                totalDebt,
                Maths.wdiv(pendingInflator, inflatorSnapshot) - Maths.ONE_WAD
            );

            inflatorSnapshot = pendingInflator;
            lastInflatorSnapshotUpdate = block.timestamp;
        }
    }

    /// @notice Calculate the pending inflator based upon previous rate and last update
    /// @return The new pending inflator value
    function getPendingInflator() public view returns (uint256) {
        // calculate annualized interest rate
        uint256 spr = previousRate / SECONDS_PER_YEAR;
        uint256 secondsSinceLastUpdate = block.timestamp -
            lastInflatorSnapshotUpdate;

        return
            PRBMathUD60x18.mul(
                inflatorSnapshot,
                PRBMathUD60x18.pow(
                    PRBMathUD60x18.fromUint(1) + spr,
                    PRBMathUD60x18.fromUint(secondsSinceLastUpdate)
                )
            );
    }

    /// @notice Add debt to a borrower given the current global inflator and the last rate at which that the borrower's debt accumulated.
    /// @dev Only adds debt if a borrower has already initiated a debt position
    function accumulateBorrowerInterest(BorrowerInfo storage borrower) private {
        if (borrower.debt != 0 && borrower.inflatorSnapshot != 0) {
            uint256 pendingInterest = Maths.wmul(
                borrower.debt,
                inflatorSnapshot / borrower.inflatorSnapshot - 1
            );
            borrower.debt += pendingInterest;
            totalDebt += pendingInterest;
        }
        borrower.inflatorSnapshot = inflatorSnapshot;
    }

    // -------------------- Bucket related functions --------------------

    // TODO: rename bucketAtPrice & add bucketAtIndex
    // TODO: add return type
    /// @notice Get a bucket struct for a given price
    /// @param _price The price of the bucket to retrieve
    function bucketAt(uint256 _price)
        public
        view
        returns (
            uint256 price,
            uint256 up,
            uint256 down,
            uint256 amount,
            uint256 debt,
            uint256 inflatorSnapshot,
            uint256 lpOutstanding
        )
    {
        return _buckets.bucketAt(_price);
    }

    // -------------------- Pool state related functions --------------------

    function getPoolPrice() public view returns (uint256) {
        return lup;
    }

    function getMinimumPoolPrice() public view returns (uint256) {
        if (totalDebt != 0) {
            return Maths.wdiv(totalDebt, totalCollateral);
        }
        return 0;
    }

    function getPoolCollateralization() public view returns (uint256) {
        uint256 encumberedCollateral = getEncumberedCollateral();
        if (encumberedCollateral != 0) {
            return Maths.wdiv(totalCollateral, encumberedCollateral);
        }
        return Maths.ONE_WAD;
    }

    function getEncumberedCollateral() public view returns (uint256) {
        if (lup != 0) {
            return Maths.wdiv(totalDebt, lup);
        }
        return 0;
    }

    function getPoolActualUtilization() public view returns (uint256) {
        if (totalDebt != 0) {
            return Maths.wdiv(totalDebt, totalQuoteToken);
        }
        return 0;
    }

    function getPoolTargetUtilization() public view returns (uint256) {
        uint256 poolCollateralization = getPoolCollateralization();
        if (poolCollateralization != 0) {
            return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
        }
        return Maths.ONE_WAD;
    }

    // -------------------- Borrower related functions --------------------

    function getBorrowerInfo(address _borrower)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        BorrowerInfo memory borrower = borrowers[_borrower];
        uint256 borrowerDebt = borrower.debt;
        uint256 borrowerPendingDebt = borrower.debt;
        uint256 collateralEncumbered;
        uint256 collateralization;

        if (borrower.debt > 0 && borrower.inflatorSnapshot != 0) {
            uint256 pendingInflator = getPendingInflator();
            borrowerDebt += Maths.wmul(
                borrower.debt,
                inflatorSnapshot - borrower.inflatorSnapshot
            );
            borrowerPendingDebt += Maths.wmul(
                borrower.debt,
                pendingInflator - borrower.inflatorSnapshot
            );
            collateralEncumbered = Maths.wdiv(borrowerPendingDebt, lup);
            collateralization = Maths.wdiv(
                borrower.collateralDeposited,
                collateralEncumbered
            );
        }

        return (
            borrowerDebt,
            borrowerPendingDebt,
            borrower.collateralDeposited,
            collateralEncumbered,
            collateralization,
            borrower.inflatorSnapshot,
            inflatorSnapshot
        );
    }

    function estimatePriceForLoan(uint256 _amount)
        public
        view
        returns (uint256)
    {
        if (_amount > totalQuoteToken - totalDebt) {
            return 0;
        }

        if (lup == 0) {
            return _buckets.estimatePrice(_amount, hdp);
        }

        return _buckets.estimatePrice(_amount, lup);
    }
}
