import pytest
from sdk import *
from brownie import test, network, Contract, ERC20PoolFactory, ERC20Pool
from brownie.exceptions import VirtualMachineError
from brownie.network.state import TxHistory
from brownie.utils import color

ZRO_ADD = '0x0000000000000000000000000000000000000000'
MIN_PRICE = 99836282890
MAX_PRICE = 1_004_968_987606512354182109771

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

    ajna_protocol = AjnaProtocol()
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
    scaled_factory = ERC20PoolFactory.deploy({"from": deployer})
    scaled_factory.deployPool(MKR_ADDRESS, DAI_ADDRESS, 0.05 * 1e18, {"from": deployer})
    return ERC20Pool.at(
        scaled_factory.deployedPools("2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2", MKR_ADDRESS, DAI_ADDRESS)
        )


@pytest.fixture
def lenders(ajna_protocol, scaled_pool):
    amount = 200_000 * 10**18  # 200,000 DAI for each lender
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())

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
    dai_client = ajna_protocol.get_token(scaled_pool.quoteToken())
    mkr_client = ajna_protocol.get_token(scaled_pool.collateral())

    borrowers = []
    for _ in range(10):
        borrower = ajna_protocol.add_borrower()

        mkr_client.top_up(borrower, amount)
        mkr_client.approve_max(scaled_pool, borrower)
        dai_client.approve_max(scaled_pool, borrower)

        borrowers.append(borrower)

    return borrowers


class ScaledPoolUtils:
    def __init__(self, ajna_protocol: AjnaProtocol):
        self.bucket_math = ajna_protocol.bucket_math

    @staticmethod
    def get_origination_fee(pool: ERC20Pool, amount):
        fee_rate = max(pool.interestRate() / 52, 0.0005 * 10**18)
        assert fee_rate >= (0.0005 * 10**18)
        assert fee_rate < (100 * 10**18)
        return fee_rate * amount / 10**18

    @staticmethod
    def price_to_index_safe(pool, price):
        if price < MIN_PRICE:
            return pool.priceToIndex(MIN_PRICE)
        elif price > MAX_PRICE:
            return pool.priceToIndex(MAX_PRICE)
        else:
            return pool.priceToIndex(price)


@pytest.fixture
def scaled_pool_utils(ajna_protocol):
    return ScaledPoolUtils(ajna_protocol)


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
    def validate_pool(pool):
        # if pool is collateralized...
        if pool.lupIndex() > ScaledPoolUtils.price_to_index_safe(pool, pool.htp()):
            # ...ensure debt is less than the size of the pool
            assert pool.borrowerDebt <= pool.poolSize()

        # if there are no borrowers in the pool, ensure there is no debt
        if pool.totalBorrowers() == 0:
            assert pool.borrowerDebt() == 0

        # totalBorrowers should be decremented as borrowers repay debt
        if pool.totalBorrowers() > 0:
            assert pool.borrowerDebt() > 0


    @staticmethod
    def dump_book(pool, min_bucket_index, max_bucket_index, with_headers=True, csv=False) -> str:
        """
        :param pool:             pool contract for which report shall be generated
        :param min_bucket_index: highest-priced bucket from which to iterate downward in price
        :param max_bucket_index: lowest-priced bucket
        :param with_headers:     print column headings
        :param csv:              export as CSV for importing into a spreadsheet
        :return:                 multi-line string
        """
        assert min_bucket_index < max_bucket_index

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

        lup_index = pool.lupIndex()
        htp_index = ScaledPoolUtils.price_to_index_safe(pool, pool.htp())

        lines = []
        if with_headers:
            if csv:
                lines.append("Index,Price,Pointer,Quote,Collateral,LP Outstanding,Scale")
            else:
                lines.append(j('Index') + j('Price') + j('Pointer') + j('Quote') + j('Collateral')
                             + j('LP Outstanding') + j('Scale'))
        for i in range(min_bucket_index, max_bucket_index):
            price = pool.indexToPrice(i)
            pointer = ""
            if i == lup_index:
                pointer += "LUP"
            if i == htp_index:
                pointer += "HTP"
            try:
                (
                    bucket_quote,
                    bucket_collateral,
                    bucket_lpAccumulator,
                    bucket_scale
                ) = pool.bucketAt(i)
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
    def summarize_pool(pool):
        print(f"actual utlzn:   {pool.poolActualUtilization()/1e18:>12.1%}  "
              f"target utlzn: {pool.poolTargetUtilization()/1e18:>10.1%}   "
              f"collateralization: {pool.poolCollateralization()/1e18:>7.1%}  "
              f"borrowerDebt: {pool.borrowerDebt()/1e18:>12.1f}  "
              f"pendingInf: {pool.pendingInflator()/1e18:>20.18f}")

        contract_quote_balance = Contract(pool.quoteToken()).balanceOf(pool)
        reserves = contract_quote_balance + pool.borrowerDebt() - pool.poolSize()
        pledged_collateral = pool.pledgedCollateral()
        if pledged_collateral > 0:
            ptp = pool.borrowerDebt() * 10 ** 18 / pledged_collateral
            ptp_index = pool.priceToIndex(ptp)
            ru = pool.depositAt(ptp_index)
        else:
            ptp = 0
            ru = 0
        print(f"contract q bal: {contract_quote_balance/1e18:>12.1f}  "
              f"reserves:   {reserves/1e18:>12.1f}   "
              f"pledged collaterl: {pool.pledgedCollateral()/1e18:>7.1f}  "
              f"ptp: {ptp/1e18:>10.3f}  "
              f"ru: {ru/1e18:>12.1f}  "
              f"sum: {pool.poolSize()/1e18:>12.1f}  "
              f"rate:     {pool.interestRate()/1e18:>10.6f}")


@pytest.fixture
def test_utils():
    return TestUtils
