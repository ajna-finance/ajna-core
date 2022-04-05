import brownie
from brownie import Contract
import pytest
import inspect


def test_add_remove_collateral_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(["addQuoteToken", "addCollateral", "removeCollateral"]):
        mkr_dai_pool.addQuoteToken(
            lenders[0],
            20_000 * 1e18,
            bucket_math.indexToPrice(1708),
            {"from": lenders[0]},
        )
        tx_add_collateral = mkr_dai_pool.addCollateral(
            100 * 1e18, {"from": borrowers[0]}
        )
        mkr_dai_pool.borrow(20_000 * 1e18, 2500 * 1e18, {"from": borrowers[0]})
        tx_remove_collateral = mkr_dai_pool.removeCollateral(
            10 * 1e18, {"from": borrowers[0]}
        )
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Add collateral          - {test_utils.get_usage(tx_add_collateral.gas_used)}\n"
                f"Remove collateral       - {test_utils.get_usage(tx_remove_collateral.gas_used)}"
            )


def test_claim_collateral_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(
        ["addQuoteToken", "addCollateral", "borrow", "purchaseBid", "claimCollateral"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]
        bidder = borrowers[1]

        # deposit DAI in 3 buckets
        mkr_dai_pool.addQuoteToken(
            lender, 3_000 * 1e18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 4_000 * 1e18, bucket_math.indexToPrice(1606), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 5_000 * 1e18, bucket_math.indexToPrice(1386), {"from": lender}
        )

        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
        mkr_dai_pool.borrow(4_000 * 1e18, 3000 * 1e18, {"from": borrower})

        # bidder purchases some of the middle bucket
        mkr_dai_pool.purchaseBid(
            1_500 * 1e18, bucket_math.indexToPrice(1606), {"from": bidder}
        )

        tx = mkr_dai_pool.claimCollateral(
            lender, 0.4 * 1e18, bucket_math.indexToPrice(1606), {"from": lender}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(f"Claim collateral           - {test_utils.get_usage(tx.gas_used)}")
            print("==================================")
