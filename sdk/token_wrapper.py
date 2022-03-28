from brownie import *
from brownie import (
    Contract,
)
from brownie.network.account import Accounts, LocalAccount


class TokenWrapper:
    def __init__(self, token_address, reserve_address):
        self.token_address = token_address
        self.reserve_address = reserve_address

        self._contract = Contract(token_address)
        self._reserve = Accounts().at(reserve_address, force=True)

    def get_contract(self) -> Contract:
        return self._contract

    def top_up(self, to: LocalAccount, amount: int):
        reserve_balance = self._contract.balanceOf(self._reserve)
        if reserve_balance < amount:
            raise Exception(
                f"Not enough funds to transfer {amount} tokens from reserve to {to.address}. Only {reserve_balance} tokens available in reserve."
            )

        tx = self._contract.transfer(to, amount, {"from": self._reserve})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to top up {self.token_address} to {to.address}. Revert message: {tx.revert_msg}"
            )

    def transfer(self, from_: LocalAccount, to: LocalAccount, amount: int):

        tx = self._contract.transfer(to, amount, {"from": from_})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to transfer {amount} tokens from {from_.address} to {to.address}. Revert message: {tx.revert_msg}"
            )

    def approve(self, spender: LocalAccount, amount: int, owner: LocalAccount):
        tx = self._contract.approve(spender, amount, {"from": owner})

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to approve {amount} tokens to {spender.address}. Revert message: {tx.revert_msg}"
            )

    def balance(self, user: LocalAccount) -> int:
        return self._contract.balanceOf(user)

    def approve_max(self, spender: LocalAccount, owner: LocalAccount):
        tx = self._contract.approve(
            spender,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": owner},
        )

        if bool(tx.revert_msg):
            raise Exception(
                f"Failed to approve max amount. Revert message: {tx.revert_msg}"
            )
