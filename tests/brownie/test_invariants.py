import brownie
import pytest
from brownie.test import strategy
from brownie import Contract, chain
import hypothesis.strategies as st
from hypothesis.stateful import invariant
from hypothesis._settings import HealthCheck
from conftest import PoolHelper, MAX_PRICE

############## Constants ##############

MAX_BUCKET = 2690
MIN_BUCKET = 2700
NUM_LENDERS = 10
NUM_BORROWERS = 15
NUM_BIDDERS = 5
NUM_KICKERS = 5
NUM_TAKERS = 5
MAX_LEND_AMOUNT = 10000*1e18
MIN_LEND_AMOUNT = 1*1e18
MAX_BORROW_AMOUNT = 1000*1e18
MIN_BORROW_AMOUNT = 1*1e18
MAX_BID_AMOUNT = 10*1e18
MIN_BID_AMOUNT = 1*1e18
MIN_TAKE_AMOUNT = 5*1e16
MAX_TAKE_AMOUNT = 1*1e18
MAX_NUMBER_OF_RULES = 1000
MAX_NUMBER_OF_RUNS = 50

MAX_UINT256 = 2**256-1


class _BasePoolStateMachine:

    """
    This base state machine class contains initialization and invariant
    methods that are shared across multiple stateful tests.
    """

    ############## Strategies ##############

    st_sleep = st.integers(min_value=0, max_value=12 * 360)
    st_index  = st.integers(min_value=MAX_BUCKET, max_value=MIN_BUCKET)
    st_lender = st.integers(min_value=0, max_value=NUM_LENDERS-1)
    st_borrower = st.integers(min_value=0, max_value=NUM_BORROWERS-1)
    st_bidder = st.integers(min_value=0, max_value=NUM_BIDDERS-1)
    st_kicker = st.integers(min_value=0, max_value=NUM_KICKERS-1)
    st_taker = st.integers(min_value=0, max_value=NUM_TAKERS-1)

    st_lend_amount = strategy("uint256", min_value=MIN_LEND_AMOUNT, max_value=MAX_LEND_AMOUNT)
    st_borrow_amount = strategy("uint256", min_value=MIN_BORROW_AMOUNT, max_value=MAX_BORROW_AMOUNT)
    st_bid_amount = strategy("uint256", min_value=MIN_BID_AMOUNT, max_value=MAX_BID_AMOUNT)
    st_take_amount = strategy("uint256", min_value=MIN_TAKE_AMOUNT, max_value=MAX_TAKE_AMOUNT)


    ############## Initialization ##############

    def __init__(self, ajna_protocol, scaled_pool, lenders, borrowers, bidders, kickers, takers):
        self.pool = scaled_pool
        self.lenders = lenders
        self.borrowers = borrowers
        self.bidders = bidders
        self.kickers = kickers
        self.takers = takers
        self.pool_helper = PoolHelper(ajna_protocol, scaled_pool)


    ############## Invariants ##############

    @invariant()
    def pool_collateral_balance(self):

        # collateral inflows:
        #   - pledge collateral (borrower)
        #   - added collateral in bucket (bidder swap)
        # collateral outflows:
        #   - pull collateral (borrower)
        #   - remove collateral from buckets (any actor with LP in bucket: lender, borrower, kicker, taker)
        #   - auction take

        buckets_collateral = 0

        for index in range(MAX_BUCKET, MIN_BUCKET + 1):
            (_, bucket_collateral, _, _, _) = self.pool.bucketInfo(index)
            buckets_collateral += bucket_collateral

        # Invariant 1: Pool collateral token balance = sum of collateral across all borrowers + sum of claimable collateral across all buckets
        assert self.pool_helper.collateralToken().balanceOf(self.pool) == self.pool.pledgedCollateral() + buckets_collateral

        borrowers_collateral = 0

        for borrower in self.borrowers:
            (_, borrower_collateral, _) = self.pool.borrowerInfo(borrower)
            borrowers_collateral += borrower_collateral

        # Invariant 2: total pledged collateral in pool = sum of collateral pledged across all borrowers
        assert borrowers_collateral == self.pool.pledgedCollateral()

    @invariant()
    def pool_quote_balance(self):

        # quote inflows:
        #   - add quote tokens (lender)
        #   - repay debt (borrower)
        #   - kick loan (kicker, lender)
        # quote outflows:
        #   - draw debt (borrower)
        #   - remove quote tokens from bucket (any actor with LP in bucket: lender, borrower, kicker, taker)
        #   - claim bonds (kicker, lender)
        #   - reward reserves auction 

        liquidation_bonds = 0
        for kicker in self.kickers:
            (claimable, locked) = self.pool.kickerInfo(kicker)
            liquidation_bonds += claimable + locked

        # Invariant 3: Pool quote token balance (with penalties) >= liquidation bonds (locked + claimable) + pool deposit size - pool debt
        assert self.pool_helper.quoteToken().balanceOf(self.pool) >= liquidation_bonds + self.pool_helper.pool.depositSize() - self.pool_helper.debt()

    @invariant()
    def pool_global_debt(self):
        borrowers_debt = 0

        for borrower in self.borrowers:
            (borrower_debt, _, _) = self.pool.borrowerInfo(borrower)
            borrowers_debt += borrower_debt

        # Invariant 4: Global Debt Accumulator = sum of debt across all borrowers
        assert self.pool.totalT0Debt() == borrowers_debt

    @invariant()
    def pool_buckets(self):
        for index in range(MAX_BUCKET, MIN_BUCKET + 1):
            total_lenders_lps = 0

            for lender in self.lenders:
                (lender_lps, _) = self.pool.lenderInfo(index, lender)
                total_lenders_lps += lender_lps

            for borrower in self.borrowers:
                (borrower_lps, _) = self.pool.lenderInfo(index, borrower)
                total_lenders_lps += borrower_lps

            for bidder in self.bidders:
                (bidder_lps, _) = self.pool.lenderInfo(index, bidder)
                total_lenders_lps += bidder_lps

            for kicker in self.kickers:
                (kicker_lps, _) = self.pool.lenderInfo(index, kicker)
                total_lenders_lps += kicker_lps

            for taker in self.takers:
                (taker_lps, _) = self.pool.lenderInfo(index, taker)
                total_lenders_lps += taker_lps

            (bucket_lps, bucket_collateral, _, bucket_deposit, _) = self.pool.bucketInfo(index)
            # Invariant 5: sum of actors lps in bucket = bucket lps accumulator
            assert bucket_lps == total_lenders_lps

            # Invariant 6: if no deposit / collateral in bucket then bucket LP should be 0
            if bucket_collateral == 0 and bucket_deposit == 0:
                assert bucket_lps == 0


    @invariant()
    def pool_debt_in_auction(self):
        auctioned_borrowers_debt = 0
        for borrower in self.borrowers:
            (_, _, _, kick_time, _, _, _, _, _, _) = self.pool.auctionInfo(borrower)
            if kick_time != 0:
                (borrower_debt, _, _) = self.pool.borrowerInfo(borrower)
                auctioned_borrowers_debt += borrower_debt

        # Invariant 7: debt in auction accumulator = sum of debt across all auctioned borrowers
        assert self.pool.totalT0DebtInAuction() == auctioned_borrowers_debt

    @invariant()
    def pool_auction_bonds(self):
        (total_bond_escrowed, _, _, _) = self.pool.reservesInfo()

        kicker_bonds_locked = 0
        for kicker in self.kickers:
            (_, locked) = self.pool.kickerInfo(kicker)
            kicker_bonds_locked += locked

        auction_bonds_locked = 0
        for borrower in self.borrowers:
            (_, _, bond_size, _, _, _, _, _, _, _) = self.pool.auctionInfo(borrower)
            auction_bonds_locked += bond_size

        # Invariant 8: sum of bonds across all auctions = sum of locked balances across all kickers = total bond escrowed accumulator
        assert total_bond_escrowed == kicker_bonds_locked == auction_bonds_locked

    @invariant()
    def pool_loans_and_auctions(self):
        (_, _, number_of_loans) = self.pool.loansInfo()

        number_of_auctions = 0
        borrowers_with_debt = 0
        for borrower in self.borrowers:
            (borrower_debt, _, _) = self.pool.borrowerInfo(borrower)
            if borrower_debt != 0:
                borrowers_with_debt += 1

                (_, _, _, kick_time, _, _, _, _, _, _) = self.pool.auctionInfo(borrower)
                if kick_time != 0:
                    number_of_auctions += 1

        # Invariant 9: number of borrowers with debt = number of loans + number of auctioned borrowers
        assert borrowers_with_debt == number_of_loans + number_of_auctions


    ############## Teardown ##############

    def teardown(self):
        # TODO: verify pool invariants / health at the end of each run
        print('Tear down')


    ############## Utilities ##############

    @staticmethod
    def _print_rule_result(message, success):
        status = "succeeded" if success else "failed"
        print(f"{message} {status}")


@pytest.fixture
def BasePoolStateMachine():
    yield _BasePoolStateMachine


@pytest.fixture
def borrowers(ajna_protocol, scaled_pool):
    collateral_client = ajna_protocol.get_token(scaled_pool.collateralAddress())
    quote_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(150_000 * 10**18 / NUM_BORROWERS)
    borrowers = []
    print("Initializing borrowers")
    for _ in range(NUM_BORROWERS):
        borrower = ajna_protocol.add_borrower()
        collateral_client.top_up(borrower, amount)
        collateral_client.approve_max(scaled_pool, borrower)
        quote_client.top_up(borrower, 100_000 * 10**18)  # for repayment of interest
        quote_client.approve_max(scaled_pool, borrower)
        assert collateral_client.get_contract().balanceOf(borrower) >= amount
        borrowers.append(borrower)
    return borrowers


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    quote_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(3_000_000_000 * 10**18 / NUM_LENDERS)
    lenders = []
    print("Initializing lenders")
    for _ in range(NUM_LENDERS):
        lender = ajna_protocol.add_lender()
        quote_client.top_up(lender, amount)
        quote_client.approve_max(scaled_pool, lender)
        lenders.append(lender)
    return lenders


@pytest.fixture
def bidders(ajna_protocol, scaled_pool):
    collateral_client = ajna_protocol.get_token(scaled_pool.collateralAddress())
    amount = int(100 * 10**18 / NUM_BIDDERS)
    bidders = []
    print("Initializing bidders")
    for _ in range(NUM_BIDDERS):
        bidder = ajna_protocol.add_borrower()
        collateral_client.top_up(bidder, amount)
        collateral_client.approve_max(scaled_pool, bidder)
        assert collateral_client.get_contract().balanceOf(bidder) >= amount
        bidders.append(bidder)
    return bidders


@pytest.fixture
def kickers(ajna_protocol, scaled_pool):
    quote_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(3_000_000_000 * 10**18 / NUM_KICKERS)
    kickers = []
    print("Initializing kickers")
    for _ in range(NUM_KICKERS):
        kicker = ajna_protocol.add_lender()
        quote_client.top_up(kicker, amount)
        quote_client.approve_max(scaled_pool, kicker)
        kickers.append(kicker)
    return kickers


@pytest.fixture
def takers(ajna_protocol, scaled_pool):
    quote_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    amount = int(3_000_000_000 * 10**18 / NUM_TAKERS)
    takers = []
    print("Initializing takers")
    for _ in range(NUM_TAKERS):
        taker = ajna_protocol.add_lender()
        quote_client.top_up(taker, amount)
        quote_client.approve_max(scaled_pool, taker)
        takers.append(taker)
    return takers

############## Tests ##############


def test_stateful_borrow_repay(
    BasePoolStateMachine,
    state_machine,
    ajna_protocol,
    scaled_pool,
    lenders,
    borrowers,
    bidders,
    kickers,
    takers
    ):

    """
    Stateful test that verifies draw debt / repay behavior
    """

    class PoolStateMachine(BasePoolStateMachine):


        def setup(self):
            # add some initial liquidity in the pool
            self.pool.addQuoteToken(MAX_LEND_AMOUNT, MAX_BUCKET, chain.time() + 30, {"from": lenders[0]})


        ############## Lender rules ##############

        def rule_add_quote_token(self, st_lend_amount, st_index, st_lender, st_sleep):
            # lend an arbitrary amount
            lender = lenders[st_lender]

            lender_balance = self.pool_helper.quoteToken().balanceOf(lender)

            lend_amount = min(lender_balance, st_lend_amount)

            success = True

            try:
                self.pool.addQuoteToken(lend_amount, st_index, chain.time() + 30, {"from": lenders[st_lender]})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"lender{st_lender}: add quote token {lend_amount} at index {st_index}",
                success
            )


        def rule_swap_quote_for_collateral(self, st_lend_amount, st_bid_amount, st_index, st_lender, st_bidder, st_sleep):

            success = True

            try:
                (_, bucket_collateral, _, _, _) = self.pool.bucketInfo(st_index)
                if bucket_collateral < st_bid_amount:
                    self.pool.addCollateral(st_bid_amount, st_index, chain.time() + 30, {"from": bidders[st_bidder]})

                self.pool.addQuoteToken(st_lend_amount, st_index, chain.time() + 30, {"from": lenders[st_lender]})
                self.pool.removeCollateral(st_bid_amount, st_index, {"from": lenders[st_lender]})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"lender{st_lender}: swap quote {st_lend_amount} for collateral {st_bid_amount} from index {st_index}",
                success
            )
                

        ############## Borrower rules ##############

        def rule_draw_debt(self, st_borrow_amount, st_lender, st_borrower, st_sleep):
            # borrow an arbitrary amount

            success = True

            try:
                (min_debt, _, _, _) = self.pool_helper.utilizationInfo()
                st_borrow_amount = max(st_borrow_amount, min_debt + 100*1e18) # borrow at least the min debt amount from pool

                pool_quote_on_deposit = self.pool_helper.pool.depositSize() - self.pool_helper.debt()
                if pool_quote_on_deposit < st_borrow_amount:
                    self.pool.addQuoteToken(st_borrow_amount + 100*1e18, MAX_BUCKET, chain.time() + 30, {"from": lenders[st_lender]})

                pool_price = self.pool_helper.lup()
                if pool_price == MAX_PRICE:  # if there is no LUP,
                    pool_price = self.pool_helper.hpb()  # use the highest-priced bucket with deposit

                collateral_to_deposit = st_borrow_amount / pool_price * 2 * 10**18

                self.pool.drawDebt(borrowers[st_borrower], st_borrow_amount, 7000, collateral_to_deposit, {"from": borrowers[st_borrower]})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"borrower{st_borrower}: draw debt {st_borrow_amount} and pledge {collateral_to_deposit}",
                success
            )


        def rule_repay_debt(self, st_borrow_amount, st_borrower, st_sleep):
            # repay an arbitrary amount
            borrower = borrowers[st_borrower]

            (debt, _, _) = self.pool_helper.borrowerInfo(borrower)
            repay_amount = min(debt, st_borrow_amount)

            borrower_balance = self.pool_helper.quoteToken().balanceOf(borrower)
            repay_amount = min(repay_amount, borrower_balance)

            success = True

            try:
                self.pool.repayDebt(borrower, repay_amount, 0, borrower, 7000, {"from": borrower})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"borrower{st_borrower}: repay debt {repay_amount}",
                success
            )


        ############## Bidder rules ##############

        def rule_swap_collateral_for_quote(self, st_bid_amount, st_lend_amount, st_index, st_lender, st_bidder, st_sleep):
            # bid an arbitrary amount

            success = True

            try:
                (_, _, _, bucket_deposit, _) = self.pool.bucketInfo(st_index)
                if bucket_deposit < st_lend_amount:
                    self.pool.addQuoteToken(st_lend_amount, st_index, chain.time() + 30, {"from": lenders[st_lender]})

                self.pool.addCollateral(st_bid_amount, st_index, chain.time() + 30, {"from": bidders[st_bidder]})
                self.pool.removeQuoteToken(st_lend_amount, st_index, {"from": bidders[st_bidder]})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"bidder{st_bidder}: swap collateral {st_bid_amount} for quote {st_lend_amount} at index {st_index}",
                success
            )


    settings = {"stateful_step_count": MAX_NUMBER_OF_RULES, "max_examples": MAX_NUMBER_OF_RUNS}
    state_machine(
        PoolStateMachine,
        ajna_protocol,
        scaled_pool,
        lenders,
        borrowers,
        bidders,
        kickers,
        takers,
        settings=settings
    )


@pytest.mark.skip
def test_stateful_auctions(
    BasePoolStateMachine,
    state_machine,
    ajna_protocol,
    scaled_pool,
    lenders,
    borrowers,
    bidders,
    kickers,
    takers
    ):

    """
    Stateful test that verifies auctions behavior
    """

    class PoolStateMachine(BasePoolStateMachine):


        def setup(self):
            # add some initial liquidity in the pool
            self.pool.addQuoteToken(MAX_BORROW_AMOUNT, MAX_BUCKET, chain.time() + 30, {"from": lenders[0]})
            self.pool.addQuoteToken(MAX_BORROW_AMOUNT, MIN_BUCKET, chain.time() + 30, {"from": lenders[0]})


        ############## Borrower rules ##############

        def rule_draw_debt(self, st_borrow_amount, st_lender, st_borrower, st_sleep):
            # borrow an arbitrary amount

            success = True

            # make sure borrower doesn't have any debt or collateral pledged (to make sure kick and take actions succeed)
            (debt, collateral_deposited, _) = self.pool_helper.borrowerInfo(borrowers[st_borrower])
            if debt != 0:
                debt = MAX_UINT256 # make sure the entire debt is repaid

            self.pool.repayDebt(borrowers[st_borrower], debt, collateral_deposited, borrowers[st_borrower], 7000, {"from": borrowers[st_borrower]})

            try:
                (min_debt, _, _, _) = self.pool_helper.utilizationInfo()
                st_borrow_amount = max(st_borrow_amount, min_debt + 100*1e18) # borrow at least the min debt amount from pool

                pool_quote_on_deposit = self.pool_helper.pool.depositSize() - self.pool_helper.debt()
                if pool_quote_on_deposit < st_borrow_amount:
                    self.pool.addQuoteToken(st_borrow_amount + 100*1e18, MAX_BUCKET, chain.time() + 30, {"from": lenders[st_lender]})

                pool_price = self.pool_helper.lup()
                if pool_price == MAX_PRICE:  # if there is no LUP,
                    pool_price = self.pool_helper.hpb()  # use the highest-priced bucket with deposit

                collateral_to_deposit = st_borrow_amount / pool_price * 1.01 * 10**18

                self.pool.drawDebt(borrowers[st_borrower], st_borrow_amount, 7000, collateral_to_deposit, {"from": borrowers[st_borrower]})

                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"borrower{st_borrower}: draw debt {st_borrow_amount} and pledge {collateral_to_deposit}",
                success
            )


        def rule_repay_debt(self, st_borrow_amount, st_borrower, st_sleep):
            # repay an arbitrary amount
            borrower = borrowers[st_borrower]

            (debt, _, _) = self.pool_helper.borrowerInfo(borrower)
            repay_amount = min(debt, st_borrow_amount)

            borrower_balance = self.pool_helper.quoteToken().balanceOf(borrower)
            repay_amount = min(repay_amount, borrower_balance)

            success = True

            try:
                self.pool.repayDebt(borrower, repay_amount, 0, borrower, 7000, {"from": borrower})

                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"borrower{st_borrower}: repay debt {repay_amount}",
                success
            )


        ############## Kicker rules ##############

        def rule_kick_auction(self, st_borrow_amount, st_lender, st_borrower, st_kicker, st_sleep):

            # do not kick if already active
            (_, _, _, kick_time, _, _, _, _, _, _) = self.pool.auctionInfo(borrowers[st_borrower])
            if kick_time != 0:
                return

            success = True

            try:
                # execute borrow rule to ensure loan
                self.rule_draw_debt(st_borrow_amount, st_lender, st_borrower, st_sleep)

                # do not kick if borrower does not have debt
                (debt, _, _) = self.pool_helper.borrowerInfo(borrowers[st_borrower])
                if debt == 0:
                    return

                # skip to make loan kickable
                chain.sleep(86400 * 200)
                chain.mine(2)

                # kick borrower
                self.pool.kick(borrowers[st_borrower], 7_388, {"from": kickers[st_kicker]})

                chain.sleep(st_sleep)
                chain.mine(2)
            except:
                success = False

            self._print_rule_result(
                f"kicker{st_kicker}: kick borrower borrower{st_borrower}",
                success
            )


        ############## Taker rules ##############

        def rule_take_auction(self, st_borrow_amount, st_take_amount, st_lender, st_borrower, st_kicker, st_taker, st_sleep):

            success = True

            # kick if auction not kicked already
            (_, _, _, kick_time, _, _, _, _, _, _) = self.pool.auctionInfo(borrowers[st_borrower])
            if kick_time == 0:
                self.rule_kick_auction(st_borrow_amount, st_lender, st_borrower, st_kicker, st_sleep)

            try:
                # skip to take from auction
                chain.sleep(3600 * 3)
                chain.mine(2)

                self.pool.take(borrowers[st_borrower], st_take_amount, takers[st_taker], bytes(), {"from": takers[st_taker]})
                chain.sleep(st_sleep)
            except:
                success = False

            self._print_rule_result(
                f"taker{st_taker}: take collateral {st_take_amount} from borrower{st_borrower}",
                success
            )


    settings = {"stateful_step_count": MAX_NUMBER_OF_RULES, "max_examples": MAX_NUMBER_OF_RUNS}
    state_machine(
        PoolStateMachine,
        ajna_protocol,
        scaled_pool,
        lenders,
        borrowers,
        bidders,
        kickers,
        takers,
        settings=settings
    )