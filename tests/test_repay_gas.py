import brownie
import pytest
import inspect
from conftest import ZRO_ADD
from brownie import Contract
from multiprocessing import pool

def test_repay_gas(
    lenders,
    borrowers,
    scaled_pool,
    dai,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken", "addCollateral", "repay", "borrow"]):
        for i in range(1643, 1663):
            scaled_pool.addQuoteToken(10_000 * 10**18, i, {"from": lenders[0]})

        dai.transfer(borrowers[0], 10_000 * 10**18, {"from": lenders[1]})
        scaled_pool.addCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})

        # borrow 10_000 DAI from single bucket (LUP)
        scaled_pool.borrow(10_000 * 10**18, 1 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        tx_repay_to_one_bucket = scaled_pool.repay(10_001 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})

        # borrow 101_000 DAI from 11 buckets
        scaled_pool.borrow(101_000 * 10**18, 1 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        tx_repay_to_11_buckets = scaled_pool.repay(101_001 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Repay single bucket          - {test_utils.get_usage(tx_repay_to_one_bucket.gas_used)}\n"
                f"Repay multiple buckets (11)  - {test_utils.get_usage(tx_repay_to_11_buckets.gas_used)}"
            )
        assert True
