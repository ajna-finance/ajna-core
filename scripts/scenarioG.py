from brownie import *
from sdk import *


def main():
    sdk_options = (
        SdkOptionsBuilder()
        .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        .add_token(COMP_ADDRESS, COMP_RESERVE_ADDRESS)
        .deploy_pool(COMP_ADDRESS, DAI_ADDRESS)
    )

    sdk_options.with_borrowers(10).with_token(COMP_ADDRESS, 20_000 * 10**18).add()
    sdk_options.with_lenders(5).with_token(DAI_ADDRESS, 600_000 * 10**18).add()

    sdk = AjnaSdk(sdk_options.build())
    pool = sdk.get_pool(COMP_ADDRESS, DAI_ADDRESS)

    sdk.deposit_quote_token(pool, 20_000 * 1e18, 11.694 * 1e18, 0)
    sdk.deposit_quote_token(pool, 50_000 * 1e18, 12.278 * 1e18, 0)
    sdk.deposit_quote_token(pool, 100_000 * 1e18, 12.892 * 1e18, 0)
    sdk.deposit_quote_token(pool, 50_000 * 1e18, 13.537 * 1e18, 0)
    sdk.deposit_quote_token(pool, 60_000 * 1e18, 14.214 * 1e18, 0)

    sdk.deposit_quote_token(pool, 10_000 * 1e18, 11.137 * 1e18, 1)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 11.694 * 1e18, 1)
    sdk.deposit_quote_token(pool, 70_000 * 1e18, 12.278 * 1e18, 1)
    sdk.deposit_quote_token(pool, 60_000 * 1e18, 12.892 * 1e18, 1)
    sdk.deposit_quote_token(pool, 60_000 * 1e18, 13.537 * 1e18, 1)
    sdk.deposit_quote_token(pool, 50_000 * 1e18, 14.214 * 1e18, 1)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 14.924 * 1e18, 1)

    sdk.deposit_quote_token(pool, 40_000 * 1e18, 11.694 * 1e18, 2)
    sdk.deposit_quote_token(pool, 60_000 * 1e18, 12.278 * 1e18, 2)
    sdk.deposit_quote_token(pool, 90_000 * 1e18, 12.892 * 1e18, 2)
    sdk.deposit_quote_token(pool, 30_000 * 1e18, 13.537 * 1e18, 2)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 14.214 * 1e18, 2)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 14.924 * 1e18, 2)

    sdk.deposit_quote_token(pool, 10_000 * 1e18, 11.137 * 1e18, 3)
    sdk.deposit_quote_token(pool, 30_000 * 1e18, 11.694 * 1e18, 3)
    sdk.deposit_quote_token(pool, 70_000 * 1e18, 12.278 * 1e18, 3)
    sdk.deposit_quote_token(pool, 50_000 * 1e18, 12.892 * 1e18, 3)
    sdk.deposit_quote_token(pool, 40_000 * 1e18, 13.537 * 1e18, 3)
    sdk.deposit_quote_token(pool, 10_000 * 1e18, 14.214 * 1e18, 3)

    return (
        sdk,
        sdk.lenders,
        sdk.borrowers,
        sdk.get_pool_quote_token(pool).contract,
        sdk.get_pool_collateral_token(pool).contract,
        pool,
    )
