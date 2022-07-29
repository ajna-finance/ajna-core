import math

import brownie
import pytest
import random
from brownie import Contract
from brownie.exceptions import VirtualMachineError
from conftest import MAX_PRICE, ScaledPoolUtils, TestUtils
from decimal import *
from sdk import AjnaProtocol, DAI_ADDRESS, MKR_ADDRESS


MAX_BUCKET = 2532  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization
MIN_BUCKET = 2612  # 2210.03602, lowest bucket involved in the test
SECONDS_PER_YEAR = 3600 * 24 * 365
MIN_UTILIZATION = 0.4
MAX_UTILIZATION = 0.8
GOAL_UTILIZATION = 0.6      # borrowers should collateralize such that target utilization approaches this
MIN_PARTICIPATION = 10000   # in quote token, the minimum amount to lend
NUM_ACTORS = 100


# set of buckets deposited into, indexed by lender index
buckets_deposited = {lender_id: set() for lender_id in range(0, NUM_ACTORS)}
# timestamp when a lender/borrower last interacted with the pool
last_triggered = {}


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())
    amount = 3_000_000 * 10**18
    lenders = []
    print("Initializing lenders")
    for _ in range(NUM_ACTORS):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, amount)
        dai_client.approve_max(scaled_pool, lender)
        lenders.append(lender)
    return lenders


@pytest.fixture
def borrowers(ajna_protocol, scaled_pool):
    collateral_client = ajna_protocol.get_token(scaled_pool.collateral())
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())
    amount = 1_500 * 10**18
    borrowers = []
    print("Initializing borrowers")
    for _ in range(NUM_ACTORS):
        borrower = ajna_protocol.add_borrower()
        collateral_client.top_up(borrower, amount)
        collateral_client.approve_max(scaled_pool, borrower)
        dai_client.top_up(borrower, 100_000 * 10**18)  # for repayment of interest
        dai_client.approve_max(scaled_pool, borrower)
        assert collateral_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)
    return borrowers


@pytest.fixture
def pool1(scaled_pool, lenders, borrowers, scaled_pool_utils, test_utils):
    pool = scaled_pool
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool, scaled_pool_utils)
    draw_initial_debt(borrowers, pool, test_utils, target_utilization=GOAL_UTILIZATION)
    global last_triggered
    last_triggered = dict.fromkeys(range(0, NUM_ACTORS), 0)
    test_utils.validate_pool(pool)
    return pool


class TransactionValidator:
    def __init__(self, pool, min_bucket):
        self.pool = pool
        self.min_bucket = min_bucket

    def validate(self, tx, limit=800000):
        if tx.gas_used > limit:
            print(f"Gas used {tx.gas_used} exceeds limit {limit}")
            assert False


@pytest.fixture
def tx_validator(pool1):
    return TransactionValidator(pool1, MIN_BUCKET)


def add_initial_liquidity(lenders, pool, scaled_pool_utils):
    # Lenders 0-9 will be "new to the pool" upon actual testing
    for i in range(10, len(lenders) - 1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4) + 1):
            place_initial_random_bid(lenders[i], pool, scaled_pool_utils)


def place_initial_random_bid(lender, pool, scaled_pool_utils):
    price_count = MIN_BUCKET - MAX_BUCKET
    price_position = int(random.expovariate(lambd=6.3) * price_count)
    price_index = price_position + MAX_BUCKET
    print(f" lender depositing into bucket {price_index} ({pool.indexToPrice(price_index)/1e18:.1f})")
    pool.addQuoteToken(60_000 * 10**18, price_index, {"from": lender})


def draw_initial_debt(borrowers, pool, test_utils, target_utilization):
    collateral_token = Contract(pool.collateral())
    target_debt = (pool.treeSum() - pool.borrowerDebt()) * target_utilization
    for borrower_index in range(0, len(borrowers) - 1):
        # determine amount we want to borrow and how much collateral should be deposited
        borrower = borrowers[borrower_index]

        collateral_balance = collateral_token.balanceOf(borrower)
        borrow_amount = target_debt / NUM_ACTORS  # WAD
        assert borrow_amount > 10**18
        pool_price = pool.lup()
        if pool_price == MAX_PRICE:             # if there is no LUP,
            pool_price = 3293.70191 * 10**18    # use the highest-priced bucket with deposit
        collateralization_ratio = min((1 / target_utilization) + 0.05, 2.5)  # cap at 250% collateralization
        # WAD / WAD * unscaled
        collateral_to_deposit = borrow_amount * 10**18 / pool_price * collateralization_ratio  # WAD
        assert collateral_balance > collateral_to_deposit

        pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils)


def pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils, debug=False):
    (_, pending_debt, collateral_deposited, _) = pool.borrowerInfo(borrower.address)

    # pledge collateral
    threshold_price = int(pending_debt / (collateral_deposited + collateral_to_deposit) * 10**18)
    old_prev, new_prev = ScaledPoolUtils.find_loan_queue_params(pool, borrower.address, threshold_price, debug)
    print(f" borrower {borrower_index} pledging {collateral_to_deposit / 1e18:.8f} collateral TP={threshold_price / 1e18:.1f}")
    assert collateral_to_deposit > 10 ** 18
    # TODO: if debt is 0, contracts require passing old_prev and new_prev=0, which is awkward
    pool.addCollateral(collateral_to_deposit, old_prev, new_prev, 0, {"from": borrower})
    test_utils.validate_queue(pool)

    # draw debt
    (_, pending_debt, collateral_deposited, _) = pool.borrowerInfo(borrower.address)
    new_total_debt = pending_debt + borrow_amount + ScaledPoolUtils.get_origination_fee(pool, borrow_amount)
    threshold_price = int(new_total_debt / collateral_deposited * 10**18)
    assert threshold_price > 10**18
    old_prev, new_prev = ScaledPoolUtils.find_loan_queue_params(pool, borrower.address, threshold_price, debug)
    print(f" borrower {borrower_index} drawing {borrow_amount / 1e18:.8f} from bucket {pool.lup() / 1e18:.1f} "
          f"with {collateral_deposited / 1e18:.18f} collateral deposited, "
          f"TP={threshold_price / 1e18:.8f} with {new_total_debt/1e18:.18f} total debt "
          f"old_prev={old_prev[:6]} new_prev={new_prev[:6]}")
    tx = pool.borrow(borrow_amount, MIN_BUCKET, old_prev, new_prev, 0, {"from": borrower})
    test_utils.validate_queue(pool)
    test_utils.validate_pool(pool)
    print("")
    return tx


def get_time_between_interactions(actor_index):
    # Distribution function throttles time between interactions based upon user_index
    return 333 * math.exp(actor_index/10) + 3600


def draw_and_bid(lenders, borrowers, start_from, pool, chain, gas_validator, test_utils, duration=3600):
    user_index = start_from
    end_time = chain.time() + duration
    # Update the interest rate
    interest_rate = pool.interestRate() / 10**18
    chain.sleep(14)

    while chain.time() < end_time:
        if chain.time() - last_triggered[user_index] > get_time_between_interactions(user_index):

            # Draw debt, repay debt, or do nothing depending on interest rate
            utilization = pool.poolActualUtilization() / 10**18
            if interest_rate < 0.10 and utilization < MAX_UTILIZATION:
                target_collateralization = max(1.1, 1/GOAL_UTILIZATION)
                draw_debt(borrowers[user_index], user_index, pool, gas_validator, test_utils,
                          collateralization=target_collateralization)
            elif utilization > MIN_UTILIZATION:  # start repaying debt if interest grows too high
                repay(borrowers[user_index], user_index, pool, gas_validator, test_utils)
            chain.sleep(14)

            # Add or remove liquidity
            utilization = pool.poolActualUtilization() / 10**18
            if utilization < MAX_UTILIZATION and len(buckets_deposited[user_index]) > 0:
                price = buckets_deposited[user_index].pop()
                # try:
                remove_quote_token(lenders[user_index], user_index, price, pool)
                # except VirtualMachineError as ex:
                #     print(f" ERROR removing liquidity at {price / 10**18:.1f}, "
                #           f"collateralized at {pool.poolCollateralization() / 10**18:.1%}: {ex}")
                #     print(test_utils.dump_book(pool1, MAX_BUCKET, MIN_BUCKET))
                #     buckets_deposited[user_index].add(price)  # try again later when pool is better collateralized
            else:
                price = add_quote_token(lenders[user_index], user_index, pool, gas_validator)
                if price:
                    buckets_deposited[user_index].add(price)

            try:
                test_utils.validate_pool(pool)
            except AssertionError as ex:
                print("Book or debt became invalid:")
                print(TestUtils.dump_book(pool, MAX_BUCKET, MIN_BUCKET))
                raise ex
            chain.sleep(14)

            last_triggered[user_index] = chain.time()
        # chain.mine(blocks=20, timedelta=274)  # https://github.com/eth-brownie/brownie/issues/1514
        chain.sleep(274)
        user_index = (user_index + 1) % NUM_ACTORS  # increment with wraparound
    return user_index


def get_cumulative_bucket_deposit(pool, bucket_depth) -> int:  # WAD
    # Iterates through number of buckets passed as parameter, adding deposit to determine what loan size will be
    # required to utilize the buckets.
    index = pool.lupIndex()
    (quote, _, _, _) = pool.bucketAt(index)
    cumulative_deposit = quote
    while bucket_depth > 0 and index > MIN_BUCKET:
        index += 1
        print(f" get_cumulative_bucket_deposit at {index}")
        # TODO: This ignores partially-utilized buckets; difficult to calculate in v10
        (quote, _, _, _) = pool.bucketAt(index)
        cumulative_deposit += quote
        bucket_depth -= 1
    return cumulative_deposit


def draw_debt(borrower, borrower_index, pool, gas_validator, test_utils, collateralization=1.1):
    # Draw debt based on added liquidity
    borrow_amount = get_cumulative_bucket_deposit(pool, (borrower_index % 4) + 1)
    pool_quote_on_deposit = pool.treeSum() - pool.borrowerDebt()
    borrow_amount = min(pool_quote_on_deposit / 2, borrow_amount)
    collateral_to_deposit = borrow_amount / pool.lup() * collateralization * 10**18
    print(f" borrower {borrower_index} borrowing {borrow_amount / 10**18:.1f} "
          f"collateralizing at {collateralization:.1%}, (pool price is {pool.lup() / 10**18:.1f})")
    assert collateral_to_deposit > 10**18
    assert borrow_amount > 10**18
    tx = pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils, debug=True)
    gas_validator.validate(tx)


def add_quote_token(lender, lender_index, pool, gas_validator):
    dai = Contract(pool.quoteToken())
    index_offset = ((lender_index % 6) - 2) * 2
    deposit_index = pool.lupIndex() - index_offset
    deposit_price = pool.indexToPrice(deposit_index)
    quantity = int(MIN_PARTICIPATION * ((lender_index % 4) + 1) ** 2) * 10**18

    if dai.balanceOf(lender) < quantity:
        print(f" lender {lender_index} had insufficient balance to add {quantity / 10 ** 18:.1f}")
        return None

    print(f" lender {lender_index} adding {quantity / 10**18:.1f} liquidity at {deposit_price / 10**18:.1f}")
    try:
        tx = pool.addQuoteToken(quantity, deposit_index, {"from": lender})
        gas_validator.validate(tx)
        return deposit_price
    except VirtualMachineError as ex:
        print(f" ERROR adding liquidity at {deposit_price / 10**18:.1f}\n{ex}")
        print(TestUtils.dump_book(pool, MAX_BUCKET, MIN_BUCKET))
        assert False


def remove_quote_token(lender, lender_index, price, pool):
    price_index = pool.priceToIndex(price)
    lp_balance = pool.lpBalance(price_index, lender)
    if lp_balance > 0:
        exchange_rate = pool.exchangeRate(price_index)
        claimable_quote = lp_balance * 10**9 / exchange_rate
        print(f" lender {lender_index} removing {lp_balance/1e27:.27f} lp "
              f"(~{claimable_quote / 10**18:.1f} quote) from bucket {price_index} ({price / 10**18:.1f})")
        tx = pool.removeQuoteToken(lp_balance, price_index, {"from": lender})
    else:
        print(f" lender {lender_index} has no claim to bucket {price / 10**18:.1f}")


def repay(borrower, borrower_index, pool, gas_validator, test_utils):
    dai = Contract(pool.quoteToken())
    (debt, pending_debt, _, _) = pool.borrowerInfo(borrower)
    quote_balance = dai.balanceOf(borrower)
    if debt > 1000 * 10**18:
        # TODO: handle partial repayment when out-of-funds, which requires calculating pending debt
        #if quote_balance > 100 * 10**18:
        if quote_balance > debt:
            # repay the debt
            (_, _, collateral_deposited, _) = pool.borrowerInfo(borrower)
            repay_amount = min(debt * 1.05, quote_balance)
            old_prev, new_prev = ScaledPoolUtils.find_loan_queue_params(pool, borrower.address, 0, debug=True)
            print(f" borrower {borrower_index} is repaying {repay_amount / 10**18:.1f}")
            pool.repay(repay_amount, old_prev, new_prev, 0, {"from": borrower})

            # withdraw appropriate amount of collateral to maintain a target-utilization-friendly collateralization
            # FIXME: this was producing a negative number; fix it
            # collateral_to_withdraw = collateral_deposited - (collateral_encumbered * 1.667)
            print(f" borrower {borrower_index} is withdrawing {collateral_deposited / 10**18:.1f} collateral")
            tx = pool.removeCollateral(collateral_deposited, old_prev, new_prev, 0, {"from": borrower})
            test_utils.validate_queue(pool)
            gas_validator.validate(tx)
        else:
            print(f" borrower {borrower_index} has insufficient funds to repay {debt / 10**18:.1f}")


@pytest.mark.skip
def test_stable_volatile_one(pool1, lenders, borrowers, scaled_pool_utils, test_utils, chain, tx_validator):
    # Validate test set-up
    print("Before test:\n" + test_utils.dump_book(pool1, MAX_BUCKET, MIN_BUCKET))
    assert pool1.collateral() == MKR_ADDRESS
    assert pool1.quoteToken() == DAI_ADDRESS
    assert len(lenders) == NUM_ACTORS
    assert len(borrowers) == NUM_ACTORS
    assert pool1.treeSum() > 2_700_000 * 10**18
    assert pool1.poolActualUtilization() > 0.50 * 10**18
    test_utils.validate_pool(pool1)

    # Simulate pool activity over a configured time duration
    start_time = chain.time()
    end_time = start_time + SECONDS_PER_YEAR / 365
    actor_id = 0
    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeQuoteToken', 'repay']):
        while chain.time() < end_time:
            utilization = pool1.poolActualUtilization() / 10**18
            target = pool1.poolTargetUtilization() / 10**18
            collateralization = pool1.poolCollateralization() / 10**18
            print(f"actual utlzn: {utilization:>6.1%}   "
                  f"target utlzn: {target:>6.1%}   "
                  f"collateralization: {collateralization:>6.1%}   "
                  f"debt: {pool1.borrowerDebt()/10**18:>12.1f}")
            # hit the pool an hour at a time, calculating interest and then sending transactions
            actor_id = draw_and_bid(lenders, borrowers, actor_id, pool1, chain, tx_validator, test_utils)
            print(f"days remaining: {(end_time - chain.time()) / 3600 / 24:.3f}")

    # Validate test ended with the pool in a meaningful state
    test_utils.validate_pool(pool1)
    print("After test:\n" + test_utils.dump_book(pool1, MAX_BUCKET, MIN_BUCKET))
    utilization = pool1.poolActualUtilization() / 10**18
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days   actual utilization: {utilization}")
    assert MIN_UTILIZATION * 0.9 < utilization < MAX_UTILIZATION * 1.1
