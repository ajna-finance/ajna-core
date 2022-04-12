import math

import brownie
import inspect
import pytest
import random
from brownie import Contract
from brownie.exceptions import VirtualMachineError
from conftest import TestUtils
from decimal import *
from sdk import AjnaPoolClient, AjnaProtocol


MIN_BUCKET = 1543  # 2210.03602, lowest bucket involved in the test
MAX_BUCKET = 1623  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization
SECONDS_PER_YEAR = 3600 * 24 * 365


# set of buckets deposited into, indexed by lender index
buckets_deposited = dict.fromkeys(range(0, 100), set())
# timestamp when a lender/borrower last interacted with the pool
last_triggered = {}


@pytest.fixture
def pool_client(ajna_protocol: AjnaProtocol, weth, dai) -> AjnaPoolClient:
    return ajna_protocol.get_pool(weth.address, dai.address)


@pytest.fixture
def lenders(ajna_protocol, pool_client, weth_dai_pool):
    dai_client = pool_client.get_quote_token()
    amount = 4_000_000 * 1e18
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
    amount = 15_000 * 1e18
    dai_client = pool_client.get_quote_token()
    borrowers = []
    for _ in range(100):
        borrower = ajna_protocol.add_borrower()
        weth_client.top_up(borrower, amount)
        weth_client.approve_max(weth_dai_pool, borrower)
        dai_client.top_up(borrower, int(amount * 0.20))  # for repayment of interest
        dai_client.approve_max(weth_dai_pool, borrower)
        assert weth_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)

    return borrowers


@pytest.fixture
def pool1(pool_client, dai, weth, lenders, borrowers, bucket_math, test_utils):
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool_client, bucket_math)
    draw_initial_debt(borrowers, pool_client)
    global last_triggered
    last_triggered = dict.fromkeys(range(0, 100), 0)
    pool = pool_client.get_contract()
    test_utils.validate_book(pool, bucket_math, MIN_BUCKET, MAX_BUCKET)
    return pool


class TransactionValidator:
    def __init__(self, pool, bucket_math, min_bucket):
        self.pool = pool
        self.bucket_math = bucket_math
        self.min_bucket = min_bucket

    def validate(self, tx, limit=400000):
        if tx.gas_used > limit:
            print(f"Gas used {tx.gas_used} exceeds limit {limit}")
            hpb_index = self.bucket_math.priceToIndex(self.pool.hdp())
            print(TestUtils.dump_book(self.pool, self.bucket_math, self.min_bucket, hpb_index))
            assert False


@pytest.fixture
def tx_validator(pool1, bucket_math):
    return TransactionValidator(pool1, bucket_math, MIN_BUCKET)


def add_initial_liquidity(lenders, pool_client, bucket_math):
    # Lenders 0-9 will be "new to the pool" upon actual testing
    seed = 1648932463
    for i in range(10, len(lenders) - 1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4) + 1):
            random.seed(seed)
            seed += 1
            place_initial_random_bid(i, pool_client, bucket_math)


def place_initial_random_bid(lender_index, pool_client, bucket_math):
    price_count = MAX_BUCKET - MIN_BUCKET
    price_position = 1 - random.expovariate(lambd=5.0)
    price_index = (
        max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    )
    price = bucket_math.indexToPrice(price_index)
    pool_client.deposit_quote_token(60_000 * 10**18, price, lender_index)


def draw_initial_debt(borrowers, pool_client, target_utilization=0.60, limit_price=2210.03602 * 1e18):
    pool = pool_client.get_contract()
    weth = pool_client.get_collateral_token().get_contract()
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(0, len(borrowers) - 1):
        borrower = borrowers[borrower_index]
        collateral_balance = weth.balanceOf(borrower)
        borrow_amount = target_debt / 100
        assert borrow_amount > 10**45
        pool_price = pool.getPoolPrice()
        if pool_price == 0:
            pool_price = 3293.70191 * 10**18  # MAX_BUCKET
        collateralization_ratio = 1 / target_utilization
        collateral_to_deposit = borrow_amount / pool_price * collateralization_ratio / 10**9
        assert collateral_balance > collateral_to_deposit
        pool_client.deposit_collateral(collateral_to_deposit, borrower_index)
        pool_client.borrow(borrow_amount / 10**27, borrower_index, limit_price)


def get_time_between_interactions(actor_index):
    # Distribution function throttles time between interactions based upon user_index
    return 333 * math.exp(actor_index/10) + 3600


def draw_and_bid(lenders, borrowers, start_from, pool, bucket_math, chain, gas_validator, test_utils, duration=3600):
    user_index = start_from
    end_time = chain.time() + duration
    # Update the interest rate
    interest_rate = update_interest_rate(lenders, pool)
    chain.sleep(14)

    while chain.time() < end_time:
        if chain.time() - last_triggered[user_index] > get_time_between_interactions(user_index):

            # Draw debt, repay debt, or do nothing depending on interest rate
            utilization = pool.getPoolActualUtilization() / 1e18
            try:
                if interest_rate < 0.10 and utilization < 0.80:  # draw more debt if interest is reasonably low
                    target_collateralization = 1 / pool.getPoolTargetUtilization() * 1e18
                    assert 1 < target_collateralization < 10
                    draw_debt(borrowers[user_index], user_index, pool, gas_validator,
                              collateralization=target_collateralization)
                elif interest_rate > 0.20:  # start repaying debt if interest grows too high
                    repay(borrowers[user_index], user_index, pool)
            except VirtualMachineError as ex:
                print(f" ERROR at time {chain.time()}: {ex}")
            test_utils.validate_book(pool, bucket_math, MIN_BUCKET, MAX_BUCKET)
            chain.sleep(14)

            # Add or remove liquidity
            utilization = pool.getPoolActualUtilization() / 1e18
            if len(buckets_deposited[user_index]) > 3:  # if lender is in too many buckets, pull out of one
                price = buckets_deposited[user_index].pop()
                try:
                    remove_quote_token(lenders[user_index], user_index, price, pool)
                except VirtualMachineError as ex:
                    print(f" ERROR removing liquidity at {price / 1e18:.1f}: {ex}")
                    buckets_deposited[user_index].add(price)  # try again later when pool is better collateralized
            elif utilization > 0.60:
                liquidity_coefficient = 1.05 if utilization > pool.getPoolTargetUtilization() / 1e18 else 1.0
                price = add_quote_token(lenders[user_index], user_index, pool, bucket_math, gas_validator,
                                        liquidity_coefficient)
                if price:
                    buckets_deposited[user_index].add(price)
            try:
                test_utils.validate_book(pool, bucket_math, MIN_BUCKET, MAX_BUCKET)
            except AssertionError as ex:
                print("Book became invalid following the previous transaction")
                print(TestUtils.dump_book(pool, bucket_math, MIN_BUCKET, bucket_math.priceToIndex(pool.hdp())))
                raise ex
            print(TestUtils.dump_book(pool, bucket_math, MIN_BUCKET, bucket_math.priceToIndex(pool.hdp())))
            chain.sleep(14)

            last_triggered[user_index] = chain.time()
        chain.mine(blocks=20, timedelta=274)  # mine empty blocks
        user_index = (user_index + 1) % 100  # increment with wraparound
    return user_index

    
def update_interest_rate(lenders, pool) -> int:
    # Update the interest rate
    tx = pool.updateInterestRate({"from": lenders[random.randrange(0, len(lenders))]})
    interest_rate = tx.events["UpdateInterestRate"][0][0]['newRate'] / 1e18
    print(f" updated interest rate to {interest_rate:.1%}")
    assert 0.001 < interest_rate < 100
    return interest_rate


def get_cumulative_bucket_deposit(pool, bucket_depth) -> int:
    # Iterates through number of buckets passed as parameter, adding deposit to determine what loan size will be
    # required to utilize the buckets.
    (_, _, down, quote, _, _, _, _) = pool.bucketAt(pool.lup())
    cumulative_deposit = quote
    while bucket_depth > 0 and down:
        (_, _, down, quote, _, _, _, _) = pool.bucketAt(down)
        cumulative_deposit += quote
        bucket_depth -= 1
    return cumulative_deposit / 1e27


def draw_debt(borrower, borrower_index, pool, gas_validator, collateralization=1.1, limit_price=2210.03602 * 1e18):
    # Draw debt based on added liquidity
    borrow_amount = get_cumulative_bucket_deposit(pool, (borrower_index % 4) + 1)
    collateral_to_deposit = borrow_amount / pool.getPoolPrice() * collateralization * 1e18
    print(f" borrower {borrower_index} borrowing {borrow_amount / 1e18:.1f} "
          f"collateralizing at {collateralization:.1%}, (pool price is {pool.getPoolPrice() / 1e18:.1f})")
    assert collateral_to_deposit > 1e18
    pool.addCollateral(collateral_to_deposit, {"from": borrower})
    assert borrow_amount > 1e18
    tx = pool.borrow(borrow_amount, limit_price, {"from": borrower})
    gas_validator.validate(tx)


def add_quote_token(lender, lender_index, pool, bucket_math, gas_validator, liquidity_coefficient=1.0):
    dai = Contract(pool.quoteToken())
    lup_index = bucket_math.priceToIndex(pool.lup())
    index_offset = ((lender_index % 6) - 2) * 2
    price = bucket_math.indexToPrice(lup_index + index_offset)
    quantity = int(30_000 * ((lender_index % 4) + 1)) * liquidity_coefficient * 1e18
    if dai.balanceOf(lender) > quantity:
        print(f" lender {lender_index} adding {quantity / 1e18:.1f} liquidity at {price / 1e18:.1f}")
        try:
            tx = pool.addQuoteToken(lender, quantity, price, {"from": lender})
            gas_validator.validate(tx)
            return price
        except VirtualMachineError as ex:
            print(f" ERROR adding liquidity at {price / 1e18:.3f}: {ex}")
            hpb_index = bucket_math.priceToIndex(pool.hdp())
            print(TestUtils.dump_book(pool, bucket_math, MIN_BUCKET, hpb_index))
            assert False
    else:
        print(f" lender {lender_index} had insufficient balance to add {quantity / 1e18:.1f}")
    return None


def remove_quote_token(lender, lender_index, price, pool):
    lp_balance = pool.getLPTokenBalance(lender, price)
    (_, _, _, quote, _, _, lp_outstanding, _) = pool.bucketAt(price)
    if lp_balance > 0:
        assert lp_outstanding > 0
        (_, claimable_quote) = pool.getLPTokenExchangeValue(lp_balance, price)
        print(f" lender {lender_index} removing {claimable_quote / 1e18:.1f} at {price / 1e18:.1f}")
        pool.removeQuoteToken(lender, claimable_quote, price, {"from": lender})


def repay(borrower, borrower_index, pool):
    dai = Contract(pool.quoteToken())
    (debt, pending_debt, _, _, _, _, _) = pool.getBorrowerInfo(borrower)
    quote_balance = dai.balanceOf(borrower)
    if pending_debt > 1000 * 10**45:
        if quote_balance > 100 * 10**18:
            repay_amount = min(pending_debt * 1.05, quote_balance)
            print(f" borrower {borrower_index} is repaying {repay_amount / 1e18:.1f}")
            pool.repay(repay_amount, {"from": borrower})
            (_, _, collateral_deposited, collateral_encumbered, _, _, _) = pool.getBorrowerInfo(borrower)
            # withdraw appropriate amount of collateral to maintain a target-utilization-friendly collateralization
            collateral_to_withdraw = collateral_deposited - (collateral_encumbered * 1.667)
            pool.removeCollateral(collateral_to_withdraw, {"from": borrower})
        else:
            print(
                f" borrower {borrower_index} has insufficient funds to repay {pending_debt / 10**18:.1f}"
            )


def test_stable_volatile_one(pool1, dai, weth, lenders, borrowers, bucket_math, test_utils, chain, tx_validator):
    # Validate test set-up
    assert pool1.collateral() == weth
    assert pool1.quoteToken() == dai
    assert len(lenders) == 100
    assert len(borrowers) == 100
    assert pool1.totalQuoteToken() > 2_700_000 * 1e18  # 50% utilization
    assert pool1.getPoolActualUtilization() > 0.50 * 1e18
    print("Before test:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, bucket_math.priceToIndex(pool1.hdp())))

    # Simulate pool activity over a configured time duration
    start_time = chain.time()
    # end_time = start_time + SECONDS_PER_YEAR  # TODO: one year test
    end_time = start_time + SECONDS_PER_YEAR / 52
    actor_id = 0
    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeQuoteToken', 'repay', 'updateInterestRate']):
        while chain.time() < end_time:
            # hit the pool an hour at a time, calculating interest and then sending transactions
            actor_id = draw_and_bid(lenders, borrowers, actor_id, pool1, bucket_math, chain, tx_validator, test_utils)
            print(f"days remaining: {(end_time - chain.time()) / 3600 / 24:.3f}")

    # Validate test ended with the pool in a meaningful state
    hpb_index = bucket_math.priceToIndex(pool1.hdp())
    print("After test:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, hpb_index))
    utilization = pool1.getPoolActualUtilization() / 1e18
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days   actual utilization: {utilization}")
    assert 0.5 < utilization < 0.7
