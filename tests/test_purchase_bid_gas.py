import brownie
from brownie import Contract
import pytest
from decimal import *


def test_purchase_bid_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
    test_utils,
):

    with test_utils.GasWatcher(
        ["addQuoteToken", "addCollateral", "borrow", "purchaseBid"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]
        bidder = borrowers[1]

        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 1663, {"from": lender})
        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 1606, {"from": lender})
        mkr_dai_pool.addQuoteToken(3_000 * 1e18, 1524, {"from": lender})

        # borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
        mkr_dai_pool.borrow(4_000 * 1e18, 3000 * 1e18, {"from": borrower})

        # purchase 2000 bid from 1663 bucket
        tx = mkr_dai_pool.purchaseBid(2_000 * 1e18, 1663, {"from": bidder})

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Purchase bid (reallocate to one bucket)           - {test_utils.get_usage(tx.gas_used)}"
            )
