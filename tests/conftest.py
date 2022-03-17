import pytest
from sdk import *


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
    @staticmethod
    def get_gas_usage(gas) -> str:
        in_eth = gas * 100 * 10e-9
        in_fiat = in_eth * 3000
        return f"Gas amount: {gas}, Gas in ETH: {in_eth}, Gas price: ${in_fiat}"


@pytest.fixture
def test_utils():
    return TestUtils
