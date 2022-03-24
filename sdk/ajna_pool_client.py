from .ajna_protocol import *


class AjnaPoolClient:
    def __init__(self, sdk, pool: ERC20Pool):
        self._sdk = sdk
        self.pool_contract = pool

    def get_contract(self):
        """
        Returns the wrapped ERC20 pool contract

        :return: ERC20Pool
        """

        return self.pool_contract

    def get_collateral_token(self) -> ERC20TokenClient:
        """
        Returns the wrapped ERC20 token contract for the collateral token used by the pool

        :return: ERC20TokenClient
        """

        pool_contract = self.get_contract()
        return self._sdk.get_token(pool_contract.collateral())

    def get_quote_token(self) -> ERC20TokenClient:
        """
        Returns the wrapped ERC20 token contract for the quote token used by the pool

        :return: ERC20TokenClient
        """

        pool_contract = self.get_contract()
        return self._sdk.get_token(pool_contract.quoteToken())

    def deposit_quote_token(
        self,
        amount: int,
        price: int,
        lender_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        """
        Deposits quote token into the pool for the specified amount and price by the specified lender

        Args:
            amount: Amount of quote token to deposit
            price: Price of quote token to deposit
            lender_index: Index of the lender to deposit the quote token for
            ensure_approval: If True, the lender will be approved for the specified amount of quote token
            ensure_passes: If True, an exception will be raised if the transaction fails
        """

        pool_contract = self.get_contract()

        lender = self._sdk.lenders[lender_index]

        if ensure_approval:
            quote_token = self.get_quote_token(pool_contract)
            quote_token.approve(pool_contract, amount, lender)

        tx = pool_contract.addQuoteToken(amount, price, {"from": lender})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(
                f"Failed to deposit quote token to pool {pool_contract.address}. Revert message: {tx.revert_msg}"
            )

    def withdraw_quote_token(
        self,
        amount: int,
        price: int,
        lender_index: int,
        ensure_passes=True,
    ) -> None:
        """
        Withdraws quote token from the pool for the specified amount and price by the specified lender

        Args:
            amount: Amount of quote token to withdraw
            price: Price of quote token to withdraw
            lender_index: Index of the lender to withdraw the quote token for
            ensure_passes: If True, an exception will be raised if the transaction fails
        """

        pool_contract = self.get_contract()

        lender = self._sdk.lenders[lender_index]

        tx = pool_contract.removeQuoteToken(amount, price, {"from": lender})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(
                f"Failed to remove quote token from pool {pool_contract.address}. Revert message: {tx.revert_msg}"
            )

    def deposit_collateral(
        self,
        amount: int,
        borrower_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        """
        Deposits collateral into the pool for the specified amount by the specified borrower

        Args:
            amount: Amount of collateral to deposit
            borrower_index: Index of the borrower to deposit the collateral for
            ensure_approval: If True, the borrower will be approved for the specified amount of collateral
            ensure_passes: If True, an exception will be raised if the transaction fails
        """
        pool_contract = self.get_contract()

        borrower = self._sdk.borrowers[borrower_index]

        if ensure_approval:
            collateral_token = self.get_collateral_token(pool_contract)
            collateral_token.approve(pool_contract, amount, borrower)

        tx = pool_contract.addCollateral(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to add collateral: {tx.revert_msg}")

    def withdraw_collateral(
        self, amount: int, borrower_index: int, ensure_passes=True
    ) -> None:
        """
        Withdraws collateral from the pool for the specified amount by the specified borrower

        Args:
            amount: Amount of collateral to withdraw
            borrower_index: Index of the borrower to withdraw the collateral for
            ensure_passes: If True, an exception will be raised if the transaction fails
        """

        pool_contract = self.get_contract()

        borrower = self._sdk.borrowers[borrower_index]
        tx = pool_contract.removeCollateral(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to withdraw collateral: {tx.revert_msg}")

    def borrow(
        self,
        amount: int,
        borrower_index: int,
        stop_price: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        """
        Borrows the specified amount of quote token by the specified borrower

        Args:
            amount: Amount of quote token to borrow
            borrower_index: Index of the borrower to borrow the quote token for
            stop_price: Stop price of the borrow
            ensure_approval: If True, the borrower will be approved for the specified amount of quote token
            ensure_passes: If True, an exception will be raised if the transaction fails
        """

        pool_contract = self.get_contract()

        borrower = self._sdk.borrowers[borrower_index]

        if ensure_approval:
            quote_token = self.get_collateral_token(pool_contract)
            quote_token.approve(pool_contract, amount, borrower)

        tx = pool_contract.borrow(amount, stop_price, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to borrow: {tx.revert_msg}")

    def repay(
        self,
        amount: int,
        borrower_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        """
        Repays the specified amount of quote token by the specified borrower

        Args:
            amount: Amount of quote token to repay
            borrower_index: Index of the borrower to repay the quote token for
            ensure_approval: If True, the borrower will be approved for the specified amount of quote token
            ensure_passes: If True, an exception will be raised if the transaction fails
        """

        pool_contract = self.get_contract()

        borrower = self._sdk.borrowers[borrower_index]

        if ensure_approval:
            quote_token = self.get_collateral_token(pool_contract)
            quote_token.approve(pool_contract, amount, borrower)

        tx = pool_contract.repay(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to repay: {tx.revert_msg}")
