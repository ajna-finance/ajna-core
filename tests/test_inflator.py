import brownie
from brownie import Contract
import pytest
from decimal import *


def test_inflator(
    lenders,
    borrowers,
    mkr_dai_pool,
    dai,
    mkr,
    chain,
):

    lender = lenders[0]
    borrower1 = borrowers[0]

    assert mkr_dai_pool.inflatorSnapshot() == 1 * 1e18

    # check inflator update on quote token deposit
    tx = mkr_dai_pool.addQuoteToken(10_000 * 1e18, 4000 * 1e18, {"from": lender})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert Decimal(mkr_dai_pool.inflatorSnapshot()) == calculate_inflator(
        mkr_dai_pool, tx.timestamp
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on collateral deposit
    tx = mkr_dai_pool.addCollateral(10 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert Decimal(mkr_dai_pool.inflatorSnapshot()) == calculate_inflator(
        mkr_dai_pool, tx.timestamp
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on loan
    tx = mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert Decimal(mkr_dai_pool.inflatorSnapshot()) == calculate_inflator(
        mkr_dai_pool, tx.timestamp
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on repay
    tx = mkr_dai_pool.repay(1_000 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert Decimal(mkr_dai_pool.inflatorSnapshot()) == calculate_inflator(
        mkr_dai_pool, tx.timestamp
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on collateral remove
    tx = mkr_dai_pool.removeCollateral(1 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert Decimal(mkr_dai_pool.inflatorSnapshot()) == calculate_inflator(
        mkr_dai_pool, tx.timestamp
    )


def calculate_inflator(mkr_dai_pool, block_time):
    secs_elapsed = block_time - mkr_dai_pool.lastBorrowerInflatorUpdate()
    spr = Decimal(mkr_dai_pool.previousRate()) / (3600 * 24 * 365)

    return Decimal(mkr_dai_pool.inflatorSnapshot() * (1 + spr * secs_elapsed))
