import brownie
from brownie import Contract
import pytest
import inspect


def test_add_remove_collateral(lenders, borrowers, mkr_dai_pool, dai, mkr):
    lender = lenders[0]
    mkr_dai_pool.addQuoteToken(lender, 20_000 * 1e18, 5000 * 1e18, {"from": lender})

    borrower1 = borrowers[0]

    # remove collateral should fail if address not a borrower / no collateral deposited
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeCollateral(10 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/not-enough-collateral"

    # test deposit collateral
    assert mkr.balanceOf(borrower1) == 100 * 1e18
    tx = mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})
    assert mkr.balanceOf(borrower1) == 0
    assert mkr.balanceOf(mkr_dai_pool) == 100 * 1e18
    assert mkr_dai_pool.totalCollateral() == 100 * 1e18
    (
        _,
        _,
        deposited,
        encumbered,
        _,
        _,
        _,
    ) = mkr_dai_pool.getBorrowerInfo(borrower1)
    assert deposited == 100 * 1e18
    assert encumbered == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["from"] == borrower1
    assert transfer_event["to"] == mkr_dai_pool
    assert transfer_event["value"] == 100 * 1e18
    pool_event = tx.events["AddCollateral"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["amount"] == 100 * 1e18

    # get loan
    mkr_dai_pool.borrow(20_000 * 1e18, 2500 * 1e18, {"from": borrower1})
    (
        _,
        _,
        deposited,
        encumbered,
        _,
        _,
        _,
    ) = mkr_dai_pool.getBorrowerInfo(borrower1)
    assert deposited == 100 * 1e18
    assert encumbered == 4 * 1e18
    # test remove collateral
    # should fail if trying to remove all collateral deposited
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeCollateral(100 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-collateral"
    # payback entire loan and accumulated debt
    dai.transfer(borrower1, 20_000 * 1e18, {"from": lender})
    mkr_dai_pool.repay(20_001 * 1e18, {"from": borrower1})
    tx = mkr_dai_pool.removeCollateral(100 * 1e18, {"from": borrower1})
    assert mkr.balanceOf(borrower1) == 100 * 1e18
    assert mkr.balanceOf(mkr_dai_pool) == 0
    assert mkr_dai_pool.totalCollateral() == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["from"] == mkr_dai_pool
    assert transfer_event["to"] == borrower1
    assert transfer_event["value"] == 100 * 1e18
    pool_event = tx.events["RemoveCollateral"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["amount"] == 100 * 1e18
    (
        _,
        _,
        deposited,
        encumbered,
        _,
        _,
        _,
    ) = mkr_dai_pool.getBorrowerInfo(borrower1)
    assert deposited == 0
    assert encumbered == 0


def test_collateral_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    capsys,
    test_utils
):
    with test_utils.GasWatcher(['addQuoteToken', 'removeCollateral']):
        mkr_dai_pool.addQuoteToken(lenders[0], 20_000 * 1e18, 5000 * 1e18, {"from": lenders[0]})
        tx_add_collateral = mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[0]})
        mkr_dai_pool.borrow(20_000 * 1e18, 2500 * 1e18, {"from": borrowers[0]})
        tx_remove_collateral = mkr_dai_pool.removeCollateral(
            10 * 1e18, {"from": borrowers[0]}
        )
        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
            print(
               f"Add collateral          - {test_utils.get_usage(tx_add_collateral.gas_used)}\n"
               f"Remove collateral       - {test_utils.get_usage(tx_remove_collateral.gas_used)}"
            )

            assert True
