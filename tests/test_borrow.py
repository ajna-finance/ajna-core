import brownie
from brownie import Contract
import pytest


def test_borrow(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
):

    lender = lenders[0]
    borrower1 = borrowers[0]

    # lender deposits 10000 DAI in 5 buckets each
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3500 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 3000 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 2500 * 1e18, {"from": lender})
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 2000 * 1e18, {"from": lender})

    # check pool balance
    assert mkr_dai_pool.totalQuoteToken() == 50_000 * 1e18
    assert mkr_dai_pool.hup() == 4000 * 1e18

    # should fail if borrower wants to borrow a greater amount than in pool
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(60_000 * 1e18, 2000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-liquidity"

    # should fail if not enough collateral deposited by borrower
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/not-enough-collateral"

    # borrower deposit 100 MKR collateral
    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower1})

    # should fail if stop price exceeded
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.borrow(15_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert exc.value.revert_msg == "ajna/stop-price-exceeded"

    # get 21000 DAI loan from 3 buckets
    # loan price should be 3000 DAI
    assert 3000 * 1e18 == mkr_dai_pool.estimatePriceForLoan(21_000 * 1e18)
    tx = mkr_dai_pool.borrow(21_000 * 1e18, 2500 * 1e18, {"from": borrower1})

    assert dai.balanceOf(borrower1) == 21_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 29_000 * 1e18
    assert mkr_dai_pool.hup() == 3000 * 1e18
    assert mkr_dai_pool.onDeposit() == 9_000 * 1e18
    assert mkr_dai_pool.totalDebt() == 21_000 * 1e18
    assert mkr_dai_pool.totalEncumberedCollateral() == (21_000 / 3000) * 1e18
    # check borrower
    (debt, col_deposited, col_encumbered) = mkr_dai_pool.borrowers(borrower1)
    assert debt == 21_000 * 1e18
    assert col_deposited == 100 * 1e18
    # collateral encumbered at last price, that is 3000 DAI
    assert col_encumbered == (21_000 / 3000) * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == borrower1
    assert transfer_event["wad"] == 21_000 * 1e18
    pool_event = tx.events["Borrow"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["price"] == 3000 * 1e18
    assert pool_event["amount"] == 21_000 * 1e18

    # borrow remaining 9000 DAI from HUP
    tx = mkr_dai_pool.borrow(9_000 * 1e18, 3000 * 1e18, {"from": borrower1})

    assert dai.balanceOf(borrower1) == 30_000 * 1e18
    assert dai.balanceOf(mkr_dai_pool) == 20_000 * 1e18
    assert mkr_dai_pool.hup() == 3000 * 1e18
    assert mkr_dai_pool.onDeposit() == 0
    assert mkr_dai_pool.totalDebt() == 30_000 * 1e18
    assert mkr_dai_pool.totalEncumberedCollateral() == (30_000 / 3000) * 1e18
    # check borrower
    (debt, col_deposited, col_encumbered) = mkr_dai_pool.borrowers(borrower1)
    assert debt == 30_000 * 1e18
    assert col_deposited == 100 * 1e18
    # collateral encumbered at last price, that is 3000 DAI
    assert col_encumbered == (30_000 / 3000) * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == borrower1
    assert transfer_event["wad"] == 9_000 * 1e18
    pool_event = tx.events["Borrow"][0][0]
    assert pool_event["borrower"] == borrower1
    assert pool_event["price"] == 3000 * 1e18
    assert pool_event["amount"] == 9_000 * 1e18


def test_borrow_gas(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
    test_utils,
):
    txes = []
    for i in range(12):
        mkr_dai_pool.addQuoteToken(
            10_000 * 1e18, (4000 - 10 * i) * 1e18, {"from": lenders[0]}
        )

    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrowers[0]})

    # borrow 10_000 DAI from single bucket (HUP)
    tx_one_bucket = mkr_dai_pool.borrow(
        10_000 * 1e18, 4000 * 1e18, {"from": borrowers[0]}
    )
    txes.append(tx_one_bucket)

    # borrow 101_000 DAI from 11 buckets
    tx_11_buckets = mkr_dai_pool.borrow(
        101_000 * 1e18, 1000 * 1e18, {"from": borrowers[0]}
    )
    txes.append(tx_11_buckets)

    with capsys.disabled():
        print("\n==================================")
        print("Gas estimations:")
        print("==================================")
        print(
            f"Borrow single bucket (HUP) - {test_utils.get_gas_usage(tx_one_bucket.gas_used)}"
        )
        print(
            f"Borrow multiple buckets 11 - {test_utils.get_gas_usage(tx_11_buckets.gas_used)}"
        )
        print("==================================")
    assert True
