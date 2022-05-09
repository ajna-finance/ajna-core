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
    lender = ajna_protocol.add_lender()
    dai_client.top_up(lender, 200_000 * 1e18)
    dai_client.approve_max(pool, lender)

    mkr_client = pool_client.get_collateral_token()
    borrower = ajna_protocol.add_borrower()
    mkr_client.top_up(borrower, 5_000 * 1e18)
    mkr_client.approve_max(pool, borrower)
    dai_client.approve_max(pool, borrower)

    pool.addQuoteToken(
        lender,
        1_000 * 1e18,
        ajna_protocol.bucket_math.indexToPrice(1663),
        {"from": lender},
    )
    pool.addQuoteToken(
        lender,
        1_000 * 1e18,
        ajna_protocol.bucket_math.indexToPrice(1606),
        {"from": lender},
    )
    pool.addQuoteToken(
        lender,
        3_000 * 1e18,
        ajna_protocol.bucket_math.indexToPrice(1524),
        {"from": lender},
    )

    pool.addCollateral(100 * 1e18, {"from": borrower})
    pool.borrow(1_000 * 1e18, 1_000 * 1e18, {"from": borrower})
    chain.sleep(60)
    chain.mine()
    pool.borrow(400 * 1e18, 1_000 * 1e18, {"from": borrower})
    chain.sleep(60)
    chain.mine()
    pool.removeQuoteToken(lender, 500 * 1e18, pool.lup(), {'from': lender})
    chain.sleep(60)
    chain.mine()
    # pool.removeQuoteToken(lender, 501 * 1e18, pool.lup(), {'from': lender})

    return (
        ajna_protocol,
        lender,
        borrower,
        pool_client.get_quote_token(),
        pool_client.get_collateral_token(),
        pool,
    )
