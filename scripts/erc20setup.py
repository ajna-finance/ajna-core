from brownie import *
from sdk import *


def main():

    protocol_definition = (
        InitialProtocolStateBuilder()
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
        .deploy_pool(MKR_ADDRESS, DAI_ADDRESS)
        .with_lender()
        .with_token(DAI_ADDRESS, 500_000 * 10**18)
        .add()
        .with_borrowers(10)
        .with_token(MKR_ADDRESS, 5_000 * 10**18)
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

    pool.deposit_quote_token(10_000 * 1e18, 10000 * 1e18, 0)
    pool.deposit_quote_token(1_000 * 1e18, 9000 * 1e18, 0)
    pool.deposit_quote_token(10_000 * 1e18, 100 * 1e18, 0)

    pool.deposit_collateral(2 * 1e18, 0)
    pool.deposit_collateral(200 * 1e18, 1)
    pool.deposit_collateral(100 * 1e18, 2)
    pool.deposit_collateral(100 * 1e18, 3)
    pool.deposit_collateral(100 * 1e18, 4)

    pool.borrow(10_000 * 1e18, 1 * 1e18, 0)
    pool.borrow(1_000 * 1e18, 1 * 1e18, 0)
    pool.borrow(1_000 * 1e18, 1 * 1e18, 1)

    return (
        ajna_protocol,
        lenders[0],
        borrowers[0],
        borrowers[1],
        pool.get_quote_token().get_contract(),
        pool.get_collateral_token().get_contract(),
        pool.get_contract(),
    )
