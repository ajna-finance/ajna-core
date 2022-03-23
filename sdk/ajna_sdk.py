from typing import List

from brownie import *
from brownie import (
    Contract,
    ERC20PoolFactory,
    ERC20Pool,
    BucketMath,
    Maths,
    PriceBuckets,
)
from brownie.network.account import Accounts, LocalAccount

from .sdk_options import *
from .token_wrapper import TokenWrapper
from .pool_wrapper import PoolWrapper


class AjnaSdk:
    def __init__(self, params: AjnaSdkOptions = None) -> None:
        options = params if params else AjnaSdkOptions.DEFAULT()

        self._accounts = Accounts()
        self.deployer = self._accounts[0]

        self.bucket_math = BucketMath.deploy({"from": self.deployer})
        self.maths = Maths.deploy({"from": self.deployer})
        self.price_buckets = PriceBuckets.deploy({"from": self.deployer})

        self.ajna_factory = ERC20PoolFactory.deploy({"from": self.deployer})

        self.pools: List[ERC20Pool] = []
        for pool_options in options.deploy_pools:
            pool = self.deploy_erc20_pool(
                pool_options.collateral_address, pool_options.quote_token_address
            )
            self.pools.append(pool)

        self._tokens = {}
        for token_options in options.tokens:
            self.add_token(token_options.token_address, token_options.reserve_address)

        self.lenders = []
        for lender_options in params.lenders:
            lender = self.add_lender()

            for token_options in lender_options.token_balances:
                token = self.get_token(token_options.token_address)
                token.top_up(lender, token_options.amount)

                if token_options.approve_max:
                    for pool in self.pools:
                        token.approve_max(pool.get_contract(), lender)

            self.lenders.append(lender)

        self.borrowers = []
        for borrower_options in params.borrowers:
            borrower = self.add_borrower()

            for token_options in borrower_options.token_balances:
                token = self.get_token(token_options.token_address)
                token.top_up(borrower, token_options.amount)

                if token_options.approve_max:
                    for pool in self.pools:
                        token.approve_max(pool.get_contract(), borrower)

            self.borrowers.append(borrower)

    def deploy_erc20_pool(self, collateral_address, quote_token_address) -> PoolWrapper:
        deploy_tx = self.ajna_factory.deployPool(
            collateral_address,
            quote_token_address,
            {"from": self.deployer},
        )
        if bool(deploy_tx.revert_msg):
            raise Exception(
                f"Failed to deploy pool collateral {collateral_address} - quote {quote_token_address}. Revert reason: {deploy_tx.revert_msg}"
            )

        pool_address = self.ajna_factory.deployedPools(
            collateral_address, quote_token_address
        )

        pool = ERC20Pool.at(pool_address)

        return PoolWrapper(self, pool)

    def add_token(self, token_address: str, reserve_address: str) -> None:
        self._tokens[token_address.lower()] = TokenWrapper(
            token_address, reserve_address
        )

    def add_borrower(self, *, borrower: LocalAccount = None) -> None:
        if borrower is None:
            borrower = self._accounts.add()

        self.borrowers.append(borrower)
        return borrower

    def add_lender(self, *, lender: LocalAccount = None) -> None:
        if lender is None:
            lender = self._accounts.add()

        self.lenders.append(lender)
        return lender

    def get_pool(
        self, collateral_address, quote_token_address, *, force_deploy=False
    ) -> PoolWrapper:
        pool_address = self.ajna_factory.deployedPools(
            collateral_address, quote_token_address
        )

        is_deployed = self.ajna_factory.isPoolDeployed(
            collateral_address, quote_token_address
        )

        if is_deployed:
            pool_contract = ERC20Pool.at(pool_address)
            return PoolWrapper(self, pool_contract)

        if force_deploy:
            return self.deploy_erc20_pool(collateral_address, quote_token_address)
        else:
            raise Exception(
                f"Pool for {pool_address} not deployed. Deploy it first for collateral {collateral_address} and quote token {quote_token_address}"
            )

    def get_borrower(self, index) -> LocalAccount:
        return self.borrowers[index]

    def get_lender(self, index) -> LocalAccount:
        return self.lenders[index]

    def top_up_erc20_token(
        self, user: LocalAccount, token_address: str, amount: int
    ) -> None:
        self.get_token(token_address).top_up(user, amount)

    def get_token(self, token_address: str) -> TokenWrapper:
        token_address = token_address.lower()

        if token_address in self._tokens:
            return self._tokens[token_address]
        else:
            raise Exception(
                f"Token {token_address} not found. Add it first with corresponding reserve address"
            )

    def get_pool_quote_token(self, pool) -> TokenWrapper:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        return self.get_token(pool.quoteToken())

    def get_pool_collateral_token(self, pool) -> TokenWrapper:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        return self.get_token(pool.collateral())

    def deposit_quote_token(
        self,
        pool,
        amount: int,
        price: int,
        lender_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        lender = self.lenders[lender_index]

        if ensure_approval:
            quote_token = self.get_pool_quote_token(pool)
            quote_token.approve(pool, amount, lender)

        tx = pool.addQuoteToken(amount, price, {"from": lender})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(
                f"Failed to deposit quote token to pool {pool.address}. Revert message: {tx.revert_msg}"
            )

    def withdraw_quote_token(
        self,
        pool,
        amount: int,
        price: int,
        lender_index: int,
        ensure_passes=True,
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        lender = self.lenders[lender_index]
        tx = pool.removeQuoteToken(amount, price, {"from": lender})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(
                f"Failed to remove quote token from pool {pool.address}. Revert message: {tx.revert_msg}"
            )

    def deposit_collateral(
        self,
        pool,
        amount: int,
        borrower_index: int,
        ensure_approval=False,
        ensure_passes=True,
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        borrower = self.borrowers[borrower_index]

        if ensure_approval:
            collateral_token = self.get_pool_collateral_token(pool)
            collateral_token.approve(pool, amount, borrower)

        tx = pool.addCollateral(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to add collateral: {tx.revert_msg}")

    def withdraw_collateral(
        self, pool, amount: int, borrower_index: int, ensure_passes=True
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        borrower = self.borrowers[borrower_index]
        tx = pool.removeCollateral(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to withdraw collateral: {tx.revert_msg}")

    def borrow(
        self,
        pool,
        amount: int,
        stop_price: int,
        borrower_index: int,
        ensure_passes=True,
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        borrower = self.borrowers[borrower_index]
        tx = pool.borrow(amount, stop_price, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to borrow: {tx.revert_msg}")

    def repay(
        self,
        pool,
        amount: int,
        borrower_index: int,
        ensure_passes=True,
    ) -> None:
        if isinstance(pool, PoolWrapper):
            pool = pool.get_contract()

        borrower = self.borrowers[borrower_index]
        tx = pool.repay(amount, {"from": borrower})
        if ensure_passes and bool(tx.revert_msg):
            raise Exception(f"Failed to repay: {tx.revert_msg}")
