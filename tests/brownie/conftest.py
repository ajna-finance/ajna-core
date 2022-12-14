import math
import pytest
from sdk import *
from brownie import test, network, Contract, ERC20PoolFactory, ERC20Pool, PoolInfoUtils
from brownie.exceptions import VirtualMachineError
from brownie.network.state import TxHistory
from brownie.utils import color

AJNA_ADDRESS = "0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079"
MIN_PRICE = 99836282890
MAX_PRICE = 1_004_968_987606512354182109771
ZRO_ADD = '0x0000000000000000000000000000000000000000'

@pytest.fixture(autouse=True)
def get_capsys(capsys):
    if not TestUtils.capsys:
        TestUtils.capsys = capsys


@pytest.fixture()
def ajna_protocol() -> AjnaProtocol:
    protocol_definition = (
        InitialProtocolStateBuilder()
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .add_token(WETH_ADDRESS, WETH_RESERVE_ADDRESS)
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
    )

    ajna_protocol = AjnaProtocol(AJNA_ADDRESS)
    ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(
        protocol_definition.build()
    )

    return ajna_protocol


@pytest.fixture
def deployer(ajna_protocol):
    return ajna_protocol.deployer


@pytest.fixture
def dai(ajna_protocol):
    return ajna_protocol.get_token(DAI_ADDRESS).get_contract()


@pytest.fixture
def mkr(ajna_protocol):
    return ajna_protocol.get_token(MKR_ADDRESS).get_contract()


@pytest.fixture
def weth(ajna_protocol):
    return ajna_protocol.get_token(WETH_ADDRESS).get_contract()


@pytest.fixture
def scaled_pool(deployer):
    scaled_factory = ERC20PoolFactory.deploy(AJNA_ADDRESS, {"from": deployer})
    scaled_factory.deployPool(MKR_ADDRESS, DAI_ADDRESS, 0.05 * 1e18, {"from": deployer})
    return ERC20Pool.at(
        scaled_factory.deployedPools("2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2", MKR_ADDRESS, DAI_ADDRESS)
        )


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    amount = 200_000 * 10**18  # 200,000 DAI for each lender
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())

    lenders = []
    for _ in range(10):
        lender = ajna_protocol.add_lender()

        dai_client.top_up(lender, amount)
        dai_client.approve_max(scaled_pool, lender)

        lenders.append(lender)

    return lenders


@pytest.fixture
def borrowers(ajna_protocol, scaled_pool):
    amount = 100 * 10**18  # 100 MKR for each borrower
    dai_client = ajna_protocol.get_token(scaled_pool.quoteTokenAddress())
    mkr_client = ajna_protocol.get_token(scaled_pool.collateralAddress())

    borrowers = []
    for _ in range(10):
        borrower = ajna_protocol.add_borrower()

        mkr_client.top_up(borrower, amount)
        mkr_client.approve_max(scaled_pool, borrower)
        dai_client.approve_max(scaled_pool, borrower)

        borrowers.append(borrower)

    return borrowers


# Layer of abstraction between pool contracts and brownie tests
class PoolHelper:
    def __init__(self, ajna_protocol: AjnaProtocol, pool):
        self.loans = ajna_protocol.loans
        self.pool = pool
        self.pool_info_utils = ajna_protocol.pool_info_utils

    # TODO: Move this functionality into SDK to insulate consumer from implementation logic.

    def borrowerInfo(self, borrower_address):
        # returns (debt, collateral, mompFactor)
        return self.pool_info_utils.borrowerInfo(self.pool.address, borrower_address)

    def bucketInfo(self, index):
        # returns (index, price, quoteTokens, collateral, bucketLPs, scale, exchangeRate)
        return self.pool_info_utils.bucketInfo(self.pool.address, index)

    def collateralToken(self):
        return Contract(self.pool.collateralAddress())

    def debt(self):
        (debt, accruedDebt, debtInAuction) = self.pool.debtInfo()
        return debt

    def hpb(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return hpb

    def htp(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return htp

    def indexToPrice(self, price_index: int):
        return self.pool_info_utils.indexToPrice(price_index)

    def lenderInfo(self, index, lender_address):
        # returns (lpBalance, lastQuoteDeposit)
        return self.pool.lenderInfo(index, lender_address)

    def loansInfo(self):
        # returns (poolSize, loansCount, maxBorrower, pendingInflator, pendingInterestFactor)
        # Not to be confused with pool.loansInfo which returns (maxBorrower, maxThresholdPrice, noOfLoans)
        return self.pool_info_utils.poolLoansInfo(self.pool.address)

    def lup(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return lup

    def lupIndex(self):
        (hpb, hpbIndex, htp, htpIndex, lup, lupIndex) = self.pool_info_utils.poolPricesInfo(self.pool.address)
        return lupIndex

    def priceToIndex(self, price):
        return self.pool_info_utils.priceToIndex(price)

    def quoteToken(self):
        return Contract(self.pool.quoteTokenAddress())

    def utilizationInfo(self):
        return self.pool_info_utils.poolUtilizationInfo(self.pool.address)

    def get_origination_fee(self, amount):
        (interest_rate, _) = self.pool.interestRateInfo()
        fee_rate = max(interest_rate / 52, 0.0005 * 10**18)
        assert fee_rate >= (0.0005 * 10**18)
        assert fee_rate < (100 * 10**18)
        return fee_rate * amount / 10**18

    def price_to_index_safe(self, price):
        if price < MIN_PRICE:
            return self.pool_info_utils.priceToIndex(MIN_PRICE)
        elif price > MAX_PRICE:
            return self.pool_info_utils.priceToIndex(MAX_PRICE)
        else:
            return self.pool_info_utils.priceToIndex(price)


class LoansHeapUtils:
    @staticmethod
    def _worst_case(a, root, level, offset):
        """
        Args:
            a:      pre-allocated list in which we build up the values to insert in order
            root:   index 0, max node, head
            level:  depth of the tree being created
            offset: value by which all elements will be offset

        Returns:
            mutated list
        """
        if level == 0:
            a[root] = offset
            return offset + 1
        else:
            offset = LoansHeapUtils._worst_case(a, 2 * root + 1, level - 1, offset)
            offset = LoansHeapUtils._worst_case(a, 2 * root + 2, level - 1, offset)
            a[root] = offset
            return offset + 1

    @staticmethod
    def _find_next_power_of_two(n):
        return 2 ** (int(math.log(n - 1, 2)) + 1)

    @staticmethod
    def worst_case_heap_orientation(n, scale=1):
        # build a larger tree which can hold all required nodes
        tree_size = LoansHeapUtils._find_next_power_of_two(n)
        a = [0] * tree_size
        max_depth = int(math.log(tree_size, 2) - 1)
        # populate the tree
        LoansHeapUtils._worst_case(a, 0, max_depth, 0)
        # scale the tree
        a = list(map(lambda i: i * scale, a))
        # return the first n elements
        return a[:n]


class TestUtils:
    capsys = None

    @staticmethod
    def get_usage(gas) -> str:
        in_eth = gas * 50 * 1e-9
        in_fiat = in_eth * 1700
        return f"Gas amount: {gas}, Gas in ETH: {in_eth}, Gas price: ${in_fiat}"

    class GasWatcher(object):
        _cache = {}

        def __init__(self, method_names=None):
            self._method_names = method_names

        def __enter__(self):
            self._start_profiling()
            return TestUtils.GasWatcher

        def __exit__(self, exc_type, exc_value, exc_traceback):
            self._print()
            self._end_profiling()

        # @notice print the gas statistics of the txs collected since last cleared
        def _print(self):
            with TestUtils.capsys.disabled():
                for line in self._build_cust_output():
                    print(line)

                print("==================================")

        def _filter_methods(self, gas):
            def by_methods(x):
                contract, function = x[0].split(".", 1)
                for method in self._method_names:
                    if method in function:
                        return x

            return filter(by_methods, gas)

        def _build_cust_output(self):
            gas = network.state.TxHistory().gas_profile

            sorted_gas = self._filter_methods(sorted(gas.items())) if self._method_names else sorted(gas.items())

            grouped_by_contract = {}
            padding = {}

            lines = [""]

            for full_name, values in sorted_gas:
                contract, function = full_name.split(".", 1)
                # calculate padding to get table-like formatting
                padding["fn"] = max(padding.get("fn", 0), len(str(function)))
                for k, v in values.items():
                    padding[k] = max(padding.get(k, 0), len(str(v)))

                # group functions with payload by contract name
                if contract in grouped_by_contract.keys():
                    grouped_by_contract[contract][function] = values
                else:
                    grouped_by_contract[contract] = {function: values}

            for contract, functions in grouped_by_contract.items():
                lines.append(f"{color('bright magenta')}{contract}{color} <Contract>")
                sorted_functions = dict(
                    sorted(functions.items(), key=lambda value: value[1]["avg"], reverse=True)
                )
                for ix, (fn_name, values) in enumerate(sorted_functions.items()):
                    prefix = "\u2514\u2500" if ix == len(functions) - 1 else "\u251c\u2500"
                    fn_name = fn_name.ljust(padding["fn"])
                    values["avg"] = int(values["avg"])
                    values = {k: str(v).rjust(padding[k]) for k, v in values.items()}
                    lines.append(
                        f"   {prefix} {fn_name} -  avg: {values['avg']}  avg (confirmed):"
                        f" {values['avg_success']}  low: {values['low']}  high: {values['high']}"
                        f"  tx count: {values['count']}"
                    )

            return lines + [""]

        def _start_profiling(self):
            TestUtils.GasWatcher._cache = TxHistory().gas_profile.copy()
            TxHistory().gas_profile.clear()

        def _combined_mean(self, old_avg, old_count, new_avg, new_count):
            prod_count_avgs = old_count * old_avg + new_count * new_avg
            total_count = old_count + new_count
            return prod_count_avgs // total_count

        def _combine_profiles(self, old, new):
            overlap = {}
            for method in old:
                if new.get(method):
                    overlap[method] = {}

                    overlap[method]["high"] = max(
                        old[method]["high"], new[method]["high"]
                    )
                    overlap[method]["low"] = min(old[method]["low"], new[method]["low"])

                    # avg
                    overlap[method]["avg"] = self._combined_mean(
                        old[method]["avg"],
                        old[method]["count"],
                        new[method]["avg"],
                        new[method]["count"],
                    )

                    overlap[method]["avg_success"] = self._combined_mean(
                        old[method]["avg_success"],
                        old[method]["count_success"],
                        new[method]["avg_success"],
                        new[method]["count_success"],
                    )

                    overlap[method]["count"] = (
                        old[method]["count"] + new[method]["count"]
                    )
                    overlap[method]["count_success"] = (
                        old[method]["count_success"] + new[method]["count_success"]
                    )

            # include unique methods, overlap overwrites all duplicates
            return {**old, **new, **overlap}

        def _end_profiling(self):
            network.state.TxHistory().gas_profile = self._combine_profiles(
                TestUtils.GasWatcher._cache, network.state.TxHistory().gas_profile
            )

    @staticmethod
    def validate_pool(pool_helper, borrowers):
        pool = pool_helper.pool
        poolDebt = pool_helper.debt()

        # if pool is collateralized...
        if pool_helper.lupIndex() > pool_helper.price_to_index_safe(pool_helper.htp()):
            # ...ensure debt is less than the size of the pool
            assert poolDebt <= pool.depositSize()

        # if there are no borrowers in the pool, ensure there is no debt
        (_, loansCount, _, inflator, interestFactor) = pool_helper.loansInfo()
        if loansCount == 0:
            assert poolDebt == 0

        # loan count should be decremented as borrowers repay debt
        if loansCount > 0:
            assert poolDebt > 0

        borrowers_with_debt = 0
        for borrower in borrowers:
            (debt, _, _) = pool_helper.borrowerInfo(borrower.address)
            if debt > 0:
                borrowers_with_debt += 1
        assert borrowers_with_debt == loansCount

    @staticmethod
    def dump_book(pool_helper, with_headers=True, csv=False) -> str:
        """
        :param pool_helper:      simplifies interaction with pool contracts
        :param min_bucket_index: highest-priced bucket from which to iterate downward in price
        :param max_bucket_index: lowest-priced bucket
        :param with_headers:     print column headings
        :param csv:              export as CSV for importing into a spreadsheet
        :return:                 multi-line string
        """
        pool = pool_helper.pool

        # formatting shortcuts
        w = 15
        def j(text):
            return str.rjust(text, w)
        def nw(wad):
            return wad/1e18
        def ny(ray):
            return ray/1e27
        def fw(wad):
            return f"{nw(wad):>{w}.3f}"
        def fy(ray):
            return f"{ny(ray):>{w}.3f}"

        lup_index = pool_helper.lupIndex()
        htp_index = pool_helper.price_to_index_safe(pool_helper.htp())

        pledged_collateral = pool.pledgedCollateral()
        ptp_index = pool_helper.price_to_index_safe(int(pool_helper.debt() * 1e18 / pledged_collateral)) \
            if pledged_collateral > 0 else 0

        min_bucket_index = max(0, pool_helper.priceToIndex(pool_helper.hpb()) - 3)  # HPB
        max_bucket_index = min(7388, max(lup_index, htp_index) + 3) if htp_index < 7388 else min(7388, lup_index + 3)
        assert min_bucket_index < max_bucket_index

        lines = []
        if with_headers:
            if csv:
                lines.append("Index,Price,Pointer,Quote,Collateral,LP Outstanding,Scale")
            else:
                lines.append(j('Index') + j('Price') + j('Pointer') + j('Quote') + j('Collateral')
                             + j('LP Outstanding') + j('Scale'))
        for i in range(min_bucket_index, max_bucket_index):
            price = pool_helper.indexToPrice(i)
            pointer = ""
            if i == lup_index:
                pointer += "LUP"
            if i == htp_index:
                pointer += "HTP"
            if i == ptp_index:
                pointer += "PTP"
            try:
                (
                    _,
                    bucket_quote,
                    bucket_collateral,
                    bucket_lpAccumulator,
                    bucket_scale,
                    _
                ) = pool_helper.bucketInfo(i)
            except VirtualMachineError as ex:
                lines.append(f"ERROR retrieving bucket {i} at price {price} ({price / 1e18})")
                continue
            if csv:
                lines.append(','.join([j(str(i)), nw(price), pointer, nw(bucket_quote), nw(bucket_collateral),
                                       ny(bucket_lpAccumulator), nw(bucket_scale)]))
            else:
                lines.append(''.join([j(str(i)), fw(price), j(pointer), fw(bucket_quote), fw(bucket_collateral),
                                      fy(bucket_lpAccumulator), f"{nw(bucket_scale):>{w}.9f}"]))
        return '\n'.join(lines)

    @staticmethod
    def summarize_pool(pool_helper):
        pool = pool_helper.pool
        poolDebt = pool_helper.debt()

        (_, poolCollateralization, poolActualUtilization, poolTargetUtilization) = pool_helper.utilizationInfo()
        (_, loansCount, _, _, _) = pool_helper.loansInfo()
        print(f"actual utlzn:   {poolActualUtilization/1e18:>12.1%}  "
              f"target utlzn:   {poolTargetUtilization/1e18:>12.1%}  "
              f"collateralization: {poolCollateralization/1e18:>9.1%}  "
              f"borrowerDebt:   {poolDebt/1e18:>12.1f}  "
              f"loan count:     {loansCount:>8}")

        contract_quote_balance = pool_helper.quoteToken().balanceOf(pool)
        reserves = contract_quote_balance + poolDebt - pool.depositSize()
        pledged_collateral = pool.pledgedCollateral()
        (interest_rate, _) = pool.interestRateInfo()
        if pledged_collateral > 0:
            ptp = poolDebt * 10 ** 18 / pledged_collateral
            ptp_index = pool_helper.priceToIndex(ptp)
        else:
            ptp = 0
        print(f"contract q bal: {contract_quote_balance/1e18:>12.1f}  "
              f"deposit:        {pool.depositSize()/1e18:>12.1f}  "
              f"reserves:       {reserves/1e18:>12.1f}  "
              f"pledged:        {pool.pledgedCollateral()/1e18:>12.1f}  "
              f"rate:           {interest_rate/1e18:>8.4%}")

        lup = pool_helper.lup()
        htp = pool_helper.htp()
        poolCollateral = pool.pledgedCollateral()
        ptp = int(poolDebt * 1e18 / poolCollateral) if poolCollateral else 0
        print(f"lup:            {lup/1e18:>12.3f}  "
              f"htp:            {htp/1e18:>12.3f}  "
              f"ptp:            {ptp/1e18:>12.3f}")


@pytest.fixture
def test_utils():
    return TestUtils
