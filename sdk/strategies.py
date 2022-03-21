from cProfile import label
from brownie.test import strategy
from hypothesis import *
from hypothesis.strategies import *


from .ajna_sdk import *


def number_of_lenders_strategy(min_value, max_value):
    return integers(min_value=min_value, max_value=max_value)


def number_of_borrowers_strategy(min_value, max_value):
    return integers(
        min_value=min_value,
        max_value=max_value,
    )


def get_quote_price_strategy(data, sdk: AjnaSdk):
    price_index = data.draw(
        integers(min_value=-3232, max_value=6926), label="price_index"
    )

    return sdk.get_price_for_index(price_index)


def get_borrower_index_strategy(data, sdk: AjnaSdk):
    return data.draw(
        integers(min_value=0, max_value=len(sdk.borrowers) - 1), label="borrower_index"
    )


def get_lender_index(data, sdk: AjnaSdk):
    return data.draw(
        integers(min_value=0, max_value=len(sdk.lenders) - 1), label="lender_index"
    )


def get_collateral_deposit_amount_strategy(
    data, sdk: AjnaSdk, borrower_index: int, collateral: TokenWrapper
):
    borrower_collateral_balance = collateral.balance(sdk.borrowers[borrower_index])

    amount = data.draw(
        strategy(
            "uint256",
            min_value=borrower_collateral_balance / 2,
            max_value=borrower_collateral_balance,
        ),
        label=f"collateral_deposit_amount_for_borrower_{borrower_index}",
    )

    return amount


def get_borrow_amount_strategy(data, pool: PoolWrapper, borrower_index: int):
    return 0


def get_collateral_withdraw_amount_strategy(
    data, pool: PoolWrapper, borrower_index: int
):
    amount_available_to_withdraw = pool.get_borrower_collateral_available_to_withdraw(
        borrower_index
    )

    amount = data.draw(
        strategy("uint256", min_value=0, max_value=amount_available_to_withdraw),
        label=f"collateral_withdraw_amount_for_borrower_{borrower_index}",
    )

    return amount


def get_repayment_amount_strategy(data, pool: PoolWrapper, borrower_index: int):
    borrower_debt = pool.get_borrower_debt(borrower_index)

    amount = data.draw(
        strategy("uint256", min_value=0, max_value=borrower_debt),
        label=f"repayment_amount_for_borrower_{borrower_index}",
    )

    return amount


def get_quote_deposit_amount(
    data, sdk: AjnaSdk, lender_index: int, quote: TokenWrapper
):
    lender_quote_balance = quote.balance(sdk.lenders[lender_index])

    amount = data.draw(
        strategy(
            "uint256",
            min_value=lender_quote_balance / 2,
            max_value=lender_quote_balance,
        ),
        label=f"quote_deposit_amount_for_lender_{lender_index}",
    )

    return amount


def get_quote_withdraw_amount(
    data, sdk: AjnaSdk, lender_index: int, quote: TokenWrapper
):
    return 0
