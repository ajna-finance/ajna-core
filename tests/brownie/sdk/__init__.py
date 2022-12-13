from brownie import *
from .ajna_protocol import *
from .protocol_definition import *


def create_empty_sdk():
    """
    Creates empty AjnaProtocol with 0 lenders and 0 borrowers.
    No pool is deployed. No tokens are connected.
    """
    return AjnaProtocol(AJNA_ADDRESS)


def create_default_sdk():
    """
    Creates default AjnaProtocol with 1 lender and 1 borrower.
    Deploys MKR/DAI pool.
    Creates clients for MKR and DAI tokens.
    """
    protocol_definition = InitialProtocolState.DEFAULT()

    sdk = AjnaProtocol(AJNA_ADDRESS)
    sdk.get_runner().prepare_protocol_to_state_by_definition(
        protocol_definition.build()
    )
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
    """
    Creates AjnaProtocol with specified number of lenders and borrowers,
    with specified initial amount collateral and quote tokens
    Deploys pool with specified collateral and quote tokens.
    Creates clients for collateral and quote tokens.

    Args:
        collateral_address: address of collateral token
        collateral_reserve: address of collateral reserve token used to set initial borrowers' balances
        collateral_amount: amount of collateral tokens to be send to each borrower
        quote_address: address of quote token
        quote_reserve: address of quote reserve token used to set initial lenders balance
        quote_amount: amount of quote tokens to be send to each lender
        number_of_lenders: number of lenders to be added. Default is 10.
        number_of_borrowers: number of borrowers to be added. Default is 10.

    """
    protocol_definition = (
        InitialProtocolStateBuilder()
        .add_token(collateral_address, collateral_reserve)
        .add_token(quote_address, quote_reserve)
        .deploy_pool(collateral_address, quote_address)
    )

    (
        protocol_definition.with_borrowers(number_of_borrowers)
        .with_token(collateral_address, collateral_amount, approve_max=True)
        .with_token(quote_address, 0, approve_max=True)
        .add()
    )

    (
        protocol_definition.with_lenders(number_of_lenders)
        .with_token(quote_address, quote_amount, approve_max=True)
        .add()
    )

    sdk = AjnaProtocol()
    sdk.get_runner().prepare_protocol_to_state_by_definition(
        protocol_definition.build()
    )

    return sdk


def create_sdk_for_mkr_dai_pool(number_of_lenders=10, number_of_borrowers=10):
    """
    Creates AjnaProtocol and deploys pool with MKR/DAI tokens.

    Each lender starts with 10,000 DAI and each borrower starts with 10 MKR.
    """

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
    """
    Creates AjnaProtocol and deploys pool with DAI/USDT tokens.

    Each lender starts with 10,000 USDT and each borrower starts with 10,000 DAI.
    """
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
    """
    Creates AjnaProtocol and deploys pool with COMP/DAI tokens.

    Each lender starts with 10,000 DAI and each borrower starts with 10,000 COMP.
    """

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
