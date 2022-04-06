import brownie
import inspect
import pytest
import random
from brownie import Contract
from decimal import *
from sdk import AjnaPoolClient, AjnaProtocol


MIN_BUCKET = 1543  # 2210.03602, lowest bucket involved in the test
MAX_BUCKET = 1623  # 3293.70191, highest bucket for initial deposits, is exceeded after initialization
SECONDS_PER_YEAR = 3600 * 24 * 365


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
def pool1(pool_client, dai, weth, lenders, borrowers, bucket_math):
    # Adds liquidity to an empty pool and draws debt up to a target utilization
    add_initial_liquidity(lenders, pool_client, bucket_math)
    draw_initial_debt(borrowers, pool_client.get_contract(), weth)
    return pool_client.get_contract()


def add_initial_liquidity(lenders, pool_client, bucket_math):
    # Lenders 0-9 will be "new to the pool" upon actual testing
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
    price_index = max(0, min(int(price_position * price_count), price_count)) + MIN_BUCKET
    price = bucket_math.indexToPrice(price_index)
    pool_client.deposit_quote_token(60_000 * 1e18, price, lender_index)


def draw_initial_debt(borrowers, pool, weth, target_utilization=0.60, limit_price=2210.03602 * 1e18):
    target_debt = pool.totalQuoteToken() * target_utilization
    for borrower_index in range(0, len(borrowers) - 1):
        borrower = borrowers[borrower_index]
        collateral_balance = weth.balanceOf(borrower)
        borrow_amount = target_debt / 100
        assert borrow_amount > 1e18
        pool_price = pool.getPoolPrice()
        if pool_price == 0:
            pool_price = 3293.70191 * 1e18  # MAX_BUCKET
        collateralization_ratio = 1 / target_utilization
        collateral_to_deposit = borrow_amount / pool_price * collateralization_ratio * 1e18
        # print(f"borrower {borrower_index} about to deposit {collateral_to_deposit / 1e18:.1f} collateral "
        #       f"and draw {borrow_amount / 1e18:.1f} debt")
        assert collateral_balance > collateral_to_deposit
        pool.addCollateral(collateral_to_deposit, {"from": borrower})
        pool.borrow(borrow_amount, limit_price, {"from": borrower})


def draw_and_bid(lenders, borrowers, pool, bucket_math, chain, duration=3600*8) -> dict:
    buckets_deposited = {}
    assert len(lenders) == len(borrowers)
    delay = int(duration/3/len(lenders))
    for user_index in range(0, len(lenders)-1):
        # utilization = pool.getPoolActualUtilization() / 1e18
        # print(f"actual utilization: {utilization:>10.1%}   "
        #       f"target utilization: {pool.getPoolTargetUtilization() / 1e18:>10.1%}")

        # Update the interest rate
        tx = pool.updateInterestRate({"from": lenders[user_index]})
        interest_rate = tx.events["UpdateInterestRate"][0][0]['newRate'] / 1e18
        assert 0.001 < interest_rate < 100

        # Draw debt, repay debt, or do nothing depending on interest rate
        if interest_rate < 0.10:  # draw more debt if interest is reasonably low
            target_collateralization = 1 / pool.getPoolTargetUtilization() * 1e18
            assert 1 < target_collateralization < 10
            draw_debt(borrowers[user_index], user_index, pool, collateralization=target_collateralization)
            chain.sleep(delay)
        elif interest_rate > 0.20:  # start repaying debt if interest grows too high
            repay(borrowers[user_index], user_index, pool)
            chain.sleep(delay)

        # Add liquidity
        liquidity_coefficient = 1.05 if pool.getPoolActualUtilization() > pool.getPoolTargetUtilization() else 1.0
        buckets_deposited[user_index] = add_quote_token(lenders[user_index], user_index, pool, bucket_math,
                                                        liquidity_coefficient)
        chain.sleep(delay)

    print(f"interest rate: {interest_rate:>6.3%}   "
          f"total quote token: {pool.totalQuoteToken() / 1e18:>12.1f}   "
          f"total debt: {pool.totalDebt() / 1e18:>12.1f}")
    return buckets_deposited


def draw_debt(borrower, borrower_index, pool, collateralization=1.1, limit_price=2210.03602 * 1e18):
    # Draw debt based on added liquidity
    borrow_amount = int(90_000 * ((borrower_index % 2) + 1)) * 1e18
    collateral_to_deposit = borrow_amount / pool.getPoolPrice() * collateralization * 1e18
    print(f" borrower {borrower_index} will borrow {borrow_amount / 1e18:.1f} "
          f"collateralizing at {collateralization:.1f}, (pool price is {pool.getPoolPrice() / 1e18:.1f})")
    assert collateral_to_deposit > 1e18
    pool.addCollateral(collateral_to_deposit, {"from": borrower})
    # print(f"borrower {borrower_index} drawing {borrow_amount / 1e18:.1f} debt from {pool.getPoolPrice() / 1e18:.1f}")
    assert borrow_amount > 1e18
    pool.borrow(borrow_amount, limit_price, {"from": borrower})


def add_quote_token(lender, lender_index, pool, bucket_math, liquidity_coefficient=1.0):
    dai = Contract(pool.quoteToken())
    index_offset = ((lender_index % 6) - 2) * 2
    price = bucket_math.indexToPrice(MAX_BUCKET + index_offset)
    quantity = int(90_000 * ((lender_index % 2) + 1)) * liquidity_coefficient * 1e18
    if dai.balanceOf(lender) > quantity:
        print(f" lender {lender_index} adding {quantity / 1e18:.1f} liquidity at {price / 1e18:.1f}")
        pool.addQuoteToken(lender, quantity, price, {"from": lender})
        return price
    else:
        print(f" lender {lender_index} had insufficient balance to add {quantity / 1e18:.1f}")
        return None


def remove_quote_token(lenders, pool, buckets_deposited, chain):
    for lender_index, price in buckets_deposited.items():
        print(f" lender {lender_index} removing liquidity at {price / 1e18}")
        lender = lenders[lender_index]
        pool.removeQuoteToken(lender, 100_000 * 1e18, price, {"from": lender})
        chain.sleep((lender_index + 1) * 300)


def repay(borrower, borrower_index, pool):
    dai = Contract(pool.quoteToken())
    (debt, pending_debt, _, _, _, _, _) = pool.getBorrowerInfo(borrower)
    quote_balance = dai.balanceOf(borrower)
    if pending_debt > 1000 * 1e18:
        if quote_balance > 100 * 1e18:
            repay_amount = min(pending_debt * 1.05, quote_balance)
            print(f" borrower {borrower_index} is repaying {repay_amount / 1e18:.1f}")
            pool.repay(repay_amount, {"from": borrower})
        else:
            print(f" borrower {borrower_index} has insufficient funds to repay {pending_debt / 1e18:.1f}")


def test_stable_volatile_one(pool1, dai, weth, lenders, borrowers, bucket_math, test_utils, chain):
    assert pool1.collateral() == weth
    assert pool1.quoteToken() == dai
    assert len(lenders) == 100
    assert len(borrowers) == 100
    # print("Initialized book:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, MAX_BUCKET))
    # print(f"total quote token: {pool1.totalQuoteToken()/1e18}   "
    #       f"total debt: {pool1.totalDebt() / 1e18}")
    # print(f"initial utilization: {pool1.getPoolActualUtilization()/1e18}")
    assert pool1.totalQuoteToken() > 2_700_000 * 1e18  # 50% utilization

    start_time = chain.time()
    # end_time = start_time + SECONDS_PER_YEAR  # TODO: one year test
    end_time = start_time + SECONDS_PER_YEAR / 12 / 30
    test_exception = None
    with test_utils.GasWatcher(['addQuoteToken', 'borrow', 'removeQuoteToken', 'repay', 'updateInterestRate']):
        assert pool1.getPoolActualUtilization() > 0.50 * 1e18
        while chain.time() < end_time:
            try:
                buckets_deposited = draw_and_bid(lenders, borrowers, pool1, bucket_math, chain)
                # remove_quote_token(lenders, pool1, buckets_deposited, chain)
                print(f"days remaining: {(end_time - chain.time()) / 3600 / 24}")
            except Exception as ex:
                test_exception = ex
                break

    # hpb_index = bucket_math.priceToIndex(pool1.hdp())
    # print("After test:\n" + test_utils.dump_book(pool1, bucket_math, MIN_BUCKET, hpb_index))
    print(f"elapsed time: {(chain.time()-start_time) / 3600 / 24} days")
    print(f"actual utilization: {pool1.getPoolActualUtilization() / 1e18}")
    if test_exception:
        raise test_exception
