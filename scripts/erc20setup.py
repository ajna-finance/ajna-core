from brownie import *
from sdk import *


def main():

    protocol_definition = (
        AjnaProtocolDefinitionBuilder()
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .deploy_pool(MKR_ADDRESS, DAI_ADDRESS)
        .with_lender()
        .with_token(DAI_ADDRESS, 500_000 * 10**18)
        .add()
        .with_borrowers(10)
        .with_token(MKR_ADDRESS, 20_000 * 10**18)
        .with_token(DAI_ADDRESS, 0, approve_max=True)
        .add()
    )

    ajna_protocol = AjnaProtocol()
    ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(
        protocol_definition.build()
    )

    pool = ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS)
    lenders = pool.get_lenders()
    borrowers = pool.get_borrowers()

    pool.deposit_quote_token(10_000 * 1e18, 4000 * 1e18, 0)
    pool.deposit_quote_token(10_000 * 1e18, 2000 * 1e18, 0)
    pool.deposit_quote_token(10_000 * 1e18, 1500 * 1e18, 0)
    pool.deposit_quote_token(10_000 * 1e18, 1000 * 1e18, 0)

    pool.deposit_collateral(500 * 1e18, 0)
    pool.deposit_collateral(500 * 1e18, 1)
    pool.deposit_collateral(300 * 1e18, 2)
    pool.deposit_collateral(400 * 1e18, 3)
    pool.deposit_collateral(500 * 1e18, 4)

    pool.borrow(10_000 * 1e18, 4000 * 1e18, 0)
    pool.borrow(5_000 * 1e18, 2000 * 1e18, 1)

    return (
        ajna_protocol,
        lenders[0],
        borrowers[0],
        borrowers[1],
        pool.get_quote_token().get_contract(),
        pool.get_collateral_token().get_contract(),
        pool.get_contract(),
    )
