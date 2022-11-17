from brownie import *
from brownie import (
    Contract,
)
from brownie.network.transaction import TransactionReceipt
from brownie.network.account import Accounts, LocalAccount


class ERC20TokenClient:
    def __init__(self, token_address, reserve_address):
        self.token_address = token_address
        self.reserve_address = reserve_address

        self._contract = Contract(token_address)
        self._reserve = Accounts().at(reserve_address, force=True)

    def get_contract(self) -> Contract:
        """
        Returns ERC20 token contract used by this client.
        """

        return self._contract

    def top_up(self, to: LocalAccount, amount: int) -> TransactionReceipt:
        """
        Sends `amount` tokens to `to` account from predefined reserve account.

        Args:
            to: account address to top up
            amount: amount of tokens to top up
        """

        tx = self._contract.transfer(to, amount, {"from": self._reserve})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to top up {self.token_address} to {to.address}. Revert message: {tx.revert_msg}"
            )

        return tx

    def transfer(
        self, from_: LocalAccount, to: LocalAccount, amount: int
    ) -> TransactionReceipt:
        """
        Transfers `amount` tokens from `from_` account to `to` account.

        Args:
            from_: account address to transfer from
            to: account address to transfer to
            amount: amount of tokens to transfer
        """
        tx = self._contract.transfer(to, amount, {"from": from_})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to transfer {amount} tokens from {from_.address} to {to.address}. Revert message: {tx.revert_msg}"
            )

        return tx

    def approve(
        self, spender: LocalAccount, amount: int, owner: LocalAccount
    ) -> TransactionReceipt:
        """
        Approves `spender` to spend `amount` tokens from `owner` account.

        Args:
            spender: account address to approve
            amount: amount of tokens to approve
            owner: account address to approve from
        """

        tx = self._contract.approve(spender, amount, {"from": owner})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to approve {amount} tokens to {spender.address}. Revert message: {tx.revert_msg}"
            )

        return tx

    def balance(self, user: LocalAccount) -> int:
        """
        Returns current balance of `user` account.

        Args:
            user: account address to check balance
        """
        return self._contract.balanceOf(user)

    def approve_max(
        self, spender: LocalAccount, owner: LocalAccount
    ) -> TransactionReceipt:
        """
        Approves `spender` to spend all tokens from `owner` account.

        Args:
            spender: account address to approve
            owner: account address to approve from
        """

        tx = self._contract.approve(
            spender,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": owner},
        )

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to approve max amount. Revert message: {tx.revert_msg}"
            )

        return tx


class DaiTokenClient(ERC20TokenClient):
    def top_up(self, to: LocalAccount, amount: int) -> TransactionReceipt:
        """
        Mints `amount` tokens to `to` account from DaiJoin contract.

        Args:
            to: account address to top up
            amount: amount of tokens to top up
        """

        tx = self._contract.mint(to, amount, {"from": self._reserve})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to top up {self.token_address} to {to.address}. Revert message: {tx.revert_msg}"
            )

        return tx
