from multiprocessing import pool
import brownie
from brownie import Contract
import pytest
import inspect

@pytest.mark.skip
def test_repay_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(["addQuoteToken", "addCollateral", "repay", "borrow"]):
        for i in range(1643, 1663):
            mkr_dai_pool.addQuoteToken(
                10_000 * 10**18,
                bucket_math.indexToPrice(i),
                {"from": lenders[0]},
            )

        dai.transfer(borrowers[0], 10_000 * 10**18, {"from": lenders[1]})
        mkr_dai_pool.addCollateral(100 * 10**18, {"from": borrowers[0]})

        # borrow 10_000 DAI from single bucket (LUP)
        mkr_dai_pool.borrow(10_000 * 10**18, 1 * 10**18, {"from": borrowers[0]})
        tx_repay_to_one_bucket = mkr_dai_pool.repay(
            10_001 * 10**18, {"from": borrowers[0]}
        )

        # borrow 101_000 DAI from 11 buckets
        mkr_dai_pool.borrow(101_000 * 10**18, 1 * 10**18, {"from": borrowers[0]})
        tx_repay_to_11_buckets = mkr_dai_pool.repay(
            101_001 * 10**18, {"from": borrowers[0]}
        )

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Repay single bucket          - {test_utils.get_usage(tx_repay_to_one_bucket.gas_used)}\n"
                f"Repay multiple buckets (11)  - {test_utils.get_usage(tx_repay_to_11_buckets.gas_used)}"
            )
        assert True
