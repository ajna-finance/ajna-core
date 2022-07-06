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
            20_000 * 10**18,
            bucket_math.indexToPrice(1708),
            {"from": lenders[0]},
        )
        tx_add_collateral = mkr_dai_pool.addCollateral(
            100 * 10**18, {"from": borrowers[0]}
        )
        mkr_dai_pool.borrow(20_000 * 10**18, 2500 * 10**18, {"from": borrowers[0]})
        tx_remove_collateral = mkr_dai_pool.removeCollateral(
            10 * 10**18, {"from": borrowers[0]}
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
            3_000 * 10**18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            4_000 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            5_000 * 10**18, bucket_math.indexToPrice(1386), {"from": lender}
        )

        mkr_dai_pool.addCollateral(100 * 10**18, {"from": borrower})
        mkr_dai_pool.borrow(4_000 * 10**18, 3000 * 10**18, {"from": borrower})

        # bidder purchases some of the middle bucket
        mkr_dai_pool.purchaseBid(
            1_500 * 10**18, bucket_math.indexToPrice(1606), {"from": bidder}
        )

        tx = mkr_dai_pool.claimCollateral(
            0.4 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(f"Claim collateral           - {test_utils.get_usage(tx.gas_used)}")
            print("==================================")
