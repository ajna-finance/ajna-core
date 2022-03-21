from brownie.test import given
from hypothesis import settings
from hypothesis.strategies import data, integers

from sdk import (
    create_sdk,
    strategies,
    MKR_ADDRESS,
    MKR_RESERVE_ADDRESS,
    DAI_ADDRESS,
    DAI_RESERVE_ADDRESS,
)


@given(
    number_of_lenders=strategies.number_of_lenders_strategy(
        min_value=10, max_value=100
    ),
    number_of_borrowers=strategies.number_of_borrowers_strategy(
        min_value=10, max_value=100
    ),
    data=data(),
)
@settings(max_examples=10)
def test_pool(data, number_of_lenders, number_of_borrowers):
    sdk = create_sdk(
        collateral_address=MKR_ADDRESS,
        collateral_amount=50 * 10**18,
        collateral_reserve=MKR_RESERVE_ADDRESS,
        quote_address=DAI_ADDRESS,
        quote_amount=100_000 * 10**18,
        quote_reserve=DAI_RESERVE_ADDRESS,
        number_of_lenders=number_of_lenders,
        number_of_borrowers=number_of_borrowers,
    )

    mkr_dai_pool = sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS)
    quote_token = mkr_dai_pool.get_quote_token()
    collateral_token = mkr_dai_pool.get_collateral_token()

    perform_lenders_deposits(data, number_of_lenders, sdk, mkr_dai_pool, quote_token)
    perform_borrowers_deposits(
        data, number_of_borrowers, sdk, mkr_dai_pool, collateral_token
    )
    perform_borrowers_borrow(data, number_of_borrowers, sdk, mkr_dai_pool)
    perform_borrowers_repayments(data, number_of_borrowers, sdk, mkr_dai_pool)


def perform_borrowers_repayments(data, number_of_borrowers, sdk, mkr_dai_pool):
    for borrower_index in range(0, number_of_borrowers):
        number_of_repayments = data.draw(
            integers(min_value=1, max_value=10),
            label=f"number_of_repayments_borrower_{borrower_index}",
        )

        for _ in range(0, number_of_repayments):
            amount = strategies.get_repayment_amount_strategy(
                data, mkr_dai_pool, borrower_index
            )
            if amount > 0:
                mkr_dai_pool.repay(amount, borrower_index)


def perform_borrowers_borrow(data, number_of_borrowers, sdk, mkr_dai_pool):
    for borrower_index in range(0, number_of_borrowers):
        borrow_amount = strategies.get_borrow_amount_strategy(
            data, mkr_dai_pool, borrower_index
        )

        mkr_dai_pool.borrow(borrow_amount, borrower_index)


def perform_borrowers_withdraws(
    data, number_of_borrowers, sdk, mkr_dai_pool, collateral_token
):
    for borrower_index in range(0, number_of_borrowers):
        amount = strategies.get_collateral_withdraw_amount_strategy(
            data, mkr_dai_pool, borrower_index
        )

        if amount > 0:
            mkr_dai_pool.withdraw_collateral(amount, borrower_index)


def perform_borrowers_deposits(
    data, number_of_borrowers, sdk, mkr_dai_pool, collateral_token
):
    for borrower_index in range(0, number_of_borrowers):
        amount = strategies.get_collateral_deposit_amount_strategy(
            data, sdk, borrower_index, collateral_token
        )

        mkr_dai_pool.deposit_collateral(amount, borrower_index)


def perform_lenders_deposits(data, number_of_lenders, sdk, mkr_dai_pool, quote_token):
    for lender_index in range(0, number_of_lenders):
        number_of_deposits = data.draw(
            integers(min_value=1, max_value=10),
            label=f"number_of_deposits_lender_{lender_index}",
        )

        for _ in range(0, number_of_deposits):
            amount = strategies.get_quote_deposit_amount(
                data, sdk, lender_index, quote_token
            )

            price = strategies.get_quote_price_strategy(data, sdk)

            mkr_dai_pool.deposit_quote_token(amount, price, lender_index)
