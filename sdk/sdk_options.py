from typing import List
from dataclasses import dataclass, field


DAI_ADDRESS = "0x6b175474e89094c44da98b954eedeac495271d0f"
DAI_RESERVE_ADDRESS = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"

MKR_ADDRESS = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
MKR_RESERVE_ADDRESS = "0x0a3f6849f78076aefadf113f5bed87720274ddc0"

COMP_ADDRESS = "0xc00e94Cb662C3520282E6f5717214004A7f26888"
COMP_RESERVE_ADDRESS = "0x2775b1c75658be0f640272ccb8c72ac986009e38"

USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
USDC_RESERVE_ADDRESS = "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7"

USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
USDT_RESERVE_ADDRESS = "0x5754284f345afc66a98fbb0a0afe71e0f007b949"


@dataclass
class TokenParams:
    token_address: str
    reserve_address: str


@dataclass
class DeployPoolParams:
    collateral_address: str
    quote_token_address: str


@dataclass
class BalanceParams:
    token_address: str
    amount: int
    approve_max: bool = False


@dataclass
class AccountParams:
    token_balances: List[BalanceParams] = field(default_factory=list)


@dataclass
class AjnaSdkOptions:
    lenders: List[AccountParams] = field(default_factory=list)
    borrowers: List[AccountParams] = field(default_factory=list)
    tokens: List[TokenParams] = field(default_factory=list)
    deploy_pools: List[DeployPoolParams] = field(default_factory=list)

    @staticmethod
    def DEFAULT():
        options = SdkOptionsBuilder()
        for _ in range(10):
            options.with_lender().add()
            options.with_lender().add()

        options.add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        options.add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)

        options.deploy_pool(MKR_ADDRESS, DAI_ADDRESS)

        return options.build()


class SdkOptionsBuilder:
    def __init__(self) -> None:
        self._options = AjnaSdkOptions()

    def build(self) -> AjnaSdkOptions:
        return self._options

    def with_lender(self) -> "AccountBuilder":
        return AccountBuilder(self, self._options.lenders)

    def with_lenders(self, number_of_lenders: int) -> "AccountsBuilder":
        return AccountsBuilder(self, self._options.lenders, number_of_lenders)

    def with_borrower(self) -> "AccountBuilder":
        account_builder = AccountBuilder(self, self._options.borrowers)
        return account_builder

    def with_borrowers(self, number_of_borrowers: int) -> "AccountsBuilder":
        return AccountsBuilder(self, self._options.borrowers, number_of_borrowers)

    def add_token(self, address: str, reserve_address: str) -> "SdkOptionsBuilder":
        self._options.tokens.append(TokenParams(address, reserve_address))
        return self

    def deploy_pool(
        self, collateral_address: str, quote_token_address: str
    ) -> "SdkOptionsBuilder":
        self._options.deploy_pools.append(
            DeployPoolParams(collateral_address, quote_token_address)
        )
        return self


class AccountBuilder:
    def __init__(self, builder: SdkOptionsBuilder, accounts: List):
        self._account_params = AccountParams()
        self._builder = builder
        self._accounts = accounts

    def add(self) -> SdkOptionsBuilder:
        self._accounts.append(self._account_params)
        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AccountBuilder":
        self._account_params.token_balances.append(
            BalanceParams(address, amount, approve_max)
        )
        return self


class AccountsBuilder:
    def __init__(self, builder: SdkOptionsBuilder, accounts: List, amount: int):
        self._account_params = AccountParams()
        self._builder = builder
        self._accounts = accounts
        self._amount = amount

    def add(self) -> SdkOptionsBuilder:
        for _ in range(self._amount):
            self._accounts.append(self._account_params)

        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AccountBuilder":
        self._account_params.token_balances.append(
            BalanceParams(address, amount, approve_max)
        )
        return self
