import brownie
import pytest
from decimal import *


@pytest.fixture
def lenders(ajna_protocol, weth_dai_pool, weth, dai):
    pool_client = ajna_protocol.get_pool(weth.address, dai.address)
    dai_client = pool_client.get_quote_token()
    amount = 200_000 * 10e18
    lenders = []
    for _ in range(100):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, amount)
        dai_client.approve_max(weth_dai_pool, lender)
        lenders.append(lender)
    return lenders


@pytest.fixture
def borrowers(ajna_protocol, weth_dai_pool, weth, dai):
    pool_client = ajna_protocol.get_pool(weth.address, dai.address)
    weth_client = pool_client.get_collateral_token()
    amount = 67 * 10e18
    dai_client = pool_client.get_quote_token()
    borrowers = []
    for _ in range(100):
        borrower = ajna_protocol.add_borrower()
        weth_client.top_up(borrower, amount)
        weth_client.approve_max(weth_dai_pool, borrower)
        dai_client.approve_max(weth_dai_pool, borrower)
        borrowers.append(borrower)

    return borrowers


def test_stable_volatile_one(weth_dai_pool, dai, weth, lenders, borrowers):
    assert weth_dai_pool.collateral() == weth
    assert weth_dai_pool.quoteToken() == dai

    assert len(lenders) == 100
    assert len(borrowers) == 100
