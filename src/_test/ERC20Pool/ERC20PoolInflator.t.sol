// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { PRBMathUD60x18 } from "@prb-math/contracts/PRBMathUD60x18.sol";

import { ERC20Pool }        from "../../ERC20Pool.sol";
import { ERC20PoolFactory } from "../../ERC20PoolFactory.sol";

import { CollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { DSTestPlus }                             from "../utils/DSTestPlus.sol";
import { UserWithCollateral, UserWithQuoteToken } from "../utils/Users.sol";

contract ERC20PoolInflatorTest is DSTestPlus {

    address            internal _poolAddress;
    CollateralToken    internal _collateral;
    ERC20Pool          internal _pool;
    QuoteToken         internal _quote;
    UserWithCollateral internal _borrower;
    UserWithQuoteToken internal _lender;

    function setUp() external {
        _collateral  = new CollateralToken();
        _quote       = new QuoteToken();
        _poolAddress = new ERC20PoolFactory().deployPool(address(_collateral), address(_quote), 0.05 * 10**18);
        _pool        = ERC20Pool(_poolAddress);  

        _borrower   = new UserWithCollateral();
        _lender     = new UserWithQuoteToken();

        _collateral.mint(address(_borrower), 100 * 1e18);
        _quote.mint(address(_lender), 200_000 * 1e18);
        _borrower.approveToken(_collateral, address(_pool), 100 * 1e18);
        _lender.approveToken(_quote, address(_pool), 200_000 * 1e18);
    }

    /**
     *  @notice With 1 lender and 1 borrower quote token is deposited
     *          then borrower adds collateral, borrows and repays over time.
     *          Inflator is checked for correctness.
     */
    function testInflator() external {
        uint256 inflatorSnapshot = _pool.inflatorSnapshot();
        uint256 lastInflatorSnapshotUpdate = _pool.lastInflatorSnapshotUpdate();
        assertEq(inflatorSnapshot,           1 * 1e27);
        assertEq(lastInflatorSnapshotUpdate, block.timestamp);

        skip(8200);
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);
        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(lastInflatorSnapshotUpdate);

        skip(8200);
        _borrower.addCollateral(_pool, 10 * 1e18);
        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(lastInflatorSnapshotUpdate);

        skip(8200);
        _borrower.borrow(_pool, 10_000 * 1e18, 4000 * 1e18);
        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(lastInflatorSnapshotUpdate);

        skip(8200);
        _borrower.approveToken(_quote, address(_pool), 1_000 * 1e18);
        _borrower.repay(_pool, 1_000 * 1e18);
        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(lastInflatorSnapshotUpdate);

        skip(8200);
        _borrower.removeCollateral(_pool, 1 * 1e18);
        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(lastInflatorSnapshotUpdate);
    }

    /**
     *  @notice With 1 lender pending inflator is tested against calculated inflator.
     */
    function testCalculatePendingInflator() external {
        _lender.addQuoteToken(_pool, address(_lender), 10_000 * 1e18, _p4000);
        uint256 calculatedInflator = calculateInflator();

        skip(8200);

        assertGt(_pool.getPendingInflator(), 0);
        assertGt(_pool.getPendingInflator(), calculatedInflator);
    }

    function assertPoolInflator(uint256 lastInflatorSnapshotUpdate)
        internal
        returns (uint256 newInflatorSnapshot, uint256 newLastInflatorSnapshotUpdate)
    {
        assertEq(_pool.lastInflatorSnapshotUpdate(), block.timestamp);
        assertGt(_pool.lastInflatorSnapshotUpdate(), lastInflatorSnapshotUpdate);
        assertEq(_pool.inflatorSnapshot(),           calculateInflator());

        newInflatorSnapshot           = _pool.inflatorSnapshot();
        newLastInflatorSnapshotUpdate = _pool.lastInflatorSnapshotUpdate();
    }

    function calculateInflator() internal view returns (uint256 calculatedInflator) {
        uint256 secondsSinceLastUpdate = block.timestamp - _pool.lastInflatorSnapshotUpdate();
        uint256 spr                    = _pool.interestRate() / (3600 * 24 * 365);
        calculatedInflator            = PRBMathUD60x18.mul(
            _pool.inflatorSnapshot(),
            PRBMathUD60x18.pow(
                PRBMathUD60x18.fromUint(1) + spr,
                PRBMathUD60x18.fromUint(secondsSinceLastUpdate)
            )
        );
    }

}
