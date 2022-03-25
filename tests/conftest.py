import pytest
from sdk import *
from brownie import test, network

@pytest.fixture(autouse=True)
def get_capsys(capsys):
    if not TestUtils.capsys:
        TestUtils.capsys = capsys

@pytest.fixture()
def sdk() -> AjnaSdk:
    options_builder = (
        SdkOptionsBuilder()
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .deploy_pool(MKR_ADDRESS, DAI_ADDRESS)
    )

    sdk = AjnaSdk(options_builder.build())
    return sdk


@pytest.fixture
def deployer(sdk):
    return sdk.deployer


@pytest.fixture
def dai(sdk):
    return sdk.get_token(DAI_ADDRESS).get_contract()


@pytest.fixture
def mkr(sdk):
    return sdk.get_token(MKR_ADDRESS).get_contract()


# TODO: convert to deploying all necessary libraries "libraries(deployer)"
@pytest.fixture
def bucket_math(sdk):
    return sdk.bucket_math


@pytest.fixture
def mkr_dai_pool(sdk):
    return sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS).get_contract()


@pytest.fixture
def lenders(sdk, mkr_dai_pool):
    amount = 200_000 * 10**18  # 200,000 DAI for each lender

    lenders = []
    for _ in range(10):
        lender = sdk.add_lender()
        token = sdk.get_pool_quote_token(mkr_dai_pool)

        token.top_up(lender, amount)
        token.approve_max(mkr_dai_pool, lender)

        lenders.append(lender)

    return lenders


@pytest.fixture
def borrowers(sdk, mkr_dai_pool):
    amount = 100 * 10**18  # 100 MKR for each borrower

    borrowers = []
    for _ in range(10):
        borrower = sdk.add_borrower()
        dai_token = sdk.get_pool_quote_token(mkr_dai_pool)
        mkr_token = sdk.get_pool_collateral_token(mkr_dai_pool)

        mkr_token.top_up(borrower, amount)
        mkr_token.approve_max(mkr_dai_pool, borrower)
        dai_token.approve_max(mkr_dai_pool, borrower)

        borrowers.append(borrower)

    return borrowers

class TestUtils:
    capsys = None

    @staticmethod
    def get_usage(gas) -> str:
        in_eth = gas * 100 * 10e-9
        in_fiat = in_eth * 3000
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
        # @param method_names optional array of the method names to print gas stats for
        def _print(self):
            with TestUtils.capsys.disabled():
                if self._method_names:
                    for line in test.output._build_gas_profile_output():
                        for method in self._method_names:
                            if method in line:
                                print(line)
                else:
                    for line in test.output._build_gas_profile_output():
                        print(line)

                print("==================================")

        def _start_profiling(self):
            TestUtils.GasWatcher._cache = network.state.TxHistory().gas_profile.copy()
            network.state.TxHistory().gas_profile.clear()

        def _combined_mean(self, old_avg, old_count, new_avg, new_count):
            prod_count_avgs = old_count * old_avg + new_count * new_avg
            total_count = old_count + new_count
            return prod_count_avgs // total_count

        def _combine_profiles(self, old, new):
            overlap = {}
            for method in old:
                if new.get(method):
                    overlap[method] = {}

                    overlap[method]['high'] = max(old[method]['high'], new[method]['high'])
                    overlap[method]['low'] = min(old[method]['low'], new[method]['low'])

                    # avg
                    overlap[method]['avg'] = self._combined_mean(old[method]['avg'],
                                                             old[method]['count'],
                                                             new[method]['avg'],
                                                             new[method]['count'])

                    overlap[method]['avg_success'] = self._combined_mean(old[method]['avg_success'],
                                                                     old[method]['count_success'],
                                                                     new[method]['avg_success'],
                                                                     new[method]['count_success'])

                    overlap[method]['count'] = old[method]['count'] + new[method]['count']
                    overlap[method]['count_success'] = old[method]['count_success'] + new[method]['count_success']

            # include unique methods, overlap overwrites all duplicates
            return {**old,**new,**overlap}

        def _end_profiling(self):
            network.state.TxHistory().gas_profile = self._combine_profiles(TestUtils.GasWatcher._cache,
                                                                          network.state.TxHistory().gas_profile)

@pytest.fixture
def test_utils():
    return TestUtils