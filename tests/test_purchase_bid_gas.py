import pytest
from decimal import *
from brownie import Contract

@pytest.mark.skip
def test_purchase_bid_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):

    with test_utils.GasWatcher(
        ["addQuoteToken", "addCollateral", "borrow", "purchaseBid"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]
        bidder = borrowers[1]

        mkr_dai_pool.addQuoteToken(
            3_000 * 10**18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            3_000 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            3_000 * 10**18, bucket_math.indexToPrice(1524), {"from": lender}
        )

        # borrower takes a loan of 4000 DAI making bucket 4000 to be fully utilized
        mkr_dai_pool.addCollateral(100 * 10**18, {"from": borrower})
        mkr_dai_pool.borrow(4_000 * 10**18, 3000 * 10**18, {"from": borrower})

        # purchase 2000 bid from 1663 bucket
        tx = mkr_dai_pool.purchaseBid(
            2_000 * 10**18, bucket_math.indexToPrice(1663), {"from": bidder}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Purchase bid (reallocate to one bucket)           - {test_utils.get_usage(tx.gas_used)}"
            )
