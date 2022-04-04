import pytest
from sdk import *
from brownie import test, network, PositionManager
from brownie.network.state import TxHistory
from brownie.utils import color


@pytest.fixture(autouse=True)
def get_capsys(capsys):
    if not TestUtils.capsys:
        TestUtils.capsys = capsys


@pytest.fixture()
def ajna_protocol() -> AjnaProtocol:
    protocol_definition = (
        InitialProtocolStateBuilder()
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .deploy_pool(MKR_ADDRESS, DAI_ADDRESS)
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
def bucket_math(ajna_protocol):
    return ajna_protocol.bucket_math


@pytest.fixture
def mkr_dai_pool(ajna_protocol):
    return ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS).get_contract()


@pytest.fixture
def position_manager(deployer):
    position_manager = PositionManager.deploy({"from": deployer})
    yield position_manager


@pytest.fixture
def lenders(ajna_protocol, mkr_dai_pool):
    amount = 200_000 * 10**18  # 200,000 DAI for each lender
    token = ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS).get_quote_token()

    lenders = []
    for _ in range(10):
        lender = ajna_protocol.add_lender()

        token.top_up(lender, amount)
        token.approve_max(mkr_dai_pool, lender)

        lenders.append(lender)

    return lenders


@pytest.fixture
def borrowers(ajna_protocol, mkr_dai_pool):
    amount = 100 * 10**18  # 100 MKR for each borrower
    dai_token = ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS).get_quote_token()
    mkr_token = ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS).get_collateral_token()

    borrowers = []
    for _ in range(10):
        borrower = ajna_protocol.add_borrower()

        mkr_token.top_up(borrower, amount)
        mkr_token.approve_max(mkr_dai_pool, borrower)
        dai_token.approve_max(mkr_dai_pool, borrower)

        borrowers.append(borrower)

    return borrowers


class TestUtils:
    capsys = None

    @staticmethod
    def get_usage(gas) -> str:
        in_eth = gas * 50 * 10e-9
        in_fiat = in_eth * 3500
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

            sorted_gas = (
                self._filter_methods(sorted(gas.items()))
                if self._method_names
                else sorted(gas.items())
            )

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
                    sorted(
                        functions.items(),
                        key=lambda value: value[1]["avg"],
                        reverse=True,
                    )
                )
                for ix, (fn_name, values) in enumerate(sorted_functions.items()):
                    prefix = (
                        "\u2514\u2500" if ix == len(functions) - 1 else "\u251c\u2500"
                    )
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


@pytest.fixture
def test_utils():
    return TestUtils
