import math

import brownie
import pytest
import random
from decimal import *
from brownie import Contract
from brownie.exceptions import VirtualMachineError
from sdk import AjnaProtocol, DAI_ADDRESS, MKR_ADDRESS
from conftest import LoansHeapUtils, MAX_PRICE, PoolHelper, TestUtils


MAX_BUCKET = 2532  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization
MIN_BUCKET = 2612  # 2210.03602, lowest bucket involved in the test
SECONDS_PER_DAY = 3600 * 24
MIN_UTILIZATION = 0.3
MAX_UTILIZATION = 0.7
GOAL_UTILIZATION = 0.5      # borrowers should collateralize such that target utilization approaches this
MIN_PARTICIPATION = 25000   # in quote token, the minimum amount to lend
NUM_LENDERS = 50
NUM_BORROWERS = 50
LOG_LENDER_ACTIONS = True
LOG_BORROWER_ACTIONS = True


# set of buckets deposited into, indexed by lender index
buckets_deposited = {lender_id: set() for lender_id in range(0, NUM_LENDERS)}
# timestamp when a lender/borrower last interacted with the pool
last_triggered = {}
# list of threshold prices for borrowers to attain in test setup, to start heap in a worst-case state
threshold_prices = LoansHeapUtils.worst_case_heap_orientation(NUM_BORROWERS, scale=2210/NUM_BORROWERS)
assert len(threshold_prices) == NUM_BORROWERS


def log(message: str):
    if "lender" in message and not LOG_LENDER_ACTIONS:
        return
    if "borrower" in message and not LOG_BORROWER_ACTIONS:
        return
    print(message)


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
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
    collateral_client = ajna_protocol.get_token(scaled_pool.collateralAddress())
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
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
def pool_helper(ajna_protocol, scaled_pool, lenders, borrowers, test_utils, chain):
    pool_helper = PoolHelper(ajna_protocol, scaled_pool)
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool_helper)
    draw_initial_debt(borrowers, pool_helper, test_utils, chain, target_utilization=GOAL_UTILIZATION)
    global last_triggered
    last_triggered = dict.fromkeys(range(0, max(NUM_LENDERS, NUM_BORROWERS)), 0)
    test_utils.validate_pool(pool_helper, borrowers)
    return pool_helper


def add_initial_liquidity(lenders, pool_helper):
    # Lenders 0-9 will be "new to the pool" upon actual testing
    # TODO: determine this non-arbitrarily
    deposit_amount = MIN_PARTICIPATION * 10**18
    first_lender = 0 if len(lenders) <= 10 else 10
    for i in range(first_lender, len(lenders) - 1):
        # determine how many buckets to deposit into
        for b in range(1, (i % 4) + 1):
            price_count = MIN_BUCKET - MAX_BUCKET
            price_position = int(random.expovariate(lambd=6.3) * price_count)
            price_index = price_position + MAX_BUCKET
            log(f" lender {i} depositing {deposit_amount/1e18} into bucket {price_index} "
                f"({pool_helper.indexToPrice(price_index) / 1e18:.1f})")
            pool_helper.pool.addQuoteToken(deposit_amount, price_index, {"from": lenders[i]})


def draw_initial_debt(borrowers, pool_helper, test_utils, chain, target_utilization):
    pool = pool_helper.pool
    target_debt = (pool.depositSize() - pool_helper.debt()) * target_utilization
    sleep_amount = max(1, int(12 * 3600 / NUM_BORROWERS))
    for borrower_index in range(0, len(borrowers) - 1):
        # determine amount we want to borrow and how much collateral should be deposited
        borrower = borrowers[borrower_index]
        borrow_amount = int(target_debt / NUM_BORROWERS)  # WAD
        assert borrow_amount > 10**18

        pool_price = pool_helper.lup()
        if pool_price == MAX_PRICE:  # if there is no LUP,
            pool_price = pool_helper.hpb()  # use the highest-priced bucket with deposit

        # determine amount of collateral to deposit
        if threshold_prices:
            # order the loan heap in a specific manner
            tp = threshold_prices.pop(0)
            if tp:
                collateral_to_deposit = int(borrow_amount / tp)
            else:  # 0 TP implies empty node on the tree
                collateral_to_deposit = 0
        else:
            collateralization_ratio = 1/GOAL_UTILIZATION
            collateral_to_deposit = borrow_amount * 10**18 / pool_price * collateralization_ratio  # WAD

        if collateral_to_deposit > 0:
            pledge_and_borrow(pool_helper, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils, debug=True)
        chain.sleep(sleep_amount)
    test_utils.validate_pool(pool_helper, borrowers)


def ensure_pool_is_funded(pool, quote_token_amount: int, action: str) -> bool:
    """ Ensures pool has enough funds for an operation which requires an amount of quote token. """
    pool_quote_balance = Contract(pool.quoteTokenAddress()).balanceOf(pool)
    if pool_quote_balance < quote_token_amount:
        log(f" WARN: contract has {pool_quote_balance/1e18:.1f} quote token; "
            f"cannot {action} {quote_token_amount/1e18:.1f}")
        return False
    else:
        return True


def get_cumulative_bucket_deposit(pool_helper, bucket_depth) -> int:  # WAD
    # Iterates through number of buckets passed as parameter, adding deposit to determine what loan size will be
    # required to utilize the buckets.
    index = pool_helper.lupIndex()
    (_, quote, _, _, _, _) = pool_helper.bucketInfo(index)
    cumulative_deposit = quote
    while bucket_depth > 0 and index > MIN_BUCKET:
        index += 1
        # TODO: This ignores partially-utilized buckets; difficult to calculate in v10
        (_, quote, _, _, _, _) = pool_helper.bucketInfo(index)
        cumulative_deposit += quote
        bucket_depth -= 1
    return cumulative_deposit


def get_time_between_interactions(actor_index):
    # Distribution function throttles time between interactions based upon user_index
    return 333 * math.exp(actor_index/10) + 3600


# for debugging discrepancy between borrower debt and pool debt
def aggregate_borrower_debt(borrowers, pool_helper, debug=False):
    total_debt = 0
    for i in range(0, len(borrowers) - 1):
        borrower = borrowers[i]
        (debt, _, _) = pool_helper.borrowerInfo(borrower.address)
        if debug and debt > 0:
            log(f"   borrower {i:>4}     debt: {debt/1e18:>15.3f}")
        total_debt += debt
    return total_debt


# for debugging debt-with-no-loans issue
def log_borrower_stats(borrowers, pool_helper, chain, debug=False):
    pool = pool_helper.pool
    poolDebt = pool_helper.debt()
    agg_borrower_debt = aggregate_borrower_debt(borrowers, pool_helper, debug)
    (_, loansCount, _, _, _) = pool_helper.loansInfo()

    log(f"  pool debt:  {poolDebt / 1e18:>15.3f}"
        f"  borrower:   {agg_borrower_debt / 1e18:>15.3f}"
        f"  diff:       {(poolDebt - agg_borrower_debt) / 1e18:>9.6f}"
        f"  loan count: {loansCount:>3}\n")
    chain.sleep(14)


def pledge_and_borrow(pool_helper, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils, debug=False):
    pool = pool_helper.pool

    # prevent invalid actions
    (debt, pledged, _) = pool_helper.borrowerInfo(borrower.address)
    if not ensure_pool_is_funded(pool, borrow_amount, "borrow"):
        # ensure_pool_is_funded logs a message
        return
    (min_debt, _, _, _) = pool_helper.utilizationInfo()
    if borrow_amount < min_debt:
        log(f" WARN: borrower {borrower_index} cannot draw {borrow_amount / 1e18:.1f}, "
            f"which is below minimum debt of {min_debt/1e18:.1f}")
        return

    # determine amount to pledge
    collateral_balance = pool_helper.collateralToken().balanceOf(borrower)
    if collateral_balance < collateral_to_deposit:
        log(f" WARN: borrower {borrower_index} only has {collateral_balance/1e18:.1f} collateral "
              f"and cannot deposit {collateral_to_deposit/1e18:.1f} to draw debt")
        return
    assert collateral_to_deposit > 0.001 * 10**18

    # draw debt
    pledged += collateral_to_deposit
    new_total_debt = debt + borrow_amount + pool_helper.get_origination_fee(borrow_amount)
    threshold_price = new_total_debt * 10**18 / pledged
    # CAUTION: This calculates collateralization against current LUP, rather than the new LUP once debt is drawn.
    collateralization = pledged * pool_helper.lup() / new_total_debt
    log(f" borrower {borrower_index:>4} drawing {borrow_amount / 1e18:>8.1f} from bucket {pool_helper.lup() / 1e18:>6.3f} "
        f"with {pledged / 1e18:>6.1f} collateral pledged, "
        f"with {new_total_debt/1e18:>9.1f} total debt "
        f"collateralized at {collateralization/1e18:>6.1%} "
        f"at a TP of {threshold_price/1e18:8.1f}")
    tx = pool.drawDebt(borrower, borrow_amount, MIN_BUCKET, collateral_to_deposit, {"from": borrower})
    return tx


def draw_and_bid(lenders, borrowers, start_from, pool_helper, chain, test_utils, duration=3600):
    user_index = start_from
    end_time = chain.time() + duration
    chain.sleep(14)

    while chain.time() < end_time:
        if chain.time() - last_triggered[user_index] > get_time_between_interactions(user_index):

            # Draw debt, repay debt, or do nothing depending on utilization
            if user_index < NUM_BORROWERS:
                (_, _, poolActualUtilization, _) = pool_helper.utilizationInfo()
                utilization = poolActualUtilization / 10**18
                if utilization < MAX_UTILIZATION:
                    target_collateralization = random.uniform(1.05, 1/MAX_UTILIZATION)
                    draw_debt(borrowers[user_index], user_index, pool_helper, test_utils, collateralization=target_collateralization)
                elif utilization > MIN_UTILIZATION:  # start repaying debt if interest grows too high
                    repay_debt(borrowers[user_index], user_index, pool_helper, test_utils)
                # log_borrower_stats(borrowers, pool_helper, chain, debug=True)
                chain.sleep(14)

            # Add or remove liquidity
            if user_index < NUM_LENDERS:
                if random.choice([True, False]):
                    price = add_quote_token(lenders[user_index], user_index, pool_helper)
                    if price:
                        buckets_deposited[user_index].add(price)
                else:
                    if len(buckets_deposited[user_index]) > 0:
                        price = buckets_deposited[user_index].pop()
                        if not remove_quote_token(lenders[user_index], user_index, price, pool_helper):
                            buckets_deposited[user_index].add(price)
                chain.sleep(14)

            try:
                test_utils.validate_pool(pool_helper, borrowers)
            except AssertionError as ex:
                log("Pool state became invalid:")
                log(TestUtils.dump_book(pool_helper))
                raise ex

            last_triggered[user_index] = chain.time()
        # chain.mine(blocks=20, timedelta=274)  # https://github.com/eth-brownie/brownie/issues/1514
        chain.sleep(900)
        user_index = (user_index + 1) % max(NUM_LENDERS, NUM_BORROWERS)  # increment with wraparound
    return user_index


def draw_debt(borrower, borrower_index, pool_helper, test_utils, collateralization=1.1):
    # Draw debt based on added liquidity
    borrow_amount = get_cumulative_bucket_deposit(pool_helper, (borrower_index % 4) + 1)
    pool_quote_on_deposit = pool_helper.pool.depositSize() - pool_helper.debt()
    borrow_amount = min(pool_quote_on_deposit / 2, borrow_amount)
    collateral_to_deposit = borrow_amount / pool_helper.lup() * collateralization * 10**18

    # if borrower doesn't have enough collateral, adjust debt based on what they can afford
    collateral_balance = pool_helper.collateralToken().balanceOf(borrower)
    if collateral_balance <= 10**18:
        log(f" WARN: borrower {borrower_index} has insufficient collateral to draw debt")
        return
    elif collateral_balance < collateral_to_deposit:
        collateral_to_deposit = collateral_balance
        borrow_amount = collateral_to_deposit * pool_helper.lup() / collateralization / 10**18
        log(f" WARN: borrower {borrower_index} only has {collateral_balance/1e18:.1f} collateral; "
              f" drawing {borrow_amount/1e18:.1f} of debt against it")

    tx = pledge_and_borrow(pool_helper, borrower, borrower_index, collateral_to_deposit, borrow_amount, test_utils)


def add_quote_token(lender, lender_index, pool_helper):
    dai = pool_helper.quoteToken()
    index_offset = ((lender_index % 6) - 2) * 2
    lup_index = pool_helper.lupIndex()
    deposit_index = lup_index - index_offset if lup_index > 6 else MAX_BUCKET
    deposit_price = pool_helper.indexToPrice(deposit_index)
    quantity = int(MIN_PARTICIPATION * ((lender_index % 4) + 1) ** 2) * 10**18

    if dai.balanceOf(lender) < quantity:
        log(f" lender   {lender_index:>4} had insufficient balance to add {quantity / 10 ** 18:.1f}")
        return None

    log(f" lender   {lender_index:>4} adding {quantity / 10**18:.1f} liquidity at {deposit_price / 10**18:.1f}")
    tx = pool_helper.pool.addQuoteToken(quantity, deposit_index, {"from": lender})
    return deposit_price


def remove_quote_token(lender, lender_index, price, pool_helper) -> bool:
    price_index = pool_helper.priceToIndex(price)
    (lp_balance, _) = pool_helper.lenderInfo(price_index, lender)
    if lp_balance > 0:
        (_, _, _, _, _, exchange_rate) = pool_helper.bucketInfo(price_index)
        claimable_quote = lp_balance * exchange_rate / 10**36
        log(f" lender   {lender_index:>4} removing {claimable_quote / 10**18:.1f} quote"
              f" from bucket {price_index} ({price / 10**18:.1f}); exchange rate is {exchange_rate/1e27:.8f}")
        if not ensure_pool_is_funded(pool_helper.pool, claimable_quote * 2, "withdraw"):
            return False
        try:
            tx = pool_helper.pool.removeQuoteToken(2**256 - 1, price_index, {"from": lender})
            return True
        except VirtualMachineError as ex:
            log(f"WARN: Could not remove quote token: {ex.message}")
            return False
    else:
        log(f" lender   {lender_index:>4} has no claim to bucket {price / 10**18:.1f}")


def repay_debt(borrower, borrower_index, pool_helper, test_utils):
    dai = pool_helper.quoteToken()
    (debt, collateral_deposited, _) = pool_helper.borrowerInfo(borrower)
    quote_balance = dai.balanceOf(borrower)
    (_, _, _, min_debt) = pool_helper.utilizationInfo()

    if quote_balance < 100 * 10**18:
        log(f" borrower {borrower_index:>4} only has {quote_balance/1e18:.1f} quote token and will not repay debt")
        return

    if debt > 100 * 10**18:
        repay_amount = min(debt, quote_balance)

        # if partial repayment, ensure we're not leaving a dust amount
        if repay_amount != debt and debt - repay_amount < min_debt:
            log(f" borrower {borrower_index:>4} not repaying loan of {debt / 1e18:.1f}; "
                  f"repayment would drop below min debt amount of {min_debt / 1e18:.1f}")
            return
        log(f" borrower {borrower_index:>4} repaying {repay_amount/1e18:.1f} of {debt/1e18:.1f} debt")

        # withdraw appropriate amount of collateral to maintain a target-utilization-friendly collateralization
        remaining_debt = debt - repay_amount
        if remaining_debt == 0:
            collateral_to_withdraw = collateral_deposited
            collateral_encumbered = 0
        else:
            collateral_encumbered = int((remaining_debt * 10**18) / pool_helper.lup())
            collateral_to_withdraw = int(collateral_deposited - (collateral_encumbered * 1.667))
        log(f" borrower {borrower_index:>4}, with {collateral_deposited/1e18:.1f} deposited "
              f"and {collateral_encumbered/1e18:.1f} encumbered, "
              f"is withdrawing {collateral_deposited/1e18:.1f} collateral")
        # assert collateral_to_withdraw > 0
        repay_amount = int(repay_amount * 1.01)
        tx = pool_helper.pool.repayDebt(borrower, repay_amount, collateral_to_withdraw, {"from": borrower})
    elif debt == 0:
        log(f" borrower {borrower_index:>4} has no debt to repay")
    else:
        log(f" borrower {borrower_index:>4} will not repay dusty {debt/1e18:.1f} debt")


def test_stable_volatile_one(pool_helper, lenders, borrowers, test_utils, chain):
    # Validate test set-up
    print("Before test:\n" + test_utils.dump_book(pool_helper))
    test_utils.summarize_pool(pool_helper)
    assert pool_helper.pool.collateralAddress() == MKR_ADDRESS
    assert pool_helper.pool.quoteTokenAddress() == DAI_ADDRESS
    assert len(lenders) == NUM_LENDERS
    assert len(borrowers) == NUM_BORROWERS
    # assert pool1.poolSize() > 2_700_000 * 10**18
    (_, _, poolActualUtilization, _) = pool_helper.utilizationInfo()
    assert poolActualUtilization > 0
    test_utils.validate_pool(pool_helper, borrowers)

    # Simulate pool activity over a configured time duration
    start_time = chain.time()
    end_time = start_time + SECONDS_PER_DAY * 7
    actor_id = 0
    with test_utils.GasWatcher(['addQuoteToken', 'drawDebt', 'removeQuoteToken', 'repayDebt']):
        while chain.time() < end_time:
            # hit the pool an hour at a time, calculating interest and then sending transactions
            actor_id = draw_and_bid(lenders, borrowers, actor_id, pool_helper, chain, test_utils)
            test_utils.summarize_pool(pool_helper)
            print(f"days remaining: {(end_time - chain.time()) / 3600 / 24:.3f}\n")

    # Validate test ended with the pool in a meaningful state
    test_utils.validate_pool(pool_helper, borrowers)
    print("After test:\n" + test_utils.dump_book(pool_helper))
    (_, _, poolActualUtilization, _) = pool_helper.utilizationInfo()
    utilization = poolActualUtilization / 10**18
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days   actual utilization: {utilization}")
    assert utilization > MIN_UTILIZATION
