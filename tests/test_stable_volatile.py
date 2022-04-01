import brownie
import pytest
import random
from decimal import *
from sdk import AjnaPoolClient


MIN_BUCKET = 1543  # 2210.03602
MAX_BUCKET = 1623  # 3293.70191


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


@pytest.fixture  # TODO: (scope="session")
def pool1(pool_client, dai, weth, lenders, borrowers, bucket_math):
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool_client, bucket_math)
    draw_initial_debt(borrowers, pool_client)
    return pool_client.get_contract()


def add_initial_liquidity(lenders, pool_client, bucket_math):
    # Lenders 10-99 add liquidity; lenders 0-9 reserved for the actual test
    for i in range(10, len(lenders)-1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4)+1):
            place_random_bid(i, pool_client, bucket_math)


def place_random_bid(lender_index, pool_client, bucket_math):
    price_count = MAX_BUCKET - MIN_BUCKET
    price_position = 1 - random.expovariate(lambd=7.5)

    price_index = max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    price = bucket_math.indexToPrice(price_index)
    pool_client.deposit_quote_token(60_000 * 1e18, price, lender_index)


def draw_initial_debt(borrowers, pool_client, target_utilization=0.6, limit_price=2210.03602 * 1e18):
    # Borrowers 10-99 draw debt; borrowers 0-9 reserved for the actual test
    pool = pool_client.get_contract()
    weth = pool_client.get_collateral_token().get_contract()
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(10, len(borrowers) - 1):
        collateral_balance = weth.balanceOf(borrowers[borrower_index])
        pool_client.deposit_collateral(collateral_balance, borrower_index)
        borrow_amount = target_debt / 90
        pool_client.borrow(borrow_amount, borrower_index, 0)


def test_stable_volatile_one(pool1, dai, weth, lenders, borrowers, bucket_math, test_utils):
    assert pool1.collateral() == weth
    assert pool1.quoteToken() == dai

    assert len(lenders) == 100
    assert len(borrowers) == 100
    assert weth.balanceOf(borrowers[0]) >= 67 * 1e18

    print(test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, MAX_BUCKET))
    print(f"actual utilization: {pool1.getPoolActualUtilization()/1e18}")
    assert pool1.totalQuoteToken() > 2_700_000 * 1e18  # 50% utilization
    assert pool1.getPoolActualUtilization() > 0.50 * 1e18

    # assert False
