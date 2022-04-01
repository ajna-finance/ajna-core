import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_borrow_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(["borrow", "addCollateral", "addQuoteToken"]):
        txes = []
        for i in range(1643, 1663):
            mkr_dai_pool.addQuoteToken(
                lenders[0],
                10_000 * 1e18,
                bucket_math.indexToPrice(i),
                {"from": lenders[0]},
            )

        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[0]})
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[1]})

        # borrow 10_000 DAI from single bucket (LUP)
        tx_one_bucket = mkr_dai_pool.borrow(
            10_000 * 1e18, 1 * 1e18, {"from": borrowers[0]}
        )
        tx_reallocate_debt_one_bucket = mkr_dai_pool.addQuoteToken(
            lenders[1],
            10_000 * 1e18,
            bucket_math.indexToPrice(1664),
            {"from": lenders[1]},
        )
        txes.append(tx_one_bucket)
        txes.append(tx_reallocate_debt_one_bucket)

        # borrow 101_000 DAI from 11 buckets
        tx_11_buckets = mkr_dai_pool.borrow(
            101_000 * 1e18, 1 * 1e18, {"from": borrowers[1]}
        )
        tx_reallocate_debt_11_buckets = mkr_dai_pool.addQuoteToken(
            lenders[2],
            150_000 * 1e18,
            bucket_math.indexToPrice(1665),
            {"from": lenders[2]},
        )
        txes.append(tx_11_buckets)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Borrow single bucket           - {test_utils.get_usage(tx_one_bucket.gas_used)}\n"
                f"Reallocate debt single bucket  - {test_utils.get_usage(tx_reallocate_debt_one_bucket.gas_used)}"
            )
            print(
                f"Borrow from multiple buckets (11)      - {test_utils.get_usage(tx_11_buckets.gas_used)}\n"
                f"Reallocate debt multiple buckets (11)  - {test_utils.get_usage(tx_reallocate_debt_11_buckets.gas_used)}"
            )
