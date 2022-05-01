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
MIN_UTILIZATION = 0.4
MAX_UTILIZATION = 0.8
GOAL_UTILIZATION = 0.6


# set of buckets deposited into, indexed by lender index
buckets_deposited = {lender_id: set() for lender_id in range(0, 100)}
# timestamp when a lender/borrower last interacted with the pool
last_triggered = {}


@pytest.fixture
def pool_client(ajna_protocol: AjnaProtocol, weth, dai) -> AjnaPoolClient:
    return ajna_protocol.get_pool(weth.address, dai.address)


@pytest.fixture
def lenders(ajna_protocol, pool_client, weth_dai_pool):
    dai_client = pool_client.get_quote_token()
    amount = 3_000_000 * 10**18
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
    amount = 15_000 * 10**18
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
    draw_initial_debt(borrowers, pool_client, bucket_math, test_utils, target_utilization=GOAL_UTILIZATION)
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

    def validate(self, tx, limit=800000):
        if tx.gas_used > limit:
            print(f"Gas used {tx.gas_used} exceeds limit {limit}")
            hpb_index = self.bucket_math.priceToIndex(self.pool.hpb())
            print(TestUtils.dump_book(self.pool, self.bucket_math, self.min_bucket, hpb_index))
            assert False


@pytest.fixture
def tx_validator(pool1, bucket_math):
    return TransactionValidator(pool1, bucket_math, MIN_BUCKET)


def add_initial_liquidity(lenders, pool_client, bucket_math):
    # Lenders 0-9 will be "new to the pool" upon actual testing
    for i in range(10, len(lenders) - 1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4) + 1):
            place_initial_random_bid(i, pool_client, bucket_math)


def place_initial_random_bid(lender_index, pool_client, bucket_math):
    price_count = MAX_BUCKET - MIN_BUCKET
    price_position = 1 - random.expovariate(lambd=5.0)
    price_index = (
        max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    )
    price = bucket_math.indexToPrice(price_index)
    pool_client.deposit_quote_token(60_000 * 10**18, price, lender_index)


def draw_initial_debt(borrowers, pool_client, bucket_math, test_utils, target_utilization, limit_price=2000 * 10**18):
    pool = pool_client.get_contract()
    weth = pool_client.get_collateral_token().get_contract()
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(0, len(borrowers) - 1):
        borrower = borrowers[borrower_index]
        collateral_balance = weth.balanceOf(borrower)
        borrow_amount = target_debt / 100
        assert borrow_amount > 10**45
        pool_price = pool.lup()
        if pool_price == 0:
            pool_price = 3293.70191 * 10**18  # MAX_BUCKET
        collateralization_ratio = min(1 / target_utilization, 2.5)  # cap at 250% collateralization
        collateral_to_deposit = borrow_amount / pool_price * collateralization_ratio / 10**9
        assert collateral_balance > collateral_to_deposit
        pool_client.deposit_collateral(collateral_to_deposit, borrower_index)
        # print(f"\nBorrower {borrower_index} drawing {borrow_amount/1e45:.1f} from bucket {pool.lup()/1e18:.1f}")
        pool_client.borrow(borrow_amount / 10**27, borrower_index, limit_price)
        # test_utils.validate_debt(pool, borrowers, bucket_math, MIN_BUCKET)


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
            utilization = pool.getPoolActualUtilization() / 10**27
            if interest_rate < 0.10 and utilization < MAX_UTILIZATION:
                target_collateralization = max(1.1, 1/GOAL_UTILIZATION)
                draw_debt(borrowers[user_index], user_index, pool, gas_validator,
                          collateralization=target_collateralization)
            elif utilization > MIN_UTILIZATION:  # start repaying debt if interest grows too high
                repay(borrowers[user_index], user_index, pool, gas_validator)
            chain.sleep(14)

            # Add or remove liquidity
            utilization = pool.getPoolActualUtilization() / 10**27
            if utilization < MAX_UTILIZATION and len(buckets_deposited[user_index]) > 0:
                price = buckets_deposited[user_index].pop()
                try:
                    remove_quote_token(lenders[user_index], user_index, price, pool)
                except VirtualMachineError as ex:
                    print(f" ERROR removing liquidity at {price / 10**18:.1f}: {ex}")
                    buckets_deposited[user_index].add(price)  # try again later when pool is better collateralized
            else:
                price = add_quote_token(lenders[user_index], user_index, pool, bucket_math, gas_validator)
                if price:
                    buckets_deposited[user_index].add(price)

            try:
                max_bucket = bucket_math.priceToIndex(pool.hpb()) + 100
                test_utils.validate_book(pool, bucket_math, MIN_BUCKET - 100, max_bucket)
                # test_utils.validate_debt(pool, borrowers, bucket_math, MIN_BUCKET)
            except AssertionError as ex:
                print("Book or debt became invalid:")
                print(TestUtils.dump_book(pool, bucket_math, MIN_BUCKET, bucket_math.priceToIndex(pool.hpb())))
                raise ex
            chain.sleep(14)

            last_triggered[user_index] = chain.time()
        # chain.mine(blocks=20, timedelta=274)  # https://github.com/eth-brownie/brownie/issues/1514
        chain.sleep(274)
        user_index = (user_index + 1) % 100  # increment with wraparound
    return user_index

    
def update_interest_rate(lenders, pool) -> int:
    # Update the interest rate
    tx = pool.updateInterestRate({"from": lenders[random.randrange(0, len(lenders))]})
    if 'UpdateInterestRate' in tx.events:
        interest_rate = tx.events['UpdateInterestRate'][0][0]['newRate'] / 10**18
        print(f" updated interest rate to {interest_rate:.3%}")
    else:
        interest_rate = pool.previousRate() / 10**18
        print(f" interest rate was not updated, and remains at {interest_rate:.3%}")
    return interest_rate


def get_cumulative_bucket_deposit(pool, bucket_depth) -> int:  # WAD
    # Iterates through number of buckets passed as parameter, adding deposit to determine what loan size will be
    # required to utilize the buckets.
    (_, _, down, quote, _, _, _, _) = pool.bucketAt(pool.lup())
    cumulative_deposit = quote
    while bucket_depth > 0 and down:
        (_, _, down, quote, _, _, _, _) = pool.bucketAt(down)
        cumulative_deposit += quote
        bucket_depth -= 1
    return cumulative_deposit / 10**27


def draw_debt(borrower, borrower_index, pool, gas_validator, collateralization=1.1, limit_price=1000 * 10**18):
    # Draw debt based on added liquidity
    borrow_amount = get_cumulative_bucket_deposit(pool, (borrower_index % 4) + 1)
    borrow_amount = min(pool.totalQuoteToken() / 2, borrow_amount)
    collateral_to_deposit = borrow_amount / pool.lup() * collateralization * 10**18
    print(f" borrower {borrower_index} borrowing {borrow_amount / 10**18:.1f} "
          f"collateralizing at {collateralization:.1%}, (pool price is {pool.lup() / 10**18:.1f})")
    assert collateral_to_deposit > 10**18
    pool.addCollateral(collateral_to_deposit, {"from": borrower})
    assert borrow_amount > 10**18
    tx = pool.borrow(borrow_amount, limit_price, {"from": borrower})
    gas_validator.validate(tx)


def add_quote_token(lender, lender_index, pool, bucket_math, gas_validator, liquidity_coefficient=1.0):
    dai = Contract(pool.quoteToken())
    lup_index = bucket_math.priceToIndex(pool.lup())
    index_offset = ((lender_index % 6) - 2) * 2
    price = bucket_math.indexToPrice(lup_index + index_offset)
    quantity = int(30_000 * ((lender_index % 4) + 1)) * liquidity_coefficient * 10**18
    if dai.balanceOf(lender) > quantity:
        print(f" lender {lender_index} adding {quantity / 10**18:.1f} liquidity at {price / 10**18:.1f}")
        try:
            tx = pool.addQuoteToken(lender, quantity, price, {"from": lender})
            gas_validator.validate(tx)
            return price
        except VirtualMachineError as ex:
            (_, _, _, _, _, bucket_inflator, _, _) = pool.bucketAt(price)
            print(f" ERROR adding liquidity at {price / 10**18:.1f}\n{ex}")
            hpb_index = bucket_math.priceToIndex(pool.hpb())
            print(TestUtils.dump_book(pool, bucket_math, MIN_BUCKET, hpb_index))
            assert False
    else:
        print(f" lender {lender_index} had insufficient balance to add {quantity / 10**18:.1f}")
    return None


def remove_quote_token(lender, lender_index, price, pool):
    lp_balance = pool.getLPTokenBalance(lender, price)
    (_, _, _, quote, _, _, lp_outstanding, _) = pool.bucketAt(price)
    if lp_balance > 0:
        assert lp_outstanding > 0
        (_, claimable_quote) = pool.getLPTokenExchangeValue(lp_balance, price)
        claimable_quote = claimable_quote * 1.1 / 10**27  # include extra for unaccumulated interest
        print(f" lender {lender_index} removing {claimable_quote / 10**18:.1f} at {price / 10**18:.1f}")
        pool.removeQuoteToken(lender, claimable_quote, price, {"from": lender})
    else:
        print(f" lender {lender_index} has no claim to bucket {price / 10**18:.1f}")


def repay(borrower, borrower_index, pool, gas_validator):
    dai = Contract(pool.quoteToken())
    (debt, pending_debt, _, _, _, _, _) = pool.getBorrowerInfo(borrower)
    pending_debt = pending_debt / 10**27  # convert RAD to WAD
    quote_balance = dai.balanceOf(borrower)
    if pending_debt > 1000 * 10**18:
        if quote_balance > 100 * 10**18:
            repay_amount = min(pending_debt * 1.05, quote_balance)
            print(f" borrower {borrower_index} is repaying {repay_amount / 10**18:.1f}")
            pool.repay(repay_amount, {"from": borrower})
            (_, _, collateral_deposited, collateral_encumbered, _, _, _) = pool.getBorrowerInfo(borrower)
            # withdraw appropriate amount of collateral to maintain a target-utilization-friendly collateralization
            # FIXME: subtracting dust amount (1 wad) to mitigate rounding error
            collateral_to_withdraw = collateral_deposited - (collateral_encumbered * 1.667) - 10**27
            print(f" borrower {borrower_index} is withdrawing {collateral_to_withdraw / 10**27:.1f} collateral")
            tx = pool.removeCollateral(collateral_to_withdraw / 10**9, {"from": borrower})
            gas_validator.validate(tx)
        else:
            print(f" borrower {borrower_index} has insufficient funds to repay {pending_debt / 10**18:.1f}")


@pytest.mark.skip
def test_stable_volatile_one(pool1, dai, weth, lenders, borrowers, bucket_math, test_utils, chain, tx_validator):
    # Validate test set-up
    assert pool1.collateral() == weth
    assert pool1.quoteToken() == dai
    assert len(lenders) == 100
    assert len(borrowers) == 100
    assert pool1.totalQuoteToken() > 2_700_000 * 10**18  # 50% utilization
    assert pool1.getPoolActualUtilization() > 0.50 * 10**27
    test_utils.validate_debt(pool1, borrowers, bucket_math, MIN_BUCKET, print_error=True)

    # Simulate pool activity over a configured time duration
    start_time = chain.time()
    # end_time = start_time + SECONDS_PER_YEAR  # TODO: one year test
    end_time = start_time + SECONDS_PER_YEAR / 119
    actor_id = 0
    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeQuoteToken', 'repay', 'updateInterestRate']):
        while chain.time() < end_time:
            utilization = pool1.getPoolActualUtilization() / 10**27
            target = pool1.getPoolTargetUtilization() / 10**27
            collateralization = pool1.getPoolCollateralization() / 10**27
            print(f"actual utlzn: {utilization:>6.1%}   "
                  f"target utlzn: {target:>6.1%}   "
                  f"collateralization: {collateralization:>6.1%}   "
                  f"debt: {pool1.totalDebt()/10**45:>12.1f}")
            # hit the pool an hour at a time, calculating interest and then sending transactions
            actor_id = draw_and_bid(lenders, borrowers, actor_id, pool1, bucket_math, chain, tx_validator, test_utils)
            print(f"days remaining: {(end_time - chain.time()) / 3600 / 24:.3f}")

    # Validate test ended with the pool in a meaningful state
    test_utils.validate_debt(pool1, borrowers, bucket_math, MIN_BUCKET, print_error=True)
    hpb_index = bucket_math.priceToIndex(pool1.hpb())
    print("After test:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, hpb_index))
    utilization = pool1.getPoolActualUtilization() / 10**27
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days   actual utilization: {utilization}")
    assert MIN_UTILIZATION * 0.9 < utilization < MAX_UTILIZATION * 1.1
