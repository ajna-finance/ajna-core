from brownie import *
from .ajna_sdk import *
from .sdk_options import *


def create_default_sdk():
    options = AjnaSdkOptions.DEFAULT()
    sdk = AjnaSdk(options)
    return sdk


def create_sdk(
    collateral_address: str,
    collateral_reserve: str,
    collateral_amount: int,
    quote_address: str,
    quote_reserve: str,
    quote_amount: int,
    number_of_lenders=10,
    number_of_borrowers=10,
):
    options_builder = (
        SdkOptionsBuilder()
        .add_token(collateral_address, collateral_reserve)
        .add_token(quote_address, quote_reserve)
        .deploy_pool(collateral_address, quote_address)
    )

    (
        options_builder.with_borrowers(number_of_borrowers)
        .with_token(collateral_address, collateral_amount, approve_max=True)
        .add()
    )

    (
        options_builder.with_lenders(number_of_lenders)
        .with_token(quote_address, quote_amount, approve_max=True)
        .add()
    )

    sdk = AjnaSdk(options_builder.build())
    return sdk


def create_sdk_for_mkr_dai_pool(number_of_lenders=10, number_of_borrowers=10):
    return create_sdk(
        MKR_ADDRESS,
        MKR_RESERVE_ADDRESS,
        10 * 10**18,
        DAI_ADDRESS,
        DAI_RESERVE_ADDRESS,
        10_000 * 10**18,
        number_of_lenders,
        number_of_borrowers,
    )


def create_sdk_for_dai_usdt_pool(number_of_lenders=10, number_of_borrowers=10):
    return create_sdk(
        DAI_ADDRESS,
        DAI_RESERVE_ADDRESS,
        10_000 * 10**18,
        USDT_ADDRESS,
        USDT_RESERVE_ADDRESS,
        10_000 * 10**18,
        number_of_lenders,
        number_of_borrowers,
    )


def create_sdk_for_comp_dai_pool(number_of_lenders=10, number_of_borrowers=10):
    return create_sdk(
        COMP_ADDRESS,
        COMP_RESERVE_ADDRESS,
        10_000 * 10**18,
        DAI_ADDRESS,
        DAI_RESERVE_ADDRESS,
        10_000 * 10**18,
        number_of_lenders,
        number_of_borrowers,
    )
