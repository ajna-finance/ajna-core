import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_quote_deposit_gas_below_hdp(
    lenders,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(["addQuoteToken"]):
        txes = []
        for i in reversed(range(1000, 1020)):
            tx = mkr_dai_pool.addQuoteToken(
                lenders[0],
                100 * 10**18,
                bucket_math.indexToPrice(i),
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
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):
    with test_utils.GasWatcher(["addQuoteToken"]):
        txes = []
        for i in range(1000, 1020):
            tx = mkr_dai_pool.addQuoteToken(
                lenders[0],
                100 * 10**18,
                bucket_math.indexToPrice(i),
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
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):

    with test_utils.GasWatcher(
        ["removeQuoteToken", "addCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        mkr_dai_pool.addQuoteToken(
            lender, 3_400 * 10**18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 3_400 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        mkr_dai_pool.addCollateral(100 * 10**18, {"from": borrower})
        mkr_dai_pool.borrow(3_000 * 10**18, 4000 * 10**18, {"from": borrower})

        # lender removes 1000 DAI
        tx = mkr_dai_pool.removeQuoteToken(
            lender, 1_000 * 10**18, bucket_math.indexToPrice(1663), {"from": lender}
        )

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
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):

    with test_utils.GasWatcher(
        ["removeQuoteToken", "addCollateral", "addQuoteToken", "borrow"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]

        mkr_dai_pool.addQuoteToken(
            lender, 5_000 * 10**18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 5_000 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 5_000 * 10**18, bucket_math.indexToPrice(1524), {"from": lender}
        )

        # borrower takes a loan of 3000 DAI
        mkr_dai_pool.addCollateral(100 * 10**18, {"from": borrower})
        mkr_dai_pool.borrow(3_000 * 10**18, 4000 * 10**18, {"from": borrower})

        # lender removes 1000 DAI
        tx = mkr_dai_pool.removeQuoteToken(
            lender, 1_000 * 10**18, bucket_math.indexToPrice(1606), {"from": lender}
        )

        with capsys.disabled():
            print("\n==================================")
            print("Gas estimations:")
            print("==================================")
            print(
                f"Remove quote token below lup            - {test_utils.get_usage(tx.gas_used)}"
            )
