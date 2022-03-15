import brownie
from brownie import Contract
import pytest
from decimal import *


def test_quote_removal_no_loan(
    lenders,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 10_000 * 1e18
    assert dai.balanceOf(lender) == 190_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 10_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 10_000 * 1e18

    # should fail if trying to remove more than lended
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(20_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/lended-amount-excedeed"

    # forward time so lp tokens to accumulate
    chain.sleep(82000)
    chain.mine()

    # remove 10000 DAI at price of 1 MKR = 4000 DAI
    tx = mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 0
    assert dai.balanceOf(lender) == 200_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 0
    assert mkr_dai_pool.totalQuoteToken() == 0
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        _,
        snapshot,
        lpOutstanding,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 0
    assert snapshot == 1 * 1e18
    assert lpOutstanding == 0
    (amount, lp) = mkr_dai_pool.lenders(lender, 4000 * 1e18)
    assert amount == 0

    # bucket wasn't used so lender won't receive lp tokens
    assert lp == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 10_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18


def test_quote_removal_loan_not_paid_back(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]
    borrower = borrowers[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 10_000 * 1e18
    assert dai.balanceOf(lender) == 190_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 10_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 10_000 * 1e18
    (amount, lp) = mkr_dai_pool.lenders(lender, 4000 * 1e18)
    assert amount == 10_000 * 1e18
    assert lp == 10_000 * 1e18

    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(5_000 * 1e18, 4000 * 1e18, {"from": borrower})

    # should fail if trying to remove entire amount lended
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/amount-greater-than-claimable"

    # should fail if trying to remove remaining lend ignoring the accumulated debt
    with pytest.raises(brownie.exceptions.VirtualMachineError) as exc:
        mkr_dai_pool.removeQuoteToken(5_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert exc.value.revert_msg == "ajna/amount-greater-than-claimable"

    # remove 4000 DAI at price of 1 MKR = 4000 DAI
    tx = mkr_dai_pool.removeQuoteToken(4_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert dai.balanceOf(mkr_dai_pool) == 1_000 * 1e18
    assert dai.balanceOf(lender) == 194_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 6_000 * 1e18
    assert mkr_dai_pool.totalQuoteToken() == 6_000 * 1e18
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        _,
        _,
        lpOutstanding,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 6_000 * 1e18
    assert lpOutstanding == 6_000 * 1e18
    (amount, lp) = mkr_dai_pool.lenders(lender, 4000 * 1e18)
    assert amount == 6_000 * 1e18
    assert lp == 6_000 * 1e18
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 4_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 4_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18


def test_quote_removal_loan_paid_back(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    chain,
):

    lender = lenders[0]
    borrower = borrowers[0]

    # deposit 10000 DAI at price of 1 MKR = 4000 DAI
    mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})

    mkr_dai_pool.addCollateral(100 * 1e18, {"from": borrower})
    mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower})

    dai.transfer(borrower, 1 * 1e18, {"from": lenders[1]})
    mkr_dai_pool.repay(10_001 * 1e18, {"from": borrower})

    # forward time so lp tokens to accumulate
    chain.sleep(82000)
    chain.mine()

    # remove all lended amount
    tx = mkr_dai_pool.removeQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert format(dai.balanceOf(mkr_dai_pool) / 1e18, ".3f") == format(0, ".3f")
    assert dai.balanceOf(lender) == 200_000 * 1e18
    assert mkr_dai_pool.lenderBalance(lender) == 0
    assert mkr_dai_pool.totalQuoteToken() == 0
    # check bucket balance
    (
        _,
        _,
        _,
        bucket_deposit,
        _,
        _,
        lpOutstanding,
    ) = mkr_dai_pool.bucketAt(4000 * 1e18)
    assert bucket_deposit == 0
    assert lpOutstanding == 0
    (amount, lp) = mkr_dai_pool.lenders(lender, 4000 * 1e18)
    assert amount == 0
    assert lp == 0
    # check tx events
    transfer_event = tx.events["Transfer"][0][0]
    assert transfer_event["src"] == mkr_dai_pool
    assert transfer_event["dst"] == lender
    assert transfer_event["wad"] == 10_000 * 1e18
    pool_event = tx.events["RemoveQuoteToken"][0][0]
    assert pool_event["amount"] == 10_000 * 1e18
    assert pool_event["lender"] == lender
    assert pool_event["price"] == 4000 * 1e18
