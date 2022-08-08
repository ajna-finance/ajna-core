import inspect
from decimal import *
from conftest import ZRO_ADD

def test_quote_deposit_gas_below_hdp(
    lenders,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken"]):
        txes = []
        for i in reversed(range(1000, 1020)):
            tx = scaled_pool.addQuoteToken(
                100 * 10**18,
                i,
                {"from": lenders[0]},
            )
            txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(deposit below hdp):")
            print("==================================")
            for i in range(len(txes)):
                print(f"Transaction: {i} | {test_utils.get_usage(txes[i].gas_used)}")

def test_quote_deposit_gas_above_hdp(
    lenders,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken"]):
        txes = []
        for i in range(1000, 1020):
            tx = scaled_pool.addQuoteToken(
                100 * 10**18,
                i,
                {"from": lenders[0]},
            )
            txes.append(tx)
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]})(deposit above hdp):")
            print("==================================")
            for i in range(len(txes)):
                print(
                    f"Transaction: {i} | Gas used: {test_utils.get_usage(txes[i].gas_used)}"
                )

def test_quote_removal_from_lup_with_reallocation(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):

    with test_utils.GasWatcher(
        ["removeQuoteToken", "pledgeCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        scaled_pool.addQuoteToken(
            3_400 * 10**18, 1_663, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            3_400 * 10**18, 1_606, {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})
        scaled_pool.borrow(3_000 * 10**18, 4_000 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})

        # lender removes 3_400 DAI
        # FIXME: removing all quote token from bucket reverts with S:RQT:INSUF_LPS
        tx = scaled_pool.removeQuoteToken(3_400 * 10**18, 1_663, {"from": lender})

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Remove quote token from lup (reallocate to one bucket)           - {test_utils.get_usage(tx.gas_used)}"
            )

def test_quote_removal_below_lup(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):

    with test_utils.GasWatcher(
        ["removeQuoteToken", "pledgeCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1_663, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1_606, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1_524, {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})
        scaled_pool.borrow(3_000 * 10**18, 4_000 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})

        # lender removes 5_000 DAI
        tx = scaled_pool.removeQuoteToken(5_000 * 10**18, 1_606, {"from": lender})

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Remove quote token below lup            - {test_utils.get_usage(tx.gas_used)}"
            )

def test_quote_move_from_lup_with_reallocation(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):

    with test_utils.GasWatcher(
        ["moveQuoteToken", "pledgeCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        scaled_pool.addQuoteToken(
            3_400 * 10**18, 1663, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            3_400 * 10**18, 1606, {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})
        scaled_pool.borrow(3_000 * 10**18, 4000 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})

        # lender moves 400 DAI
        tx = scaled_pool.moveQuoteToken(
            400 * 10**18, 1663, 1_000, {"from": lender}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Move quote token from lup           - {test_utils.get_usage(tx.gas_used)}"
            )

def test_quote_move_to_lup(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):

    with test_utils.GasWatcher(
        ["moveQuoteToken", "pledgeCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1663, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1606, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1524, {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})
        scaled_pool.borrow(3_000 * 10**18, 4000 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})

        # lender moves 1000 DAI to lup
        tx = scaled_pool.moveQuoteToken(
            5_000 * 10**18, 1606, 1663, {"from": lender}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Move quote token to lup            - {test_utils.get_usage(tx.gas_used)}"
            )
