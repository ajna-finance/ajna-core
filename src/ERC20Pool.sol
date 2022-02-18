// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IPool {
    function addQuoteToken(uint256 _amount, uint256 _price) external;

    function removeQuoteToken(uint256 _amount, uint256 _price) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function payBack(uint256 _amount) external;
}

contract Common {
    // --- Math ---
    uint256 public constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }
}

contract ERC20Pool is IPool, Common {
    using SafeERC20 for IERC20;

    struct BorrowerInfo {
        uint256 debt;
        uint256 collateralDeposited;
        uint256 collateralEncumbered;
    }

    struct Bucket {
        uint256 price; // current bucket price
        uint256 next; // next utilizable bucket price
        uint256 amount; // total quote deposited in bucket
        uint256 debt; // accumulated bucket debt
    }

    uint256 public constant MAX_PRICE = 7000 * WAD;
    uint256 public constant MIN_PRICE = 1000 * WAD;
    uint256 public constant COUNT = 6000;
    uint256 public constant STEP = (MAX_PRICE - MIN_PRICE) / COUNT;

    IERC20 public immutable collateral;
    IERC20 public immutable quoteToken;

    uint256 public hup;

    // buckets: price -> Bucket
    mapping(uint256 => Bucket) public buckets;

    // lenders book: lender address -> price bucket -> amount
    mapping(address => mapping(uint256 => uint256)) public lenders;
    // lender balance: lender address -> total amount
    mapping(address => uint256) public lenderBalance;

    // borrowers book: borrower address -> BorrowerInfo
    mapping(address => BorrowerInfo) public borrowers;

    uint256 public totalCollateral;
    uint256 public totalQuoteToken;
    uint256 public totalDebt;
    uint256 public totalEncumberedCollateral;

    event AddQuoteToken(
        address lender,
        uint256 price,
        uint256 amount,
        uint256 hup
    );
    event RemoveQuoteToken(address lender, uint256 price, uint256 amount);
    event AddCollateral(address borrower, uint256 amount);
    event RemoveCollateral(address borrower, uint256 amount);
    event Borrow(address borrower, uint256 price, uint256 amount);
    event PayBack(address borrower, uint256 price, uint256 amount);

    constructor(IERC20 _collateral, IERC20 _quoteToken) {
        collateral = _collateral;
        quoteToken = _quoteToken;
    }

    function addQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "ajna/invalid-bucket-price");

        lenders[msg.sender][_price] += _amount;
        lenderBalance[msg.sender] += _amount;
        buckets[_price].price = _price;
        buckets[_price].amount += _amount;
        totalQuoteToken += _amount;

        //  update HUP
        if (_price > hup && buckets[_price].amount - buckets[_price].debt > 0) {
            buckets[_price].next = hup;
            hup = _price;
        }

        uint256 cur = hup;
        uint256 next = buckets[hup].next;

        // update next price pointers accordingly to current price
        while (true) {
            if (_price > next) {
                buckets[cur].next = _price;
                buckets[_price].next = next;
                break;
            }
            cur = next;
            next = buckets[next].next;
        }

        quoteToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddQuoteToken(msg.sender, _price, _amount, hup);
    }

    function removeQuoteToken(uint256 _amount, uint256 _price) external {
        require(isValidPrice(_price), "Not a valid bucket price");
        require(
            lenders[msg.sender][_price] >= _amount,
            "Exceeds lended amount"
        );
        require(_amount <= onDeposit(_price), "Not enough liquidity in bucket");

        lenders[msg.sender][_price] -= _amount;
        lenderBalance[msg.sender] -= _amount;
        buckets[_price].amount -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit RemoveQuoteToken(msg.sender, _price, _amount);
    }

    function addCollateral(uint256 _amount) external {
        borrowers[msg.sender].collateralDeposited += _amount;
        totalCollateral += _amount;

        collateral.safeTransferFrom(msg.sender, address(this), _amount);
        emit AddCollateral(msg.sender, _amount);
    }

    function removeCollateral(uint256 _amount) external {
        require(
            borrowers[msg.sender].collateralDeposited -
                borrowers[msg.sender].collateralEncumbered >
                _amount,
            "Not enough collateral"
        );

        borrowers[msg.sender].collateralDeposited -= _amount;
        totalCollateral -= _amount;

        collateral.safeTransfer(msg.sender, _amount);
        emit RemoveCollateral(msg.sender, _amount);
    }

    function borrow(uint256 _amount, uint256 _stopPrice) external {
        require(
            _amount <= totalQuoteToken - totalDebt,
            "ajna/not-enough-liquidity"
        );
        uint256 nextHup = hup;
        uint256 amountRemaining = _amount;
        uint256 onNextHupDeposit = onDeposit();

        while (true) {
            require(nextHup >= _stopPrice, "ajna/stop-price-exceeded");

            if (amountRemaining > onNextHupDeposit) {
                // take all on deposit from this bucket, move to next
                buckets[nextHup].debt += onNextHupDeposit;
                amountRemaining -= onNextHupDeposit;
            } else if (amountRemaining <= onNextHupDeposit) {
                // take all remaining loan from this bucket and exit
                buckets[nextHup].debt += amountRemaining;
                break;
            }

            nextHup = getNextHup(nextHup);
            onNextHupDeposit = onDeposit(nextHup);
        }

        if (hup != nextHup) {
            hup = nextHup;
        }

        require(
            borrowers[msg.sender].collateralDeposited -
                borrowers[msg.sender].collateralEncumbered >
                wdiv(_amount, hup),
            "ajna/not-enough-collateral"
        );

        totalDebt += _amount;
        borrowers[msg.sender].debt += _amount;
        borrowers[msg.sender].collateralEncumbered += wdiv(_amount, hup);
        totalEncumberedCollateral += wdiv(_amount, hup);

        quoteToken.safeTransfer(msg.sender, _amount);
        emit Borrow(msg.sender, hup, _amount);
    }

    function payBack(uint256 _amount) external {
        require(
            _amount <= borrowers[msg.sender].debt,
            "Amount greater than debt"
        );
        borrowers[msg.sender].debt -= _amount;
        uint256 poolPrice = getPoolPrice();

        if (
            borrowers[msg.sender].collateralEncumbered >=
            wdiv(_amount, poolPrice)
        ) {
            // pay back entire amount
            borrowers[msg.sender].collateralEncumbered -= wdiv(
                _amount,
                poolPrice
            );
            totalEncumberedCollateral -= wdiv(_amount, poolPrice);
        } else {
            // pay back only amount needed to cover encumbered collateral
            _amount = wmul(
                borrowers[msg.sender].collateralEncumbered,
                poolPrice
            );
            totalEncumberedCollateral -= borrowers[msg.sender]
                .collateralEncumbered;
            borrowers[msg.sender].collateralEncumbered = 0;
        }

        buckets[hup].amount += _amount;
        totalDebt -= _amount;

        quoteToken.safeTransfer(msg.sender, _amount);
        emit PayBack(msg.sender, poolPrice, _amount);
    }

    function isValidPrice(uint256 _price) public view returns (bool) {
        if ((_price - MIN_PRICE) % STEP > 0) {
            return false;
        }
        uint256 index = (_price - MIN_PRICE) / STEP;
        return (index >= 0 && index < COUNT);
    }

    function getNextHup() public view returns (uint256) {
        return getNextHup(hup);
    }

    function getNextHup(uint256 _price) public view returns (uint256) {
        uint256 cur = _price;
        while (true) {
            if (buckets[cur].amount - buckets[cur].debt > 0) {
                return cur;
            }
            cur = buckets[cur].next;
        }
    }

    function onDeposit(uint256 _price) public view returns (uint256) {
        return buckets[_price].amount - buckets[_price].debt;
    }

    function onDeposit() public view returns (uint256) {
        return onDeposit(hup);
    }

    function getPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return wdiv(totalDebt, totalEncumberedCollateral);
        }
        return hup;
    }

    function getMinimumPoolPrice() public view returns (uint256) {
        if (totalDebt > 0) {
            return wdiv(totalDebt, totalCollateral);
        }
        return hup;
    }

    function getPoolCollateralization() public view returns (uint256) {
        return wdiv(totalCollateral, totalEncumberedCollateral);
    }

    function getCollateralization(address _borrower)
        public
        view
        returns (uint256)
    {
        return
            wdiv(
                borrowers[_borrower].collateralDeposited -
                    borrowers[_borrower].collateralEncumbered,
                getPoolPrice()
            );
    }

    function getActualUtilization() public view returns (uint256) {
        return wdiv(totalQuoteToken, totalDebt + totalQuoteToken);
    }

    function getTargetUtilization() public view returns (uint256) {
        return wdiv(1 * WAD, getPoolCollateralization());
    }
}
