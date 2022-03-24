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

from .protocol_definition import *
from .erc20_token_client import ERC20TokenClient
from .ajna_pool_client import AjnaPoolClient
from .ajna_protocol_runner import AjnaProtocolRunner


class AjnaProtocol:
    def __init__(self) -> None:

        self._accounts = Accounts()
        self._tokens = {}
        self.deployer = self._accounts[0]

        self.bucket_math = BucketMath.deploy({"from": self.deployer})
        self.maths = Maths.deploy({"from": self.deployer})
        self.price_buckets = PriceBuckets.deploy({"from": self.deployer})

        self.ajna_factory = ERC20PoolFactory.deploy({"from": self.deployer})

        self.pools: List[ERC20Pool] = []
        self.lenders = []
        self.borrowers = []

        self.protocol_runner = AjnaProtocolRunner(self)

    def get_runner(self) -> AjnaProtocolRunner:
        return self.protocol_runner

    def deploy_erc20_pool(
        self, collateral_address, quote_token_address
    ) -> AjnaPoolClient:
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

        pool_contract = ERC20Pool.at(pool_address)

        pool = AjnaPoolClient(self, pool_contract)
        self.pools.append(pool)

        return pool

    def add_token(self, token_address: str, reserve_address: str) -> None:
        self._tokens[token_address.lower()] = ERC20TokenClient(
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
    ) -> AjnaPoolClient:
        pool_address = self.ajna_factory.deployedPools(
            collateral_address, quote_token_address
        )

        is_deployed = self.ajna_factory.isPoolDeployed(
            collateral_address, quote_token_address
        )

        if is_deployed:
            pool_contract = ERC20Pool.at(pool_address)
            return AjnaPoolClient(self, pool_contract)

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

    def get_token(self, token_address: str) -> ERC20TokenClient:
        token_address = token_address.lower()

        if token_address in self._tokens:
            return self._tokens[token_address]
        else:
            raise Exception(
                f"Token {token_address} not found. Add it first with corresponding reserve address"
            )
