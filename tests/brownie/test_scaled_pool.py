import brownie
import pytest
import inspect
from brownie import Contract


def test_quote_deposit_move_remove_scaled(
    lenders,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken", "moveQuoteToken", "removeQuoteToken"]):
        add_txes = []
        for i in range(2530, 2550):
            tx = scaled_pool.addQuoteToken(100 * 10**18, i, {"from": lenders[0]})
            add_txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(deposit in scaled pool):")
            print("==================================")
            for i in range(len(add_txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(add_txes[i].gas_used)}")

        move_txes = []
        for i in range(2530, 2550):
            tx = scaled_pool.moveQuoteToken(100 * 10**18, i, i + 30, {"from": lenders[0]})
            move_txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(move from scaled pool):")
            print("==================================")
            for i in range(len(move_txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(move_txes[i].gas_used)}")

        remove_txes = []
        for i in range(2560, 2570):
            tx = scaled_pool.removeQuoteToken(100 * 10**18, i, {"from": lenders[0]})
            remove_txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(remove from scaled pool):")
            print("==================================")
            for i in range(len(remove_txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(remove_txes[i].gas_used)}")


def test_borrow_repay_scaled(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken", "drawDebt", "repayDebt"]):

        scaled_pool.addQuoteToken(100 * 10**18, 2550, {"from": lenders[0]})
        scaled_pool.addQuoteToken(100 * 10**18, 2560, {"from": lenders[0]})
        scaled_pool.addQuoteToken(100 * 10**18, 2570, {"from": lenders[0]})

        col_txes = []
        for i in range(10):
            tx = scaled_pool.drawDebt(borrowers[0], 0, 0, 10 * 10**18, {"from": borrowers[0]})
            col_txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(add collateral in scaled pool):")
            print("==================================")
            for i in range(len(col_txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(col_txes[i].gas_used)}")
        
        txes = []
        tx1 = scaled_pool.drawDebt(borrowers[0], 110 * 10**18, 5000, 0, {"from": borrowers[0]})
        txes.append(tx1)
        tx2 = scaled_pool.drawDebt(borrowers[0], 110 * 10**18, 5000, 0, {"from": borrowers[0]})
        txes.append(tx2)
        tx3 = scaled_pool.drawDebt(borrowers[0], 50 * 10**18, 5000, 0, {"from": borrowers[0]})
        txes.append(tx3)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(borrow from scaled pool):")
            print("==================================")
            for i in range(len(txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(txes[i].gas_used)}")

        repay_txes = []
        tx = scaled_pool.repayDebt(borrowers[0], 110 * 10**18, 0, {"from": borrowers[0]})
        repay_txes.append(tx)
        tx = scaled_pool.repayDebt(borrowers[0], 110 * 10**18, 0, {"from": borrowers[0]})
        repay_txes.append(tx)
        tx = scaled_pool.repayDebt(borrowers[0], 50 * 10**18, 0, {"from": borrowers[0]})
        repay_txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(repay in scaled pool):")
            print("==================================")
            for i in range(len(repay_txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(repay_txes[i].gas_used)}")
