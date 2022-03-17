from brownie import *
from sdk import (
    TokenWrapper,
    MKR_ADDRESS,
    MKR_RESERVE_ADDRESS,
    DAI_ADDRESS,
    DAI_RESERVE_ADDRESS,
)


def provide_borrower_tokens(borrower):
    accounts[0].transfer(borrower, 100 * 1e18)

    mkr = TokenWrapper(
        MKR_ADDRESS,
        MKR_RESERVE_ADDRESS,
    )
    mkr.top_up(borrower, 500 * 1e18)


def provide_lender_tokens(lender):
    # fund 100000 DAI
    dai = TokenWrapper(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
    dai.top_up(lender, 100_000 * 1e18)

    # fund 100 ETH
    accounts[0].transfer(lender, 100 * 1e18)
