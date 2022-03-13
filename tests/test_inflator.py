import brownie
from brownie import Contract
import pytest
from decimal import *


WAD = 10 ** 18

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
    assert compare_first_16_digits(
        Decimal(mkr_dai_pool.inflatorSnapshot()),
        calculate_inflator(mkr_dai_pool, tx.timestamp)
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on collateral deposit
    tx = mkr_dai_pool.addCollateral(10 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert compare_first_16_digits(
        Decimal(mkr_dai_pool.inflatorSnapshot()),
        calculate_inflator(mkr_dai_pool, tx.timestamp)
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on loan
    tx = mkr_dai_pool.borrow(10_000 * 1e18, 4000 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert compare_first_16_digits(
        Decimal(mkr_dai_pool.inflatorSnapshot()),
        calculate_inflator(mkr_dai_pool, tx.timestamp)
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on repay
    tx = mkr_dai_pool.repay(1_000 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert compare_first_16_digits(
        Decimal(mkr_dai_pool.inflatorSnapshot()),
        calculate_inflator(mkr_dai_pool, tx.timestamp)
    )

    chain.sleep(8200)
    chain.mine()
    # check inflator update on collateral remove
    tx = mkr_dai_pool.removeCollateral(1 * 1e18, {"from": borrower1})
    assert mkr_dai_pool.lastBorrowerInflatorUpdate() == tx.timestamp
    assert compare_first_16_digits(
        Decimal(mkr_dai_pool.inflatorSnapshot()),
        calculate_inflator(mkr_dai_pool, tx.timestamp)
    )

# account for slight precision loss between python math and solidity math
def compare_first_16_digits(number_1: Decimal, number_2: Decimal) -> bool:
    return int(str(number_1)[:16]) == int(str(number_2)[:16])

def calculate_inflator(mkr_dai_pool, block_time) -> Decimal:
    secs_elapsed = block_time - mkr_dai_pool.lastBorrowerInflatorUpdate()
    spr = int(mkr_dai_pool.previousRate() / (3600 * 24 * 365))

    return Decimal(mkr_dai_pool.inflatorSnapshot() * calculate_pending_inflator(spr, secs_elapsed))

def calculate_pending_inflator(spr: int, secs: int) -> int:
    assert isinstance(spr, int)
    assert isinstance(secs, int)

    return (((1 * WAD) + spr) / WAD) ** secs


def test_calculate_pending_inflator(mkr_dai_pool, chain):
    chain.sleep(8200)
    chain.mine()
    block_time = chain.time()

    secs_elapsed = block_time - mkr_dai_pool.lastBorrowerInflatorUpdate()
    secs_in_year = 3600 * 24 * 365
    spr = int(mkr_dai_pool.previousRate() / secs_in_year) # (secs_in_year * 10**18))
    print(f"prev rate: {mkr_dai_pool.previousRate()}")
    print(f"spr: {int(spr)}")
    print(f"secs_elapsed: {secs_elapsed}")

    inflator_py = calculate_pending_inflator(spr, secs_elapsed)
    print(f"python calculated inflator: {inflator_py}")
    
    assert mkr_dai_pool.getPendingInflator() > 0
    assert mkr_dai_pool.getPendingInflator() > calculate_pending_inflator(spr, secs_elapsed)
