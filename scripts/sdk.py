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

DAI_ADDRESS = "0x6b175474e89094c44da98b954eedeac495271d0f"
DAI_RESERVE_ADDRESS = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"

MKR_ADDRESS = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
MKR_RESERVE_ADDRESS = "0x2775b1c75658be0f640272ccb8c72ac986009e38"

USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
USDC_RESERVE_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"

USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
USDT_RESERVE_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"


class Token:
    def __init__(self, token_address, reserve_address):
        self.token_address = token_address
        self.reserve_address = reserve_address

        self.contract = Contract(token_address)
        self.reserve = Accounts().at(reserve_address, force=True)

    def top_up(self, to: LocalAccount, amount: int):
        self.contract.transfer(to, amount, {"from": self.reserve})

    def transfer(self, from_: LocalAccount, to: LocalAccount, amount: int):
        self.contract.transfer(to, amount, {"from": from_})

    def approve(self, spender: LocalAccount, amount: int, owner: LocalAccount):
        self.contract.approve(spender, amount, {"from": owner})

    def balance(self, user: LocalAccount) -> int:
        return self.contract.balanceOf(user)

    def approveMax(self, spender: LocalAccount, owner: LocalAccount):
        self.contract.approve(
            spender,
            0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF,
            {"from": owner},
        )


class AjnaSdk:
    def __init__(self, *, no_borrowers=10, no_leders=10) -> None:
        self._accounts = Accounts()
        self.deployer = self._accounts[0]

        self.number_of_borrowers = no_borrowers
        self.number_of_lenders = no_leders

        self.borrowers = [self._accounts.add() for _ in range(no_borrowers)]
        self.lenders = [self._accounts.add() for _ in range(no_leders)]

        self.bucket_math = BucketMath.deploy({"from": self.deployer})
        self.maths = Maths.deploy({"from": self.deployer})
        self.price_buckets = PriceBuckets.deploy({"from": self.deployer})

        self.ajna_factory = ERC20PoolFactory.deploy({"from": self.deployer})
        self.pools: List[ERC20Pool] = []

        self.tokens = {
            DAI_ADDRESS: Token(DAI_ADDRESS, DAI_RESERVE_ADDRESS),
            MKR_ADDRESS: Token(MKR_ADDRESS, MKR_RESERVE_ADDRESS),
            USDC_ADDRESS: Token(USDC_ADDRESS, USDC_RESERVE_ADDRESS),
            USDT_ADDRESS: Token(USDT_ADDRESS, USDT_RESERVE_ADDRESS),
        }

    def deploy_erc20_pool(self, collateral_address, quote_token_address) -> ERC20Pool:
        pool = self.ajna_factory.deployPool(
            collateral_address,
            quote_token_address,
            {"from": self.deployer},
        )

        self.pools.append(pool)

        return pool

    def add_token(self, token_address, reserve_address) -> None:
        self._tokens[token_address] = Token(token_address, reserve_address)

    def get_pool(
        self, collateral_address, quote_token_address, *, force_deploy=False
    ) -> ERC20Pool:
        pool_address = self.ajna_factory.calculatePoolAddress(
            collateral_address, quote_token_address
        )

        is_deployed = self.ajna_factory.isPoolDeployed(pool_address)
        if is_deployed:
            return ERC20Pool.at(pool_address)

        if force_deploy:
            return self.deploy_erc20_pool(collateral_address, quote_token_address)
        else:
            raise Exception(
                f"Pool for {pool_address} not deployed. Please deploy it first for collateral {collateral_address} and quote token {quote_token_address}"
            )

    def get_borrower(self, index) -> LocalAccount:
        return self.borrowers[index]

    def get_lender(self, index) -> LocalAccount:
        return self.lenders[index]

    def top_up_erc20_token(
        self, user: LocalAccount, token_address: str, amount: int
    ) -> None:
        self._tokens[token_address].top_up(user, amount)

    def deposit_quote_token(
        self, pool: ERC20Pool, amount: int, price: int, lender_index: int
    ) -> None:
        lender = self.lenders[lender_index]

        quote_token = self.tokens[pool.quoteToken()]
        quote_token.approve(pool, amount, {"from": lender})

        pool.depositQuoteToken(amount, price, {"from": lender})

    def remove_quote_token(
        self, pool: ERC20Pool, amount: int, price: int, lender_index: int
    ) -> None:
        lender = self.lenders[lender_index]
        pool.removeQuoteToken(amount, price, {"from": lender})

    def deposit_collateral(
        self, pool: ERC20Pool, amount: int, borrower_index: int
    ) -> None:
        borrower = self.borrowers[borrower_index]
        pool.depositCollateral(amount, {"from": borrower})

    def withdraw_collateral(
        self, pool: ERC20Pool, amount: int, borrower_index: int
    ) -> None:
        borrower = self.borrowers[borrower_index]
        pool.removeCollateral(amount, {"from": borrower})

    def borrow(self, pool: ERC20Pool, amount: int, borrower_index: int) -> None:
        borrower = self.borrowers[borrower_index]
        pool.borrow(amount, {"from": borrower})

    def repay(self, pool: ERC20Pool, amount: int, borrower_index: int) -> None:
        borrower = self.borrowers[borrower_index]
        pool.repay(amount, {"from": borrower})


def init() -> AjnaSdk:
    sdk = AjnaSdk()

    sdk.deploy_erc20_pool(MKR_ADDRESS, DAI_ADDRESS)
    sdk.deploy_erc20_pool(DAI_ADDRESS, USDC_ADDRESS)

    return sdk
