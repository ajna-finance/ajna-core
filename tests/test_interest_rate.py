import brownie
from brownie import Contract
import pytest
from decimal import *
import inspect

def test_update_interest_rate(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils,
):

    with test_utils.GasWatcher():
        lender = lenders[0]
        borrower1 = borrowers[0]

        assert mkr_dai_pool.previousRate() == 0.05 * 1e18
        update_time = mkr_dai_pool.previousRateUpdate()

        # should silently not update when actual utilization is 0
        tx = mkr_dai_pool.updateInterestRate({"from": lender})
        assert tx.status.value == 1
        assert mkr_dai_pool.previousRate() == 0.05 * 1e18
        assert mkr_dai_pool.previousRateUpdate() == update_time

        # raise pool utilization
        # lender deposits 10000 DAI in 3 buckets each
        mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3500 * 1e18, {"from": lender})
        mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3000 * 1e18, {"from": lender})

        # borrower deposits 100 MKR collateral and draws debt
        mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})
        mkr_dai_pool.borrow(25_000 * 1e18, 2500 * 1e18, {"from": borrower1})

        assert mkr_dai_pool.getPoolActualUtilization() == 833333333333333333
        assert mkr_dai_pool.getPoolTargetUtilization() == 83333333333333333

        tx = mkr_dai_pool.updateInterestRate({"from": lender})
        assert tx.status.value == 1
        # TODO: In Forge tests, please skip and compare the rate
        # assert compare_first_16_digits(
        #     Decimal(mkr_dai_pool.previousRate()), Decimal(87500000000000000)
        # )
        assert Decimal(0.0874) < mkr_dai_pool.previousRate() * 1e-18 < Decimal(0.0876)
        assert mkr_dai_pool.previousRateUpdate() == tx.timestamp
        assert mkr_dai_pool.lastInflatorSnapshotUpdate() == tx.timestamp

        pool_event = tx.events["UpdateInterestRate"][0][0]
        assert pool_event["oldRate"] == 0.05 * 1e18
        # assert compare_first_16_digits(pool_event["newRate"], Decimal(87500000000000000))
        assert Decimal(0.0874) < pool_event["newRate"] * 1e-18 < Decimal(0.0876)

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Update interest rate           - {test_utils.get_usage(tx.gas_used)}"
            )
            print("==================================")


def compare_first_16_digits(number_1: Decimal, number_2: Decimal) -> bool:
    return int(str(number_1)[:16]) == int(str(number_2)[:16])
