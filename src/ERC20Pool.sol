// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PRBMathUD60x18} from "@prb-math/contracts/PRBMathUD60x18.sol";
import {Clone} from "@clones/Clone.sol";

import "./libraries/Maths.sol";
import "./libraries/BucketMath.sol";
import "./libraries/Buckets.sol";

interface IPool {
    function addQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external returns (uint256 lpTokens);

    function removeQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function claimCollateral(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function repay(uint256 _amount) external;

    function purchaseBid(uint256 _amount, uint256 _price) external;

    function getLPTokenBalance(address _owner, uint256 _price)
        external
        view
        returns (uint256 lpTokens);

    function getLPTokenExchangeValue(uint256 _lpTokens, uint256 _price)
        external
        view
        returns (uint256 _collateralTokens, uint256 _quoteTokens);

    function liquidate(address _borrower) external;
}

contract ERC20Pool is IPool, Clone {
    using SafeERC20 for ERC20;
    using Buckets for mapping(uint256 => Buckets.Bucket);

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 inflatorSnapshot; // last updated inflator rate for a given borrower
    }

    uint256 public constant SECONDS_PER_YEAR = 3600 * 24 * 365;

    mapping(uint256 => Buckets.Bucket) private _buckets;
    BitMaps.BitMap private bitmap;

    uint256 public collateralScale;
    uint256 public quoteTokenScale;

    uint256 public hdp;
    uint256 public lup;

    // lenders lp token balances: lender address -> price bucket -> lender lp
    mapping(address => mapping(uint256 => uint256)) public lpBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public inflatorSnapshot;
    uint256 public lastInflatorSnapshotUpdate;
    uint256 public previousRate;
    uint256 public previousRateUpdate;

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
    event Liquidate(address indexed borrower, uint256 debt, uint256 collateral);

    // TODO: add onlyFactory modifier
    function initialize() external {
        collateralScale = 10**(18 - collateral().decimals());
        quoteTokenScale = 10**(18 - quoteToken().decimals());

        inflatorSnapshot = Maths.ONE_WAD;
        lastInflatorSnapshotUpdate = block.timestamp;
        previousRate = Maths.wdiv(5, 100);
        previousRateUpdate = block.timestamp;
    }

    function collateral() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0));
    }

    function quoteToken() public pure returns (ERC20) {
        return ERC20(_getArgAddress(0x14));
    }

    /// @notice Called by lenders to add an amount of credit at a specified price bucket
    /// @param _amount The amount of quote token to be added by a lender
    /// @param _price The bucket to which the quote tokens will be added
    function addQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external returns (uint256) {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        accumulatePoolInterest();

        // create bucket if doesn't exist
        if (!BitMaps.get(bitmap, _price)) {
            hdp = _buckets.initializeBucket(hdp, _price);
            BitMaps.setTo(bitmap, _price, true);
        }

        // deposit amount
        bool reallocate = (totalDebt != 0 && _price >= lup);
        (uint256 newLup, uint256 lpTokens) = _buckets.addQuoteToken(
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
        lpBalance[_recipient][_price] += lpTokens;

        // update quote token accumulator
        totalQuoteToken += _amount;

        quoteToken().safeTransferFrom(
            _recipient,
            address(this),
            _amount / quoteTokenScale
        );

        // TODO: add require to ensure quote tokens were transferred successfully

        emit AddQuoteToken(_recipient, _price, _amount, lup);
        return lpTokens;
    }

    /// @notice Called by lenders to remove an amount of credit at a specified price bucket
    /// @param _amount The amount of quote token to be removed by a lender
    /// @param _price The bucket from which quote tokens will be removed
    function removeQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        accumulatePoolInterest();

        // remove from bucket
        (uint256 newLup, uint256 lpTokens) = _buckets.removeQuoteToken(
            _price,
            _amount,
            lpBalance[_recipient][_price],
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

        lpBalance[_recipient][_price] -= lpTokens;

        quoteToken().safeTransfer(_recipient, _amount / quoteTokenScale);
        emit RemoveQuoteToken(_recipient, _price, _amount, lup);
    }

    function addCollateral(uint256 _amount) external {
        accumulatePoolInterest();
        borrowers[msg.sender].collateralDeposited += _amount;
        totalCollateral += _amount;

        // TODO: verify that the pool address is the holder of any token balances - i.e. if any funds are held in an escrow for backup interest purposes
        collateral().safeTransferFrom(
            msg.sender,
            address(this),
            _amount / collateralScale
        );
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

        collateral().safeTransfer(msg.sender, _amount / collateralScale);
        emit RemoveCollateral(msg.sender, _amount);
    }

    /// @notice Called by lenders to claim unencumbered collateral from a price bucket
    /// @param _amount The amount of unencumbered collateral to claim
    /// @param _price The bucket from which unencumbered collateral will be claimed
    function claimCollateral(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        uint256 maxClaim = lpBalance[_recipient][_price];
        require(maxClaim != 0, "ajna/no-claim-to-bucket");

        uint256 claimedLpTokens = _buckets.claimCollateral(
            _price,
            _amount,
            maxClaim
        );

        lpBalance[_recipient][_price] -= claimedLpTokens;

        collateral().safeTransfer(_recipient, _amount / collateralScale);
        emit ClaimCollateral(_recipient, _price, _amount, claimedLpTokens);
    }

    /// @notice Called by a borrower to open or expand a position
    /// @param _amount The amount of quote token to borrow
    /// @param _stopPrice Lower bound of LUP change (if any) that the borrower will tolerate from a creating or modifying position
    function borrow(uint256 _amount, uint256 _stopPrice) external {
        require(_amount <= totalQuoteToken, "ajna/not-enough-liquidity");

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

        totalQuoteToken -= _amount;
        totalDebt += _amount;
        require(
            getPoolCollateralization() >= Maths.ONE_WAD,
            "ajna/pool-undercollateralized"
        );

        quoteToken().safeTransfer(msg.sender, _amount / quoteTokenScale);
        emit Borrow(msg.sender, lup, _amount);
    }

    /// @notice Called by a borrower to repay some amount of their borrowed quote tokens
    /// @param _maxAmount The maximum amount of quote token to repay
    function repay(uint256 _maxAmount) external {
        uint256 availableAmount = quoteToken().balanceOf(msg.sender) *
            quoteTokenScale;
        require(availableAmount >= _maxAmount, "ajna/no-funds-to-repay");

        BorrowerInfo storage borrower = borrowers[msg.sender];
        require(borrower.debt != 0, "ajna/no-debt-to-repay");
        accumulatePoolInterest();
        accumulateBorrowerInterest(borrower);

        uint256 amount;
        if (_maxAmount >= borrower.debt) {
            amount = borrower.debt;
        } else {
            amount = _maxAmount;
        }

        uint256 debtToPay;
        (lup, debtToPay) = _buckets.repay(amount, lup, inflatorSnapshot);

        borrower.debt -= Maths.min(borrower.debt, amount);
        totalQuoteToken += amount;
        totalDebt -= Maths.min(totalDebt, amount);

        quoteToken().safeTransferFrom(
            msg.sender,
            address(this),
            amount / quoteTokenScale
        );
        emit Repay(msg.sender, lup, amount);
    }

    /// @notice Exchanges collateral for quote token
    /// @param _amount The amount of quote token to purchase
    /// @param _price The purchasing price of quote token
    function purchaseBid(uint256 _amount, uint256 _price) external {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        uint256 collateralRequired = Maths.wdiv(_amount, _price);
        require(
            collateral().balanceOf(msg.sender) * collateralScale >=
                collateralRequired,
            "ajna/not-enough-collateral-balance"
        );

        accumulatePoolInterest();

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
        collateral().safeTransferFrom(
            msg.sender,
            address(this),
            collateralRequired / collateralScale
        );

        // move quote token amount from pool to sender
        quoteToken().safeTransfer(msg.sender, _amount / quoteTokenScale);
        emit Purchase(msg.sender, _price, _amount, collateralRequired);
    }

    /// @notice Liquidates position for given borrower
    function liquidate(address _borrower) external {
        accumulatePoolInterest();

        BorrowerInfo storage borrower = borrowers[_borrower];
        accumulateBorrowerInterest(borrower);

        uint256 debt = borrower.debt;
        uint256 collateralDeposited = borrower.collateralDeposited;

        require(debt != 0, "ajna/no-debt-to-liquidate");

        uint256 collateralization = Maths.wdiv(
            collateralDeposited,
            Maths.wdiv(debt, lup)
        );
        require(
            collateralization <= Maths.ONE_WAD,
            "ajna/borrower-collateralized"
        );

        uint256 requiredCollateral = _buckets.liquidate(
            debt,
            collateralDeposited,
            hdp,
            inflatorSnapshot
        );

        // pool level accounting
        totalDebt -= borrower.debt;
        totalCollateral -= requiredCollateral;

        // borrower accounting
        borrower.debt = 0;
        borrower.collateralDeposited -= requiredCollateral;

        emit Liquidate(_borrower, debt, requiredCollateral);
    }

    /// @notice Called by lenders to update interest rate of the pool when actual > target utilization
    function updateInterestRate() external {
        uint256 actualUtilization = getPoolActualUtilization();
        if (actualUtilization != 0 && previousRateUpdate < block.timestamp) {
            uint256 oldRate = previousRate;
            accumulatePoolInterest();

            previousRate = Maths.wmul(
                previousRate,
                (Maths.sub(actualUtilization + Maths.ONE_WAD,
                    getPoolTargetUtilization()))
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

            totalDebt += getPendingInterest(
                totalDebt,
                pendingInflator,
                inflatorSnapshot
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
    function accumulateBorrowerInterest(BorrowerInfo storage _borrower)
        private
    {
        if (_borrower.debt != 0 && _borrower.inflatorSnapshot != 0) {
            _borrower.debt += getPendingInterest(
                _borrower.debt,
                inflatorSnapshot,
                _borrower.inflatorSnapshot
            );
        }
        _borrower.inflatorSnapshot = inflatorSnapshot;
    }

    function getPendingInterest(
        uint256 _debt,
        uint256 _pendingInflator,
        uint256 _currentInflator
    ) private pure returns (uint256) {
        return
            Maths.wmul(
                _debt,
                Maths.wdiv(_pendingInflator, _currentInflator) - Maths.ONE_WAD
            );
    }

    function getLPTokenBalance(address _owner, uint256 _price)
        external
        view
        returns (uint256 lpTokens)
    {
        return lpBalance[_owner][_price];
    }

    /// @notice Calculate the amount of collateral and quote tokens for a given amount of LP Tokens
    /// @param _lpTokens The number of lpTokens to calculate amounts for
    /// @param _price The price bucket for which the value should be calculated
    function getLPTokenExchangeValue(uint256 _lpTokens, uint256 _price)
        external
        view
        returns (uint256 collateralTokens, uint256 quoteTokens)
    {
        require(BucketMath.isValidPrice(_price), "ajna/invalid-bucket-price");

        (
            ,
            ,
            ,
            uint256 quote,
            ,
            ,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        ) = bucketAt(_price);

        // calculate lpTokens share of all outstanding lpTokens for the bucket
        uint256 lenderShare = PRBMathUD60x18.div(_lpTokens, lpOutstanding);

        collateralTokens = PRBMathUD60x18.mul(bucketCollateral, lenderShare);
        quoteTokens = PRBMathUD60x18.mul(quote, lenderShare);
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
            uint256 bucketInflator,
            uint256 lpOutstanding,
            uint256 bucketCollateral
        )
    {
        return _buckets.bucketAt(_price);
    }

    function isBucketInitialized(uint256 _price) public view returns (bool) {
        return BitMaps.get(bitmap, _price);
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
        if (totalQuoteToken != 0) {
            return Maths.wdiv(totalDebt, (totalQuoteToken + totalDebt));
        }
        return 0;
    }

    function getPoolTargetUtilization() public view returns (uint256) {
        return Maths.wdiv(Maths.ONE_WAD, getPoolCollateralization());
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
            borrowerDebt += getPendingInterest(
                borrower.debt,
                inflatorSnapshot,
                borrower.inflatorSnapshot
            );
            borrowerPendingDebt += getPendingInterest(
                borrower.debt,
                getPendingInflator(),
                borrower.inflatorSnapshot
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
        if (lup == 0) {
            return _buckets.estimatePrice(_amount, hdp);
        }

        return _buckets.estimatePrice(_amount, lup);
    }
}
