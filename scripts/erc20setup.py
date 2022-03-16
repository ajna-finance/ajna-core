from brownie import *
from sdk import *


def main():

    sdk_options = (
        SdkOptionsBuilder()
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

    sdk = AjnaSdk(sdk_options.build())

    pool = sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS)
    lenders = pool.get_lenders()
    borrowers = pool.get_borrowers()

    sdk.deposit_quote_token(pool, 10_000 * 1e18, 4000 * 1e18, 0)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 2000 * 1e18, 0)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 1500 * 1e18, 0)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 1000 * 1e18, 0)

    sdk.deposit_collateral(pool, 500 * 1e18, 0)
    sdk.deposit_collateral(pool, 500 * 1e18, 1)
    sdk.deposit_collateral(pool, 300 * 1e18, 2)
    sdk.deposit_collateral(pool, 400 * 1e18, 3)
    sdk.deposit_collateral(pool, 500 * 1e18, 4)

    sdk.borrow(pool, 10_000 * 1e18, 4000 * 1e18, 0)
    sdk.borrow(pool, 5_000 * 1e18, 2000 * 1e18, 1)

    return (
        sdk,
        lenders[0],
        borrowers[0],
        borrowers[1],
        sdk.get_pool_quote_token(pool).contract,
        sdk.get_pool_collateral_token(pool).contract,
        pool,
    )
