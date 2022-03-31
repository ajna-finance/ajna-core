import brownie
import pytest
import random
from decimal import *
from sdk import AjnaPoolClient


@pytest.fixture
def pool_client(ajna_protocol, weth, dai):
    return ajna_protocol.get_pool(weth.address, dai.address)


@pytest.fixture
def lenders(ajna_protocol, pool_client, weth_dai_pool):
    dai_client = pool_client.get_quote_token()
    amount = 200_000 * 1e18
    lenders = []
    for _ in range(100):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, amount)
        dai_client.approve_max(weth_dai_pool, lender)
        lenders.append(lender)
    return lenders


@pytest.fixture
def borrowers(ajna_protocol, pool_client, weth_dai_pool):
    weth_client = pool_client.get_collateral_token()
    amount = 67 * 1e18
    dai_client = pool_client.get_quote_token()
    borrowers = []
    for _ in range(100):
        borrower = ajna_protocol.add_borrower()
        weth_client.top_up(borrower, amount)
        weth_client.approve_max(weth_dai_pool, borrower)
        dai_client.approve_max(weth_dai_pool, borrower)
        assert weth_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)

    return borrowers


def add_initial_liquidity(lenders, pool_client, bucket_math):
    # reserve first 10 lenders for after initialization
    for i in range(10, len(lenders)-1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4)+1):
            place_random_bid(i, pool_client, bucket_math)


MIN_BUCKET = 1543  # 2210.03602
MAX_BUCKET = 1623  # 3293.70191


def place_random_bid(lender_index, pool_client, bucket_math):
    price_count = MAX_BUCKET - MIN_BUCKET
    price_position = 1 - random.expovariate(lambd=7.5)

    price_index = max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    price = bucket_math.indexToPrice(price_index)
    print(f"placing 60k bid from lender {lender_index} at {price/1e18:>9.3f}")
    pool_client.deposit_quote_token(60_000 * 1e18, price, lender_index)


def draw_initial_debt(borrowers, pool_client, target_utilization=0.6, limit_price=2210.03602 * 1e18):
    pool = pool_client.get_contract()
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(10, len(borrowers) - 1):
        # TODO: Deposit collateral into contract
        amount = 30_000 * 1e18
        print(f"borrower {borrower_index} borrowing 30k down to {limit_price/1e18:>9.3f}")
        tx = pool_client.borrow(amount, borrower_index, 0)


def test_stable_volatile_one(pool_client, weth_dai_pool, dai, weth, lenders, borrowers, bucket_math, test_utils):
    assert weth_dai_pool.collateral() == weth
    assert weth_dai_pool.quoteToken() == dai

    assert len(lenders) == 100
    assert len(borrowers) == 100
    assert weth.balanceOf(borrowers[0]) >= 67 * 1e18

    # test setup
    add_initial_liquidity(lenders, pool_client, bucket_math)
    assert weth_dai_pool.totalQuoteToken() > 5_400_000 * 1e18
    print(test_utils.dump_book(weth_dai_pool, bucket_math, MIN_BUCKET, MAX_BUCKET))
    # draw_initial_debt(borrowers, pool_client)
    # assert weth_dai_pool.getPoolActualUtilization() > 0.10 * 1e18
