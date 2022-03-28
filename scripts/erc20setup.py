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
        .with_token(MKR_ADDRESS, 5_000 * 10**18)
        .with_token(DAI_ADDRESS, 0, approve_max=True)
        .add()
    )

    sdk = AjnaSdk(sdk_options.build())

    pool = sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS)
    lender = sdk.get_lender(0)
    borrower1 = sdk.get_borrower(0)
    borrower2 = sdk.get_borrower(1)

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
        sdk,
        lender,
        borrower1,
        borrower2,
        sdk.get_pool_quote_token(pool).get_contract(),
        sdk.get_pool_collateral_token(pool).get_contract(),
        pool.get_contract(),
    )
