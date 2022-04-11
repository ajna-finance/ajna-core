from brownie import *
from sdk import *


def main():

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

    pool_client = ajna_protocol.get_pool(MKR_ADDRESS, DAI_ADDRESS)
    pool = pool_client.get_contract()

    dai_client = pool_client.get_quote_token()
    lenders = []
    for _ in range(10):
        lender = ajna_protocol.add_lender()
        dai_client.top_up(lender, 200_000 * 1e18)
        dai_client.approve_max(pool, lender)
        lenders.append(lender)

    mkr_client = pool_client.get_collateral_token()
    borrowers = []
    for _ in range(10):
        borrower = ajna_protocol.add_borrower()
        mkr_client.top_up(borrower, 5_000 * 1e18)
        mkr_client.approve_max(pool, borrower)
        dai_client.approve_max(pool, borrower)
        borrowers.append(borrower)

    pool.addQuoteToken(
        lenders[0],
        10_000 * 1e45,
        ajna_protocol.bucket_math.indexToPrice(1600),
        {"from": lenders[0]},
    )
    pool.addQuoteToken(
        lenders[0],
        1_000 * 1e45,
        ajna_protocol.bucket_math.indexToPrice(1500),
        {"from": lenders[0]},
    )
    pool.addQuoteToken(
        lenders[0],
        10_000 * 1e45,
        ajna_protocol.bucket_math.indexToPrice(1400),
        {"from": lenders[0]},
    )

    pool.addCollateral(100 * 1e27, {"from": borrowers[0]})
    pool.addCollateral(100 * 1e27, {"from": borrowers[1]})

    pool.borrow(10_000 * 1e45, 1 * 1e18, {"from": borrowers[0]})
    pool.borrow(10_000 * 1e45, 1 * 1e18, {"from": borrowers[1]})

    return (
        ajna_protocol,
        lenders,
        borrowers,
        pool_client.get_quote_token(),
        pool_client.get_collateral_token(),
        pool,
    )
