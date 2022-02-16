import brownie
from brownie import Contract
import pytest


def test_quote_deposit(
    lenders,
    mkr_dai_pool,
    dai,
    mkr,
):

    lender = lenders[0]
    # revert when depositing at invalid price
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.addQuoteToken(100000 * 1e18, 8000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/invalid-bucket-price"

    assert mkr_dai_pool.hup() == 0

    # test 10000 DAI deposit at price of 1 MKR = 4000 DAI
    tx = mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    # check pool balance
    assert mkr_dai_pool.lenders(lender, 4000 * 1e18) == 10_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 10_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 10_000 * 1e18
    assert mkr_dai_pool.hup() == 4000 * 1e18
    # check bucket balance
    (
        bucket_price,
        bucket_next_price,
        bucket_deposit,
        bucket_debt,
    ) = mkr_dai_pool.buckets(4000 * 1e18)
    assert bucket_price == 4000 * 1e18
    assert bucket_next_price == 0
    assert bucket_deposit == 10_000 * 1e18
    assert bucket_debt == 0
    # check tokens transfered
    assert dai.balanceOf(mkr_dai_pool) == 10_000 * 1e18
    assert dai.balanceOf(lender) == 190_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == lender
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["AddQuoteToken"][0][0]
    assert pool_event["amount"] == 10_000 * 1e18
    assert pool_event["hup"] == 4000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18

    # test 20000 DAI deposit at price of 1 MKR = 2000 DAI
    # hup should remain same 4000 DAI and hup next price should be updated from 0 to 2000 DAI
    tx = mkr_dai_pool.addQuoteToken(20_000 * 1e18, 2000 * 1e18, {"from": lender})
    # check pool balance
    assert mkr_dai_pool.lenders(lender, 2000 * 1e18) == 20_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 30_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 30_000 * 1e18
    assert mkr_dai_pool.hup() == 4000 * 1e18
    # check new bucket balance
    (
        bucket_price,
        bucket_next_price,
        bucket_deposit,
        bucket_debt,
    ) = mkr_dai_pool.buckets(2000 * 1e18)
    assert bucket_price == 2000 * 1e18
    assert bucket_next_price == 0
    assert bucket_deposit == 20_000 * 1e18
    assert bucket_debt == 0
    # check hup next price pointer updated
    (
        _,
        hup_next_price,
        _,
        _,
    ) = mkr_dai_pool.buckets(4000 * 1e18)
    assert hup_next_price == 2000 * 1e18
    # check tokens transfered
    assert dai.balanceOf(mkr_dai_pool) == 30_000 * 1e18
    assert dai.balanceOf(lender) == 170_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == lender
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 20_000 * 1e18
    pool_event = tx.events["AddQuoteToken"][0][0]
    assert pool_event["amount"] == 20_000 * 1e18
    assert pool_event["hup"] == 4000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 2000 * 1e18

    # test 30000 DAI deposit at price of 1 MKR = 3000 DAI
    # hup should remain same 4000 DAI and hup next price should be updated from 2000 to 3000 DAI
    # next price for 3000 DAI bucket should be 2000 DAI
    tx = mkr_dai_pool.addQuoteToken(30_000 * 1e18, 3000 * 1e18, {"from": lender})
    # check pool balance
    assert mkr_dai_pool.lenders(lender, 3000 * 1e18) == 30_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 60_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 60_000 * 1e18
    assert mkr_dai_pool.hup() == 4000 * 1e18
    # check new bucket balance
    (
        bucket_price,
        bucket_next_price,
        bucket_deposit,
        bucket_debt,
    ) = mkr_dai_pool.buckets(3000 * 1e18)
    assert bucket_price == 3000 * 1e18
    assert bucket_next_price == 2000 * 1e18
    assert bucket_deposit == 30_000 * 1e18
    assert bucket_debt == 0
    # check hup bucket next price pointer updated
    (
        _,
        hup_next_price,
        _,
        _,
    ) = mkr_dai_pool.buckets(4000 * 1e18)
    assert hup_next_price == 3000 * 1e18
    # check tokens transfered
    assert dai.balanceOf(mkr_dai_pool) == 60_000 * 1e18
    assert dai.balanceOf(lender) == 140_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == lender
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 30_000 * 1e18
    pool_event = tx.events["AddQuoteToken"][0][0]
    assert pool_event["amount"] == 30_000 * 1e18
    assert pool_event["hup"] == 4000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 3000 * 1e18

    # test 40000 DAI deposit at price of 1 MKR = 5000 DAI
    # hup should be updated to 5000 DAI and hup next price should be 4000 DAI
    tx = mkr_dai_pool.addQuoteToken(40_000 * 1e18, 5000 * 1e18, {"from": lender})
    # check pool balance
    assert mkr_dai_pool.lenders(lender, 5000 * 1e18) == 40_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 100_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 100_000 * 1e18
    assert mkr_dai_pool.hup() == 5000 * 1e18
    # check new bucket balance
    (
        bucket_price,
        bucket_next_price,
        bucket_deposit,
        bucket_debt,
    ) = mkr_dai_pool.buckets(5000 * 1e18)
    assert bucket_price == 5000 * 1e18
    assert bucket_next_price == 4000 * 1e18
    assert bucket_deposit == 40_000 * 1e18
    assert bucket_debt == 0
    # check tokens transfered
    assert dai.balanceOf(mkr_dai_pool) == 100_000 * 1e18
    assert dai.balanceOf(lender) == 100_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == lender
    assert transfer_event["dst"] == mkr_dai_pool
    assert transfer_event["wad"] == 40_000 * 1e18
    pool_event = tx.events["AddQuoteToken"][0][0]
    assert pool_event["amount"] == 40_000 * 1e18
    assert pool_event["hup"] == 5000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 5000 * 1e18


def test_quote_deposit_gas_below_hup(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
):
    txes = []
    for i in range(20):
        tx = mkr_dai_pool.addQuoteToken(
            100 * 1e18, (4000 - 10 * i) * 1e18, {"from": lenders[0]}
        )
        txes.append(tx)
    with capsys.disabled():
        print("\n==================================")
        print("Gas estimations (deposit below hup):")
        print("==================================")
        for i in range(len(txes)):
            print(f"Transaction: {i} | Gas used: {str(txes[i].gas_used)}")
        print("==================================")
    assert True


def test_quote_deposit_gas_above_hup(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    capsys,
):
    txes = []
    for i in range(20):
        tx = mkr_dai_pool.addQuoteToken(
            100 * 1e18, (2000 + 10 * i) * 1e18, {"from": lenders[0]}
        )
        txes.append(tx)
    with capsys.disabled():
        print("\n==================================")
        print("Gas estimations (deposit above hup):")
        print("==================================")
        for i in range(len(txes)):
            print(f"Transaction: {i} | Gas used: {str(txes[i].gas_used)}")
        print("==================================")
    assert True
