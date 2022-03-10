from multiprocessing import pool
import brownie
from brownie import Contract
import pytest


def test_repay(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    chain,
):
    lender = lenders[0]
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 5000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3000 * 1e18, {"from": lender})

    borrower1 = borrowers[0]
    # borrower starts with 10000 DAI and deposit 100 collateral
    dai.transfer(borrower1, 10_000 * 1e18, {"from": lender})
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})
    assert mkr.balanceOf(borrower1) == 0

    # should fail if no debt
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.repay(10_000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/no-debt-to-repay"

    # take loan of 25000 DAI from 3 buckets
    mkr_dai_pool.borrow(25_000 * 1e18, 2500 * 1e18, {"from": borrower1})
    assert format(mkr_dai_pool.encumberedCollateral() / 1e18, ".2f") == format(
        6.166666666666666667, ".2f"
    )

    # should fail if amount not available
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.repay(50_000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/no-funds-to-repay"

    (
        debt,
        _,
        _,
    ) = mkr_dai_pool.borrowers(borrower1)
    assert debt == 25_000 * 1e18
    assert mkr_dai_pool.totalDebt() == 25_000 * 1e18
    assert mkr_dai_pool.lup() == 3_000 * 1e18
    assert dai.balanceOf(borrower1) == 35_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 5_000 * 1e18

    # repay partially 10000 DAI
    chain.sleep(8200)
    chain.mine()
    tx = mkr_dai_pool.repay(10_000 * 1e18, {"from": borrower1})
    (
        debt,
        _,
        _,
    ) = mkr_dai_pool.borrowers(borrower1)
    assert debt == 15_000 * 1e18
    assert round(mkr_dai_pool.totalDebt() * 1e-18, 3) == 15000.325
    assert mkr_dai_pool.lup() == 4_000 * 1e18
    assert dai.balanceOf(borrower1) == 25_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 15_000 * 1e18
    assert format(mkr_dai_pool.encumberedCollateral() / 1e18, ".2f") == format(
        3.250080182705945727, ".2f"
    )
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == borrower1
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["Repay"][0][0]
    print(pool_event)
    assert pool_event["borrower"] == borrower1
    assert pool_event["price"] == 4_000 * 1e18
    assert pool_event["amount"] == 10_000 * 1e18

    # repay remaining 15000 DAI plus accumulated debt
    chain.sleep(8200)
    chain.mine()
    tx = mkr_dai_pool.repay(16_000 * 1e18, {"from": borrower1})
    (
        debt,
        deposited,
        snapshot,
    ) = mkr_dai_pool.borrowers(borrower1)
    assert deposited == 100 * 1e18
    assert snapshot == 0
    assert debt == 0
    # TODO: fix repay and reconciliate the remaining amount - assert mkr_dai_pool.totalDebt() == 0
    assert mkr_dai_pool.lup() == 5_000 * 1e18
    # TODO: reconciliate remaining amount
    assert format(mkr_dai_pool.encumberedCollateral() / 1e18, ".6f") == format(
        0.000122427819371403, ".6f"
    )
    # borrower remains with initial 10000 DAI minus debt paid to pool
    assert dai.balanceOf(borrower1) == 10_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 30_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == borrower1
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 15_000 * 1e18
    pool_event = tx.events["Repay"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["price"] == 5_000 * 1e18
    assert pool_event["amount"] == 15_000 * 1e18

    mkr_dai_pool.removeCollateral(100 * 1e18, {"from": borrower1})
    assert mkr.balanceOf(borrower1) == 100 * 1e18


def test_repay_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    capsys,
    test_utils,
):
    for i in range(12):
        mkr_dai_pool.addQuoteToken(
            10_000 * 1e18, (4000 - 10 * i) * 1e18, {"from": lenders[0]}
        )

    # borrower starts with 10000 DAI and deposit 100 collateral
    dai.transfer(borrowers[0], 10_000 * 1e18, {"from": lenders[0]})
    assert dai.balanceOf(borrowers[0]) == 10_000 * 1e18
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[0]})

    # borrow 10_000 DAI from single bucket (LUP)
    mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrowers[0]})
    assert dai.balanceOf(borrowers[0]) == 20_000 * 1e18
    tx_repay_to_one_bucket = mkr_dai_pool.repay(10_001 * 1e18, {"from": borrowers[0]})

    # borrow 101_000 DAI from 11 buckets
    mkr_dai_pool.borrow(101_000 * 1e18, 1000 * 1e18, {"from": borrowers[0]})
    tx_repay_to_11_buckets = mkr_dai_pool.repay(101_001 * 1e18, {"from": borrowers[0]})

    with capsys.disabled():
        print("\n==================================")
        print("Gas estimations:")
        print("==================================")
        print(
            f"Repay single bucket          - {test_utils.get_gas_usage(tx_repay_to_one_bucket.gas_used)}\n"
            f"Repay multiple buckets (11)  - {test_utils.get_gas_usage(tx_repay_to_11_buckets.gas_used)}"
        )
        print("==================================")
    assert True
