// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {PRBMathUD60x18} from "@prb-math/contracts/PRBMathUD60x18.sol";

import {DSTestPlus} from "./utils/DSTestPlus.sol";
import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";

contract ERC20PoolInflatorTest is DSTestPlus {
    ERC20Pool internal pool;
    CollateralToken internal collateral;
    QuoteToken internal quote;

    UserWithCollateral internal borrower;
    UserWithQuoteToken internal lender;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        ERC20PoolFactory factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);

        borrower = new UserWithCollateral();
        collateral.mint(address(borrower), 100 * 1e18);
        borrower.approveToken(collateral, address(pool), 100 * 1e18);

        lender = new UserWithQuoteToken();
        quote.mint(address(lender), 200_000 * 1e18);
        lender.approveToken(quote, address(pool), 200_000 * 1e18);
    }

    function testInflator() public {
        uint256 inflatorSnapshot = pool.inflatorSnapshot();
        uint256 lastInflatorSnapshotUpdate = pool.lastInflatorSnapshotUpdate();
        assertEq(inflatorSnapshot, 1 * 1e18);
        assertEq(lastInflatorSnapshotUpdate, block.timestamp);

        skip(8200);
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 4000 * 1e18);

        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(
            lastInflatorSnapshotUpdate
        );

        skip(8200);
        borrower.addCollateral(pool, 10 * 1e18);

        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(
            lastInflatorSnapshotUpdate
        );

        skip(8200);
        borrower.borrow(pool, 10_000 * 1e18, 4000 * 1e18);

        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(
            lastInflatorSnapshotUpdate
        );

        skip(8200);
        borrower.approveToken(quote, address(pool), 1_000 * 1e18);
        borrower.repay(pool, 1_000 * 1e18);

        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(
            lastInflatorSnapshotUpdate
        );

        skip(8200);
        borrower.removeCollateral(pool, 1 * 1e18);

        (inflatorSnapshot, lastInflatorSnapshotUpdate) = assertPoolInflator(
            lastInflatorSnapshotUpdate
        );
    }

    function testCalculatePendingInflator() public {
        lender.addQuoteToken(pool, address(lender), 10_000 * 1e18, 4000 * 1e18);
        uint256 calculatedInflator = calculateInflator();

        skip(8200);

        assertGt(pool.getPendingInflator(), 0);
        assertGt(pool.getPendingInflator(), calculatedInflator);
    }

    function assertPoolInflator(uint256 lastInflatorSnapshotUpdate)
        internal
        returns (
            uint256 newInflatorSnapshot,
            uint256 newLastInflatorSnapshotUpdate
        )
    {
        assertEq(pool.lastInflatorSnapshotUpdate(), block.timestamp);
        assertGt(pool.lastInflatorSnapshotUpdate(), lastInflatorSnapshotUpdate);

        assertEq(pool.inflatorSnapshot(), calculateInflator());

        newInflatorSnapshot = pool.inflatorSnapshot();
        newLastInflatorSnapshotUpdate = pool.lastInflatorSnapshotUpdate();
    }

    function calculateInflator()
        internal
        view
        returns (uint256 calculatedInflator)
    {
        uint256 secondsSinceLastUpdate = block.timestamp -
            pool.lastInflatorSnapshotUpdate();

        uint256 spr = pool.previousRate() / (3600 * 24 * 365);

        calculatedInflator = PRBMathUD60x18.mul(
            pool.inflatorSnapshot(),
            PRBMathUD60x18.pow(
                PRBMathUD60x18.fromUint(1) + spr,
                PRBMathUD60x18.fromUint(secondsSinceLastUpdate)
            )
        );
    }
}
