import brownie
import inspect
import pytest
import random
from brownie import Contract
from decimal import *
from sdk import AjnaPoolClient, AjnaProtocol


MIN_BUCKET = 1543  # 2210.03602, lowest bucket involved in the test
MAX_BUCKET = 1623  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization


@pytest.fixture
def pool_client(ajna_protocol: AjnaProtocol, weth, dai) -> AjnaPoolClient:
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
    amount = 134 * 1e18
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
    seed = 1648932463
    for i in range(10, len(lenders)-1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4)+1):
            random.seed(seed)
            seed += 1
            place_random_bid(i, pool_client, bucket_math)


def place_random_bid(lender_index, pool_client, bucket_math):
    price_count = MAX_BUCKET - MIN_BUCKET
    price_position = 1 - random.expovariate(lambd=5.0)
    # print(f"price_position={price_position}, lambda=5.0")
    price_index = max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    price = bucket_math.indexToPrice(price_index)
    pool_client.deposit_quote_token(60_000 * 1e18, price, lender_index)


def draw_initial_debt(borrowers, pool_client, target_utilization=0.55, limit_price=2210.03602 * 1e18):
    # Borrowers 10-99 draw debt; borrowers 0-9 reserved for the actual test
    pool = pool_client.get_contract()
    weth = pool_client.get_collateral_token().get_contract()
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(10, len(borrowers) - 1):
        collateral_balance = weth.balanceOf(borrowers[borrower_index])
        pool_client.deposit_collateral(collateral_balance, borrower_index)
        borrow_amount = target_debt / 90
        assert borrow_amount > 1e18
        pool_client.borrow(borrow_amount, borrower_index, limit_price)


def draw_and_bid(lenders, borrowers, pool, weth, bucket_math, chain) -> dict:
    buckets_deposited = {}
    time_elapsed = 0
    for user_index in range(0, 10):
        draw_debt(borrowers[user_index], user_index, pool, weth)
        interval = (user_index + 1) * 360  # 6 minutes for user 0, 60 minutes for user 9
        chain.sleep(interval)
        time_elapsed += interval
        buckets_deposited[user_index] = add_quote_token(lenders[user_index], user_index, pool, bucket_math, chain)
        chain.sleep(interval)
        time_elapsed += interval
        if time_elapsed > 269 * 13.4:
            pool.updateInterestRate({"from": lenders[user_index]})
            time_elapsed = 0
    return buckets_deposited


def draw_debt(borrower, borrower_index, pool, weth, limit_price=2210.03602 * 1e18):
    # Deposit all their collateral
    collateral_balance = weth.balanceOf(borrower)
    assert collateral_balance > 1e18
    pool.addCollateral(collateral_balance, {"from": borrower})
    # Determine how much debt to draw
    collateral_to_utilize = ((borrower_index % 3) + 2.5) / 6 * collateral_balance
    borrow_amount = collateral_to_utilize * pool.getPoolPrice()/1e18
    print(f"borrower drawing {borrow_amount/1e18} debt utilizing {collateral_to_utilize/1e18} collateral")
    assert borrow_amount > 1e18
    pool.borrow(borrow_amount, limit_price, {"from": borrower})


def add_quote_token(lender, lender_index, pool, bucket_math, chain):
    # Lenders 0-10 add liquidity
    hpb = pool.hdp()
    hpb_index = bucket_math.priceToIndex(hpb)
    index_offset = ((lender_index % 6) - 2) * 2
    price = bucket_math.indexToPrice(hpb_index + index_offset)
    print(f"lender adding liquidity at {price / 1e18}")
    pool.addQuoteToken(lender, 200_000 * 1e18, price, {"from": lender})
    return price


def remove_quote_token(lenders, pool, buckets_deposited, chain):
    for lender_index, price in buckets_deposited.items():
        print(f"lender {lender_index} removing liquidity at {price / 1e18}")
        lender = lenders[lender_index]
        pool.removeQuoteToken(lender, 200_000 * 1e18, price, {"from": lender})
        chain.sleep((lender_index + 1) * 300)


def test_stable_volatile_one(pool1, dai, weth, lenders, borrowers, bucket_math, test_utils, chain):
    assert pool1.collateral() == weth
    assert pool1.quoteToken() == dai
    assert len(lenders) == 100
    assert len(borrowers) == 100
    assert weth.balanceOf(borrowers[0]) >= 67 * 1e18
    print("Before:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, MAX_BUCKET))
    print(f"total quote token: {pool1.totalQuoteToken()/1e18}")
    print(f"actual utilization: {pool1.getPoolActualUtilization()/1e18}")
    assert pool1.totalQuoteToken() > 2_700_000 * 1e18  # 50% utilization
    assert pool1.getPoolActualUtilization() > 0.50 * 1e18

    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeQuoteToken', 'updateInterestRate']):
        buckets_deposited = draw_and_bid(lenders, borrowers, pool1, weth, bucket_math, chain)
        hpb_index = bucket_math.priceToIndex(pool1.hdp())
        print("After:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, hpb_index))
        remove_quote_token(lenders, pool1, buckets_deposited, chain)

    # assert False
    # chain.sleep(3600)
