import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect


def test_update_interest_rate_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
    bucket_math,
):

    with test_utils.GasWatcher(
        ["addQuoteToken", "addCollateral", "borrow", "updateInterestRate"]
    ):
        lender = lenders[0]
        borrower1 = borrowers[0]

        # raise pool utilization
        # lender deposits 10000 DAI in 3 buckets each
        mkr_dai_pool.addQuoteToken(
            lender, 10_000 * 1e18, bucket_math.indexToPrice(1663), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 10_000 * 1e18, bucket_math.indexToPrice(1637), {"from": lender}
        )
        mkr_dai_pool.addQuoteToken(
            lender, 10_000 * 1e18, bucket_math.indexToPrice(1569), {"from": lender}
        )

        # borrower deposits 100 MKR collateral and draws debt
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})
        mkr_dai_pool.borrow(25_000 * 1e18, 2500 * 1e18, {"from": borrower1})

        tx = mkr_dai_pool.updateInterestRate({"from": lender})

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Update interest rate           - {test_utils.get_usage(tx.gas_used)}"
            )
            print("==================================")
