import brownie
import pytest
import inspect
from decimal import *
from brownie import Contract
from conftest import ZRO_ADD

def test_borrow_gas(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["borrow", "addCollateral", "addQuoteToken"]):
        txes = []
        for i in range(1643, 1663):
            scaled_pool.addQuoteToken(10_000 * 10**18, i, {"from": lenders[0]})

        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[1]})

        # borrower 0 draws 10_000 DAI from single bucket (LUP)
        tx1 = scaled_pool.borrow(
            10_000 * 10**18, 1 * 10**18,ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        txes.append(tx1)
        tx2 = scaled_pool.addQuoteToken(10_000 * 10**18, 1664, {"from": lenders[1]})
        txes.append(tx2)

        # borrower 1 draws 101_000 DAI from 11 buckets
        tx3 = scaled_pool.borrow(101_000 * 10**18, 1 * 10**18,ZRO_ADD, ZRO_ADD, {"from": borrowers[1]})
        tx4 = scaled_pool.addQuoteToken(150_000 * 10**18, 1665, {"from": lenders[2]})
        txes.append(tx3)
        txes.append(tx4)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Borrow single bucket           - {test_utils.get_usage(tx1.gas_used)}\n"
                f"Reallocate debt single bucket  - {test_utils.get_usage(tx2.gas_used)}"
            )
            print(
                f"Borrow from multiple buckets (11)      - {test_utils.get_usage(tx3.gas_used)}\n"
                f"Reallocate debt multiple buckets (11)  - {test_utils.get_usage(tx4.gas_used)}"
            )
