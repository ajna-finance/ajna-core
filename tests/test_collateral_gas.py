import brownie
import pytest
import inspect
from conftest import ZRO_ADD
from brownie import Contract

def test_add_remove_collateral_gas(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(["addQuoteToken", "pledgeCollateral", "removeCollateral"]):
        scaled_pool.addQuoteToken(20_000 * 10**18, 1708, {"from": lenders[0]})
        tx_add_collateral = scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        scaled_pool.borrow(20_000 * 10**18, 2500 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        tx_remove_collateral = scaled_pool.removeCollateral(10 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrowers[0]})
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
                f"Add collateral          - {test_utils.get_usage(tx_add_collateral.gas_used)}\n"
                f"Remove collateral       - {test_utils.get_usage(tx_remove_collateral.gas_used)}"
            )

@pytest.mark.skip
def test_claim_collateral_gas(
    lenders,
    borrowers,
    scaled_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(
        ["addQuoteToken", "pledgeCollateral", "borrow", "purchaseBid", "claimCollateral"]
    ):
        lender = lenders[0]
        borrower = borrowers[0]
        bidder = borrowers[1]

        # deposit DAI in 3 buckets
        scaled_pool.addQuoteToken(
            3_000 * 10**18, 1663, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            4_000 * 10**18, 1606, {"from": lender}
        )
        scaled_pool.addQuoteToken(
            5_000 * 10**18, 1386, {"from": lender}
        )

        scaled_pool.pledgeCollateral(100 * 10**18, ZRO_ADD, ZRO_ADD, {"from": borrower})
        scaled_pool.borrow(4_000 * 10**18, 3000 * 10**18,ZRO_ADD, ZRO_ADD, {"from": borrower})

        # bidder purchases some of the middle bucket
        scaled_pool.purchaseQuote(
            1_500 * 10**18, 1606, {"from": bidder}
        )

        tx = scaled_pool.claimCollateral(
            0.004 * 10**18, 1606, {"from": lender}
        )
        assert 1 == 0

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(f"Claim collateral           - {test_utils.get_usage(tx.gas_used)}")
            print("==================================")
