from .ajna_sdk import *


class PoolWrapper:
    def __init__(self, sdk, pool: ERC20Pool):
        self._sdk = sdk
        self.pool_contract = pool

    def get_contract(self):
        return self.pool_contract

    def get_quote_token(self) -> TokenWrapper:
        return self._sdk.get_pool_quote_token(self.pool_contract)

    def get_collateral_token(self) -> TokenWrapper:
        return self._sdk.get_pool_collateral_token(self.pool_contract)

    def deposit_quote_token(
        self,
        amount: int,
        price: int,
        lender_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        self._sdk.deposit_quote_token(
            self.pool_contract,
            amount,
            price,
            lender_index,
            ensure_approval,
            ensure_passes,
        )

    def withdraw_quote_token(
        self, amount: int, price: int, lender_index: int, ensure_passes=True
    ) -> None:
        self._sdk.withdraw_quote_token(
            self.pool_contract, amount, price, lender_index, ensure_passes
        )

    def deposit_collateral(
        self,
        amount: int,
        borrower_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        self._sdk.deposit_collateral(
            self.pool_contract, amount, borrower_index, ensure_approval, ensure_passes
        )

    def withdraw_collateral(
        self, amount: int, borrower_index: int, ensure_passes=True
    ) -> None:
        self._sdk.withdraw_collateral(
            self.pool_contract, amount, borrower_index, ensure_passes
        )

    def borrow(
        self,
        amount: int,
        borrower_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        self._sdk.borrow(
            self.pool_contract, amount, borrower_index, ensure_approval, ensure_passes
        )

    def repay(
        self,
        amount: int,
        borrower_index: int,
        ensure_passes=True,
    ) -> None:
        self._sdk.repay(self.pool_contract, amount, borrower_index, ensure_passes)
