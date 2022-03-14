import pytest
from scripts.sdk import init as sdkInit, AjnaSdk, DAI_ADDRESS, MKR_ADDRESS


@pytest.fixture
def sdk() -> AjnaSdk:
    return sdkInit()


@pytest.fixture
def deployer(sdk):
    return sdk.deployer


@pytest.fixture
def dai(sdk):
    return sdk.tokens[DAI_ADDRESS].contract


@pytest.fixture
def mkr(sdk):
    return sdk.tokens[MKR_ADDRESS].contract


# TODO: convert to deploying all necessary libraries "libraries(deployer)"
@pytest.fixture
def bucket_math(sdk):
    return sdk.bucket_math


@pytest.fixture
def mkr_dai_pool(sdk):
    return sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS, force_deploy=True)


@pytest.fixture
def lenders(sdk, mkr_dai_pool):
    amount = 200_000 * 10**18  # 200,000 DAI for each lender

    lenders = []
    for index in range(10):
        lender = sdk.get_lender(index)
        token = sdk.tokens[DAI_ADDRESS]

        token.top_up(lender, amount)
        token.approve_max(mkr_dai_pool, lender)

        lenders.append(lender)

    return lenders


@pytest.fixture
def borrowers(sdk, mkr_dai_pool):
    amount = 100 * 10**18  # 100 MKR for each borrower

    borrowers = []
    for index in range(10):
        borrower = sdk.get_borrower(index)
        mkr_token = sdk.tokens[MKR_ADDRESS]
        dai_token = sdk.tokens[DAI_ADDRESS]

        mkr_token.top_up(borrower, amount)
        mkr_token.approve_max(mkr_dai_pool, borrower)

        dai_token.approve_max(mkr_dai_pool, borrower)

        borrowers.append(borrower)

    return borrowers


class TestUtils:
    @staticmethod
    def get_gas_usage(gas) -> str:
        in_eth = gas * 100 * 10e-9
        in_fiat = in_eth * 3000
        return f"Gas amount: {gas}, Gas in ETH: {in_eth}, Gas price: ${in_fiat}"


@pytest.fixture
def test_utils():
    return TestUtils
