from brownie import *
from .ajna_protocol import *
from .protocol_definition import *


def create_empty_sdk():
    return AjnaProtocol()


def create_default_sdk():
    protocol_definition = AjnaProtocolDefinition.DEFAULT()

    sdk = AjnaProtocol()
    sdk.prepare_protocol_to_state_by_definition(protocol_definition.build())
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
    protocol_definition = (
        AjnaProtocolDefinitionBuilder()
        .add_token(collateral_address, collateral_reserve)
        .add_token(quote_address, quote_reserve)
        .deploy_pool(collateral_address, quote_address)
    )

    (
        protocol_definition.with_borrowers(number_of_borrowers)
        .with_token(collateral_address, collateral_amount, approve_max=True)
        .add()
    )

    (
        protocol_definition.with_lenders(number_of_lenders)
        .with_token(quote_address, quote_amount, approve_max=True)
        .add()
    )

    sdk = AjnaProtocol()
    sdk.prepare_protocol_to_state_by_definition(protocol_definition.build())

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
