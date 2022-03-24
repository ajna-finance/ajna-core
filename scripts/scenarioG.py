from brownie import *
from sdk import *


def main():
    protocol_definition = (
        AjnaProtocolDefinitionBuilder()
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .add_token(COMP_ADDRESS, COMP_RESERVE_ADDRESS)
        .deploy_pool(COMP_ADDRESS, DAI_ADDRESS)
    )

    protocol_definition.with_borrowers(10).with_token(
        COMP_ADDRESS, 20_000 * 10**18
    ).add()
    protocol_definition.with_lenders(5).with_token(
        DAI_ADDRESS, 600_000 * 10**18
    ).add()

    ajna_protocol = AjnaProtocol()
    ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(
        protocol_definition.build()
    )

    pool = ajna_protocol.get_pool(COMP_ADDRESS, DAI_ADDRESS)

    pool.deposit_quote_token(20_000 * 1e18, 11.694 * 1e18, 0)
    pool.deposit_quote_token(50_000 * 1e18, 12.278 * 1e18, 0)
    pool.deposit_quote_token(100_000 * 1e18, 12.892 * 1e18, 0)
    pool.deposit_quote_token(50_000 * 1e18, 13.537 * 1e18, 0)
    pool.deposit_quote_token(60_000 * 1e18, 14.214 * 1e18, 0)

    pool.deposit_quote_token(10_000 * 1e18, 11.137 * 1e18, 1)
    pool.deposit_quote_token(10_000 * 1e18, 11.694 * 1e18, 1)
    pool.deposit_quote_token(70_000 * 1e18, 12.278 * 1e18, 1)
    pool.deposit_quote_token(60_000 * 1e18, 12.892 * 1e18, 1)
    pool.deposit_quote_token(60_000 * 1e18, 13.537 * 1e18, 1)
    pool.deposit_quote_token(50_000 * 1e18, 14.214 * 1e18, 1)
    pool.deposit_quote_token(10_000 * 1e18, 14.924 * 1e18, 1)

    pool.deposit_quote_token(40_000 * 1e18, 11.694 * 1e18, 2)
    pool.deposit_quote_token(60_000 * 1e18, 12.278 * 1e18, 2)
    pool.deposit_quote_token(90_000 * 1e18, 12.892 * 1e18, 2)
    pool.deposit_quote_token(30_000 * 1e18, 13.537 * 1e18, 2)
    pool.deposit_quote_token(10_000 * 1e18, 14.214 * 1e18, 2)
    pool.deposit_quote_token(10_000 * 1e18, 14.924 * 1e18, 2)

    pool.deposit_quote_token(10_000 * 1e18, 11.137 * 1e18, 3)
    pool.deposit_quote_token(30_000 * 1e18, 11.694 * 1e18, 3)
    pool.deposit_quote_token(70_000 * 1e18, 12.278 * 1e18, 3)
    pool.deposit_quote_token(50_000 * 1e18, 12.892 * 1e18, 3)
    pool.deposit_quote_token(40_000 * 1e18, 13.537 * 1e18, 3)
    pool.deposit_quote_token(10_000 * 1e18, 14.214 * 1e18, 3)

    return (
        ajna_protocol,
        ajna_protocol.lenders,
        ajna_protocol.borrowers,
        pool.get_quote_token().get_contract(),
        pool.get_collateral_token().get_contract(),
        pool.get_contract(),
    )
