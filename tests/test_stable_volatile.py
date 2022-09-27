import math

import brownie
import pytest
import random
from decimal import *
from brownie import Contract
from brownie.exceptions import VirtualMachineError
from sdk import AjnaProtocol, DAI_ADDRESS, MKR_ADDRESS
from conftest import LoansHeapUtils, MAX_PRICE, ScaledPoolUtils, TestUtils


MAX_BUCKET = 2532  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization
MIN_BUCKET = 2612  # 2210.03602, lowest bucket involved in the test
SECONDS_PER_DAY = 3600 * 24
MIN_UTILIZATION = 0.4
MAX_UTILIZATION = 0.8
GOAL_UTILIZATION = 0.6      # borrowers should collateralize such that target utilization approaches this
MIN_PARTICIPATION = 10000   # in quote token, the minimum amount to lend
NUM_LENDERS = 25
NUM_BORROWERS = 25


# set of buckets deposited into, indexed by lender index
buckets_deposited = {lender_id: set() for lender_id in range(0, NUM_LENDERS)}
# timestamp when a lender/borrower last interacted with the pool
last_triggered = {}
# list of threshold prices for borrowers to attain in test setup, to start heap in a worst-case state
threshold_prices = LoansHeapUtils.worst_case_heap_orientation(NUM_BORROWERS, scale=10)
assert len(threshold_prices) == NUM_BORROWERS


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())
    amount = int(3_000_000_000 * 10**18 / NUM_LENDERS)
    lenders = []
    print("Initializing lenders")
    for _ in range(NUM_LENDERS):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, amount)
        dai_client.approve_max(scaled_pool, lender)
        lenders.append(lender)
    return lenders


@pytest.fixture
def borrowers(ajna_protocol, scaled_pool):
    collateral_client = ajna_protocol.get_token(scaled_pool.collateral())
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())
    amount = int(150_000 * 10**18 / NUM_BORROWERS)
    borrowers = []
    print("Initializing borrowers")
    for _ in range(NUM_BORROWERS):
        borrower = ajna_protocol.add_borrower()
        collateral_client.top_up(borrower, amount)
        collateral_client.approve_max(scaled_pool, borrower)
        dai_client.top_up(borrower, 100_000 * 10**18)  # for repayment of interest
        dai_client.approve_max(scaled_pool, borrower)
        assert collateral_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)
    return borrowers


@pytest.fixture
def pool1(scaled_pool, lenders, borrowers, scaled_pool_utils, test_utils, chain):
    pool = scaled_pool
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool, scaled_pool_utils)
    draw_initial_debt(borrowers, pool, scaled_pool_utils, test_utils, chain, target_utilization=GOAL_UTILIZATION)
    global last_triggered
    last_triggered = dict.fromkeys(range(0, max(NUM_LENDERS, NUM_BORROWERS)), 0)
    test_utils.validate_pool(pool, scaled_pool_utils)
    return pool


def add_initial_liquidity(lenders, pool, scaled_pool_utils):
    # Lenders 0-9 will be "new to the pool" upon actual testing
    # TODO: determine this non-arbitrarily
    deposit_amount = 1_000 * 10 ** 18
    for i in range(10, len(lenders) - 1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4) + 1):
            price_count = MIN_BUCKET - MAX_BUCKET
            price_position = int(random.expovariate(lambd=6.3) * price_count)
            price_index = price_position + MAX_BUCKET
            print(f" lender {i} depositing {deposit_amount/1e18} into bucket {price_index} "
                  f"({scaled_pool_utils.index_to_price(price_index) / 1e18:.1f})")
            pool.addQuoteToken(deposit_amount, price_index, {"from": lenders[i]})


def draw_initial_debt(borrowers, pool, scaled_pool_utils, test_utils, chain, target_utilization):
    (poolSize, _, _, _) = pool.poolLoansInfo()
    target_debt = (poolSize - pool.borrowerDebt()) * target_utilization
    sleep_amount = max(1, int(12 * 3600 / NUM_LENDERS))
    for borrower_index in range(0, len(borrowers) - 1):
        # determine amount we want to borrow and how much collateral should be deposited
        borrower = borrowers[borrower_index]
        borrow_amount = int(target_debt / NUM_BORROWERS)  # WAD
        assert borrow_amount > 10**18

        (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
        pool_price = lup
        if pool_price == MAX_PRICE:  # if there is no LUP,
            pool_price = hpb  # use the highest-priced bucket with deposit

        # determine amount of collateral to deposit
        collateralization_ratio = min((1 / target_utilization) + 0.05, 2.5)  # cap at 250% collateralization
        if threshold_prices:
            tp = threshold_prices.pop(0)
            if tp:
                collateral_to_deposit = int((borrow_amount / tp) * collateralization_ratio)
            else:  # 0 TP implies empty node on the tree
                collateral_to_deposit = borrow_amount * 10**18 / pool_price * collateralization_ratio
        else:
            collateral_to_deposit = borrow_amount * 10**18 / pool_price * collateralization_ratio  # WAD

        pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, scaled_pool_utils, test_utils, debug=True)
        test_utils.validate_pool(pool, scaled_pool_utils)
        chain.sleep(sleep_amount)


def ensure_pool_is_funded(pool, quote_token_amount: int, action: str) -> bool:
    """ Ensures pool has enough funds for an operation which requires an amount of quote token. """
    pool_quote_balance = Contract(pool.quoteToken()).balanceOf(pool)
    if pool_quote_balance < quote_token_amount:
        print(f" WARN: contract has {pool_quote_balance/1e18:.1f} quote token; "
              f"cannot {action} {quote_token_amount/1e18:.1f}")
        return False
    else:
        return True


def get_cumulative_bucket_deposit(pool, bucket_depth) -> int:  # WAD
    # Iterates through number of buckets passed as parameter, adding deposit to determine what loan size will be
    # required to utilize the buckets.
    (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
    index = lupIndex
    (quote, _, _, _, _, _, _) = pool.bucketAt(lupIndex)
    cumulative_deposit = quote
    while bucket_depth > 0 and index > MIN_BUCKET:
        index += 1
        # TODO: This ignores partially-utilized buckets; difficult to calculate in v10
        (quote, _, _, _, _, _, _) = pool.bucketAt(index)
        cumulative_deposit += quote
        bucket_depth -= 1
    return cumulative_deposit


def get_time_between_interactions(actor_index):
    # Distribution function throttles time between interactions based upon user_index
    return 333 * math.exp(actor_index/10) + 3600


def pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, scaled_pool_utils, test_utils, debug=False):
    (_, pending_debt, collateral_deposited, _, _) = pool.borrowerInfo(borrower.address)
    if not ensure_pool_is_funded(pool, borrow_amount, "borrow"):
        return
    assert borrow_amount > 10**18

    # pledge collateral
    collateral_token = Contract(pool.collateral())
    collateral_balance = collateral_token.balanceOf(borrower)
    if collateral_balance < collateral_to_deposit:
        print(f" WARN: borrower {borrower_index} only has {collateral_balance/1e18:.1f} collateral "
              f"and cannot deposit {collateral_to_deposit/1e18:.1f} to draw debt")
        return
    borrower_collateral = collateral_deposited + collateral_to_deposit
    if debug:
        print(f" borrower {borrower_index:>4} pledging {collateral_to_deposit / 1e18:.8f} collateral")
    assert collateral_to_deposit > 0.001 * 10**18
    pool.pledgeCollateral(borrower, collateral_to_deposit, {"from": borrower})

    # draw debt
    (_, pending_debt, collateral_deposited, _, _) = pool.borrowerInfo(borrower.address)
    new_total_debt = pending_debt + borrow_amount + ScaledPoolUtils.get_origination_fee(pool, borrow_amount)
    threshold_price = new_total_debt * 10**18 / collateral_deposited
    (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
    print(f" borrower {borrower_index:>4} drawing {borrow_amount / 1e18:>8.1f} from bucket {lup / 1e18:>6.3f} "
          f"with {collateral_deposited / 1e18:>6.1f} collateral deposited, "
          f"with {new_total_debt/1e18:>9.1f} total debt "
          f"at a TP of {threshold_price/1e18:8.1f}")
    tx = pool.borrow(borrow_amount, MIN_BUCKET, {"from": borrower})
    test_utils.validate_pool(pool, scaled_pool_utils)
    return tx


def draw_and_bid(lenders, borrowers, start_from, pool, chain, scaled_pool_utils, test_utils, duration=3600):
    user_index = start_from
    end_time = chain.time() + duration
    # Update the interest rate
    interest_rate = pool.interestRate() / 10**18
    chain.sleep(14)

    while chain.time() < end_time:
        if chain.time() - last_triggered[user_index] > get_time_between_interactions(user_index):

            # Draw debt, repay debt, or do nothing depending on interest rate
            if user_index < NUM_BORROWERS:
                (minDebtAmount, collateralization, mau, tu) = pool.poolUtilizationInfo()
                utilization = mau / 10**18
                if interest_rate < 0.10 and utilization < MAX_UTILIZATION:
                    target_collateralization = max(1.1, 1/GOAL_UTILIZATION)
                    draw_debt(borrowers[user_index], user_index, pool, scaled_pool_utils, test_utils, collateralization=target_collateralization)
                elif utilization > MIN_UTILIZATION:  # start repaying debt if interest grows too high
                    repay(borrowers[user_index], user_index, pool, test_utils)
                chain.sleep(14)

            # Add or remove liquidity
            if user_index < NUM_LENDERS:
                (minDebtAmount, collateralization, mau, tu) = pool.poolUtilizationInfo()
                utilization = mau / 10**18
                if utilization < MAX_UTILIZATION and len(buckets_deposited[user_index]) > 0:
                    price = buckets_deposited[user_index].pop()
                    # try:
                    remove_quote_token(lenders[user_index], user_index, price, pool)
                    # except VirtualMachineError as ex:
                    #     print(f" ERROR removing liquidity at {price / 10**18:.1f}, "
                    #           f"collateralized at {collateralization / 10**18:.1%}: {ex}")
                    #     print(test_utils.dump_book(pool, scaled_pool_utils))
                    #     buckets_deposited[user_index].add(price)  # try again later when pool is better collateralized
                else:
                    price = add_quote_token(lenders[user_index], user_index, pool, scaled_pool_utils)
                    if price:
                        buckets_deposited[user_index].add(price)

            try:
                test_utils.validate_pool(pool, scaled_pool_utils)
            except AssertionError as ex:
                print("Pool state became invalid:")
                print(TestUtils.dump_book(pool, scaled_pool_utils))
                raise ex
            chain.sleep(14)

            last_triggered[user_index] = chain.time()
        # chain.mine(blocks=20, timedelta=274)  # https://github.com/eth-brownie/brownie/issues/1514
        chain.sleep(274)
        user_index = (user_index + 1) % max(NUM_LENDERS, NUM_BORROWERS)  # increment with wraparound
    return user_index


def draw_debt(borrower, borrower_index, pool, scaled_pool_utils, test_utils, collateralization=1.1):
    # Draw debt based on added liquidity
    borrow_amount = get_cumulative_bucket_deposit(pool, (borrower_index % 4) + 1)
    (poolSize, _, _, _) = pool.poolLoansInfo()
    pool_quote_on_deposit = poolSize - pool.borrowerDebt()
    borrow_amount = min(pool_quote_on_deposit / 2, borrow_amount)
    (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
    collateral_to_deposit = borrow_amount / lup * collateralization * 10**18

    # if borrower doesn't have enough collateral, adjust debt based on what they can afford
    collateral_token = Contract(pool.collateral())
    collateral_balance = collateral_token.balanceOf(borrower)
    if collateral_balance <= 10**18:
        print(f" WARN: borrower {borrower_index} has insufficient collateral to draw debt")
        return
    elif collateral_balance < collateral_to_deposit:
        collateral_to_deposit = collateral_balance
        borrow_amount = collateral_to_deposit * lup / collateralization / 10**18
        print(f" WARN: borrower {borrower_index} only has {collateral_balance/1e18:.1f} collateral; "
              f" drawing {borrow_amount/1e18:.1f} of debt against it")

    tx = pledge_and_borrow(pool, borrower, borrower_index, collateral_to_deposit, borrow_amount, scaled_pool_utils, test_utils)


def add_quote_token(lender, lender_index, pool, scaled_pool_utils):
    dai = Contract(pool.quoteToken())
    index_offset = ((lender_index % 6) - 2) * 2
    (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
    deposit_index = lupIndex - index_offset
    deposit_price = scaled_pool_utils.index_to_price(deposit_index)
    quantity = int(MIN_PARTICIPATION * ((lender_index % 4) + 1) ** 2) * 10**18

    if dai.balanceOf(lender) < quantity:
        print(f" lender   {lender_index:>4} had insufficient balance to add {quantity / 10 ** 18:.1f}")
        return None

    print(f" lender   {lender_index:>4} adding {quantity / 10**18:.1f} liquidity at {deposit_price / 10**18:.1f}")
    # try:
    tx = pool.addQuoteToken(quantity, deposit_index, {"from": lender})
    return deposit_price


def remove_quote_token(lender, lender_index, price, pool):
    price_index = pool.priceToIndex(price)
    (lp_balance, _) = pool.lenders(price_index, lender)
    if lp_balance > 0:
        exchange_rate = pool.exchangeRate(price_index)
        claimable_quote = lp_balance * exchange_rate / 10**36
        print(f" lender   {lender_index:>4} removing {claimable_quote / 10**18:.1f} quote"
              f" from bucket {price_index} ({price / 10**18:.1f}); exchange rate is {exchange_rate/1e27:.8f}")
        if not ensure_pool_is_funded(pool, claimable_quote * 2, "withdraw"):
            return
        tx = pool.removeAllQuoteToken(price_index, {"from": lender})
    else:
        print(f" lender   {lender_index:>4} has no claim to bucket {price / 10**18:.1f}")


def repay(borrower, borrower_index, pool, test_utils):
    dai = Contract(pool.quoteToken())
    (_, pending_debt, collateral_deposited, _, _) = pool.borrowerInfo(borrower)
    quote_balance = dai.balanceOf(borrower)
    min_debt = pool.poolMinDebtAmount()

    if quote_balance < 100 * 10**18:
        print(f" borrower {borrower_index:>4} only has {quote_balance/1e18:.1f} quote token and will not repay debt")
        return

    if pending_debt > 100 * 10**18:
        repay_amount = min(pending_debt, quote_balance)

        # if partial repayment, ensure we're not leaving a dust amount
        if repay_amount != pending_debt and pending_debt - repay_amount < min_debt:
            print(f" borrower {borrower_index:>4} not repaying loan of {pending_debt / 1e18:.1f}; "
                  f"repayment would drop below min debt amount of {min_debt / 1e18:.1f}")
            return

        # do the repayment
        repay_amount = int(repay_amount * 1.01)
        print(f" borrower {borrower_index:>4} repaying {repay_amount/1e18:.1f} of {pending_debt/1e18:.1f} debt")
        tx = pool.repay(borrower, repay_amount, {"from": borrower})

        # withdraw appropriate amount of collateral to maintain a target-utilization-friendly collateralization
        (_, pending_debt, collateral_deposited, _, _) = pool.borrowerInfo(borrower)
        (hpb, htp, lup, lupIndex) = pool.poolPricesInfo()
        collateral_encumbered = int((pending_debt * 10**18) / lup)
        collateral_to_withdraw = int(collateral_deposited - (collateral_encumbered * 1.667))
        print(f" borrower {borrower_index:>4}, with {collateral_deposited/1e18:.1f} deposited "
              f"and {collateral_encumbered/1e18:.1f} encumbered, "
              f"is withdrawing {collateral_deposited/1e18:.1f} collateral")
        assert collateral_to_withdraw > 0
        tx = pool.pullCollateral(collateral_to_withdraw, {"from": borrower})
    elif pending_debt == 0:
        print(f" borrower {borrower_index:>4} has no debt to repay")
    else:
        print(f" borrower {borrower_index:>4} will not repay dusty {pending_debt/1e18:.1f} debt")


def test_stable_volatile_one(pool1, lenders, borrowers, scaled_pool_utils, test_utils, chain):
    # Validate test set-up
    print("Before test:\n" + test_utils.dump_book(pool1, scaled_pool_utils))
    assert pool1.collateral() == MKR_ADDRESS
    assert pool1.quoteToken() == DAI_ADDRESS
    assert len(lenders) == NUM_LENDERS
    assert len(borrowers) == NUM_BORROWERS
    (minDebtAmount, collateralization, mau, tu) = pool1.poolUtilizationInfo()
    assert mau > 0
    test_utils.validate_pool(pool1, scaled_pool_utils)

    # Simulate pool activity over a configured time duration
    start_time = chain.time()
    end_time = start_time + SECONDS_PER_DAY * 3
    actor_id = 0
    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeAllQuoteToken', 'repay']):
        while chain.time() < end_time:
            # hit the pool an hour at a time, calculating interest and then sending transactions
            actor_id = draw_and_bid(lenders, borrowers, actor_id, pool1, chain, scaled_pool_utils, test_utils)
            test_utils.summarize_pool(pool1)
            print(f"days remaining: {(end_time - chain.time()) / 3600 / 24:.3f}\n")

    # Validate test ended with the pool in a meaningful state
    test_utils.validate_pool(pool1, scaled_pool_utils)
    print("After test:\n" + test_utils.dump_book(pool1, scaled_pool_utils))
    (minDebtAmount, collateralization, mau, tu) = pool1.poolUtilizationInfo()
    utilization = mau / 10**18
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days   actual utilization: {utilization}")
    assert MIN_UTILIZATION * 0.9 < utilization < MAX_UTILIZATION * 1.1
