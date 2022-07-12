import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_quote_deposit_scaled(
    lenders,
    scaled_pool,
    capsys,
    test_utils,
    dai,
):
    with test_utils.GasWatcher(["addQuoteToken"]):
        txes = []
        for i in range(2530, 2550):
            tx = scaled_pool.addQuoteToken(100 * 10**18, i, {"from": lenders[0]})
            txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(deposit in scaled pool):")
            print("==================================")
            for i in range(len(txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(txes[i].gas_used)}")



def test_borrow_scaled(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils,
    dai,
    mkr,
):
    with test_utils.GasWatcher(["borrow"]):
        txes = []
        scaled_pool.addQuoteToken(100 * 10**18, 2550, {"from": lenders[0]})
        scaled_pool.addQuoteToken(100 * 10**18, 2560, {"from": lenders[0]})
        scaled_pool.addQuoteToken(100 * 10**18, 2570, {"from": lenders[0]})

        scaled_pool.addCollateral(100 * 10**18, '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', 1, {"from": borrowers[0]})
        tx1 = scaled_pool.borrow(110 * 10**18, 5000, '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', 1, {"from": borrowers[0]})
        txes.append(tx1)
        tx2 = scaled_pool.borrow(110 * 10**18, 5000, '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', 1, {"from": borrowers[0]})
        txes.append(tx2)
        tx3 = scaled_pool.borrow(50 * 10**18, 5000, '0x0000000000000000000000000000000000000000', '0x0000000000000000000000000000000000000000', 1, {"from": borrowers[0]})
        txes.append(tx3)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(borrow from scaled pool):")
            print("==================================")
            for i in range(len(txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(txes[i].gas_used)}")

