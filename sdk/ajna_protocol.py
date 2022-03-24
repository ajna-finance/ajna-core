from typing import List

from brownie import *
from brownie import (
    Contract,
    ERC20PoolFactory,
    ERC20Pool,
    BucketMath,
    Maths,
    Buckets,
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
        self.price_buckets = Buckets.deploy({"from": self.deployer})

        self.ajna_factory = ERC20PoolFactory.deploy({"from": self.deployer})

        self.pools: List[ERC20Pool] = []
        self.lenders = []
        self.borrowers = []

        self.protocol_runner = AjnaProtocolRunner(self)

    def get_runner(self) -> AjnaProtocolRunner:
        """
        Returns the protocol runner used to put Protocol to desired state
        """
        return self.protocol_runner

    def deploy_erc20_pool(
        self, collateral_address, quote_token_address
    ) -> AjnaPoolClient:
        """
        Deploys ERC20 contract pool for given `collateral` and `quote` token addresses contract
        and returns AjnaPoolClient. Adds pool to list of pools stored in AjnaProtocol.

        Args:
            collateral_address: address of ERC20 token contract
            quote_token_address: address of ERC20 token contract

        Returns:
            AjnaPoolClient
        """

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
        """
        Adds ERC20 token to AjnaProtocol as an ERC20 token client.

        Args:
            token_address: ERC20 token address
            reserve_address: address of account with high balance of ERC20 token.
            Used to top up token to lenders and borrowers.
        """

        self._tokens[token_address.lower()] = ERC20TokenClient(
            token_address, reserve_address
        )

    def add_borrower(self, *, borrower: LocalAccount = None) -> None:
        """
        Adds borrower to AjnaProtocol.

        Args:
            borrower: borrower account. If None, new account is created.
        """

        if borrower is None:
            borrower = self._accounts.add()

        self.borrowers.append(borrower)
        return borrower

    def add_lender(self, *, lender: LocalAccount = None) -> None:
        """
        Adds lender to AjnaProtocol.

        Args:
            lender: lender account. If None, new account is created.
        """
        if lender is None:
            lender = self._accounts.add()

        self.lenders.append(lender)
        return lender

    def get_pool(
        self, collateral_address, quote_token_address, *, force_deploy=False
    ) -> AjnaPoolClient:
        """
        Returns AjnaPoolClient for given `collateral` and `quote` token addresses contract.

        Args:
            collateral_address: address of ERC20 token contract
            quote_token_address: address of ERC20 token contract
            force_deploy: if True, pool is deployed if it is not found.

        Returns:
            AjnaPoolClient
        """

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
        """
        Returns borrower account at given index.

        Args:
            index: index of borrower account

        Returns:
            LocalAccount
        """
        return self.borrowers[index]

    def get_lender(self, index) -> LocalAccount:
        """
        Returns lender account at given index.

        Args:
            index: index of lender account

        Returns:
            LocalAccount
        """
        return self.lenders[index]

    def get_token(self, token_address: str) -> ERC20TokenClient:
        """
        Returns ERC20 token client for given token address.
        It has to be added to AjnaProtocol first using `add_token` method.

        Args:
            token_address: ERC20 token address

        Returns:
            ERC20TokenClient
        """

        token_address = token_address.lower()

        if token_address in self._tokens:
            return self._tokens[token_address]
        else:
            raise Exception(
                f"Token {token_address} not found. Add it first with corresponding reserve address"
            )
