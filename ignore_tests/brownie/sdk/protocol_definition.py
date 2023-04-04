from typing import List
from dataclasses import dataclass, field

AJNA_ADDRESS = "0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079"

DAI_ADDRESS = "0x6b175474e89094c44da98b954eedeac495271d0f"
DAI_RESERVE_ADDRESS = "0x9759A6Ac90977b93B58547b4A71c78317f391A28"

MKR_ADDRESS = "0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2"
MKR_RESERVE_ADDRESS = "0x0a3f6849f78076aefadf113f5bed87720274ddc0"

COMP_ADDRESS = "0xc00e94Cb662C3520282E6f5717214004A7f26888"
COMP_RESERVE_ADDRESS = "0x2775b1c75658be0f640272ccb8c72ac986009e38"

USDC_ADDRESS = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
USDC_RESERVE_ADDRESS = "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7"

USDT_ADDRESS = "0xdAC17F958D2ee523a2206206994597C13D831ec7"
USDT_RESERVE_ADDRESS = "0x5754284f345afc66a98fbb0a0afe71e0f007b949"

WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
WETH_RESERVE_ADDRESS = "0x2f0b23f53734252bda2277357e97e1517d6b042a"


@dataclass
class TokenWithReserve:
    """
    Token used in AjnaProtocol. Definition is used to create ERC20TokenClient.

    Attributes:
        token_address: address of ERC20 token contract
        reserve_address: address of account with huge amount of token balance used to top up token balance for Ajna users
    """

    token_address: str
    reserve_address: str


@dataclass
class PoolsToDeploy:
    """
    Definition of Ajna pool to be deployed.

    Attributes:
        collateral_address: address of ERC20 token contract
        quote_token_address: address of ERC20 token contract
    """

    collateral_address: str
    quote_token_address: str


@dataclass
class InitialUserTokenBalance:
    """
    Definition of initial token balance for Ajna user.

    Attributes:
        token_address: address of ERC20 token contract
        amount: amount of token to be added to Ajna user
        approve_max: if True, Ajna user can pre-approve maximum amount of tokens to any Ajna Pool contract
    """

    token_address: str
    amount: int
    approve_max: bool = False


@dataclass
class QuoteTokenDeposits:
    """
    Definition of quote token deposits for Ajna user.

    Attributes:
        token_address: address of ERC20 token contract
        amount: amount of token to be added to Ajna user
    """

    min_deposit_amount: int
    max_deposit_amount: int
    min_deposit_price_index: int
    max_deposit_price_index: int


@dataclass
class CollateralTokenDeposits:
    """
    Definition of collateral token deposits for Ajna user.

    Attributes:
        token_address: address of ERC20 token contract
        amount: amount of token to be added to Ajna user
    """

    min_deposit_amount: int
    max_deposit_amount: int


@dataclass
class PoolInteractions:
    """ """

    quote_token_address: str
    collateral_address: str

    quote_deposits: List[QuoteTokenDeposits] = field(default_factory=list)
    collateral_deposits: List[CollateralTokenDeposits] = field(default_factory=list)


@dataclass
class AjnaUser:
    """
    Definition of Ajna user.

    Attributes:
        token_balances: list of definitions of initial token balances for Ajna user
    """

    token_balances: List[InitialUserTokenBalance] = field(default_factory=list)

    pool_interactions: List[PoolInteractions] = field(default_factory=list)


@dataclass
class InitialProtocolState:
    """
    Protocol definition for AjnaProtocol.

    It can be used by AjnaProtocolRunner to prepare AjnaProtocol to desired state.

    Attributes:
        - tokens: list of TokenUsedInAjnaProtocolDefinition, list of tokens used in AjnaProtocol
        - deploy_pools: list of AjnaDeployedPoolsDefinition, which defines pools to deploy
        - lenders: list of AjnaUserDefinition, which defines how many tokens each user initially has
        - borrowers: list of AjnaUserDefinition, which defines how many tokens each user initially has
    """

    lenders: List[AjnaUser] = field(default_factory=list)
    borrowers: List[AjnaUser] = field(default_factory=list)
    tokens: List[TokenWithReserve] = field(default_factory=list)
    deploy_pools: List[PoolsToDeploy] = field(default_factory=list)

    @staticmethod
    def DEFAULT():
        """
        Returns default AjnaProtocolStateDefinition.

        Default is:
            - a single Lender with 100 ETH and 0 tokens
            - a single Borrower with 100 ETH and 0 tokens
            - a MKR token wrapper
            - a DAI token wrapper
            - a single Pool for MKR and DAI pair
        """
        options = InitialProtocolStateBuilder()
        for _ in range(10):
            options.with_lender().add()
            options.with_borrower().add()

        options.add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        options.add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)

        options.deploy_pool(MKR_ADDRESS, DAI_ADDRESS)

        return options.build()


class InitialProtocolStateBuilder:
    def __init__(self) -> None:
        self._options = InitialProtocolState()

    def build(self) -> InitialProtocolState:
        return self._options

    def with_lender(self) -> "AjnaUserBuilder":
        """
        Starts definition builder for Ajna Lender.
        """
        return AjnaUserBuilder(self, self._options.lenders)

    def with_lenders(self, number_of_lenders: int) -> "MultipleAjnaUsersBuilder":
        """
        Starts definition builder for multiple Ajna Lenders with same definition.

        Args:
            number_of_lenders: number of lenders to be added
        """

        return MultipleAjnaUsersBuilder(self, self._options.lenders, number_of_lenders)

    def with_borrower(self) -> "AjnaUserBuilder":
        """
        Starts definition builder for Ajna Borrower.
        """

        account_builder = AjnaUserBuilder(self, self._options.borrowers)
        return account_builder

    def with_borrowers(self, number_of_borrowers: int) -> "MultipleAjnaUsersBuilder":
        """
        Starts definition builder for multiple Ajna Borrowers with same definition.

        Args:
            number_of_borrowers: number of Borrowers to be added
        """

        return MultipleAjnaUsersBuilder(
            self, self._options.borrowers, number_of_borrowers
        )

    def add_token(
        self, address: str, reserve_address: str
    ) -> "InitialProtocolStateBuilder":
        """
        Adds token definition to be used in AjnaProtocol.

        Args:
            address: address of ERC20 token contract
            reserve_address: address of account with huge amount of token balance used to top up token balance for Ajna users
        """

        self._options.tokens.append(TokenWithReserve(address, reserve_address))
        return self

    def deploy_pool(
        self, collateral_address: str, quote_token_address: str
    ) -> "InitialProtocolStateBuilder":
        self._options.deploy_pools.append(
            PoolsToDeploy(collateral_address, quote_token_address)
        )
        return self


class AjnaUserBuilder:
    def __init__(self, builder: InitialProtocolStateBuilder, accounts: List):
        self._account_params = AjnaUser()
        self._builder = builder
        self._accounts = accounts

    def add(self) -> InitialProtocolStateBuilder:
        """
        Finalizes AjnaUserDefinition and adds it to AjnaProtocolStateDefinition.
        """

        self._accounts.append(self._account_params)
        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AjnaUserBuilder":
        """
        Adds token balance definition to AjnaUserDefinition.

        Args:
            address: address of ERC20 token contract
            amount: amount of token to be added to Ajna user
            approve_max: if True, Ajna user can pre-approve maximum amount of tokens to any Ajna Pool contract
        """

        self._account_params.token_balances.append(
            InitialUserTokenBalance(address, amount, approve_max)
        )
        return self

    def interacts_with_pool(
        self, pool_interactions_definition: PoolInteractions
    ) -> "AjnaUserBuilder":
        self._account_params.pool_interactions.append(pool_interactions_definition)
        return self


class MultipleAjnaUsersBuilder:
    def __init__(
        self, builder: InitialProtocolStateBuilder, accounts: List, amount: int
    ):
        self._account_params = AjnaUser()
        self._builder = builder
        self._accounts = accounts
        self._amount = amount

    def add(self) -> InitialProtocolStateBuilder:
        """
        Finalizes AjnaUserDefinition and adds multiple copies of it to AjnaProtocolStateDefinition.
        """

        for _ in range(self._amount):
            self._accounts.append(self._account_params)

        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AjnaUserBuilder":
        """
        Adds token balance definition to AjnaUserDefinition.

        Args:
            address: address of ERC20 token contract
            amount: amount of token to be added to Ajna user
            approve_max: if True, Ajna user can pre-approve maximum amount of tokens to any Ajna Pool contract
        """
        self._account_params.token_balances.append(
            InitialUserTokenBalance(address, amount, approve_max)
        )
        return self

    def interacts_with_pool(
        self, pool_interactions_definition: PoolInteractions
    ) -> "AjnaUserBuilder":
        self._account_params.pool_interactions.append(pool_interactions_definition)
        return self
