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
class TokenUsedInAjnaProtocolDefinition:
    """
    Token used in AjnaProtocol. Definition is used to create ERC20TokenClient.

    Attributes:
        token_address: address of ERC20 token contract
        reserve_address: address of account with huge amount of token balance used to top up token balance for Ajna users
    """

    token_address: str
    reserve_address: str


@dataclass
class AjnaDeployedPoolsDefinition:
    """
    Definition of Ajna pool to be deployed.

    Attributes:
        collateral_address: address of ERC20 token contract
        quote_token_address: address of ERC20 token contract
    """

    collateral_address: str
    quote_token_address: str


@dataclass
class InitialUserTokenBalanceDefinition:
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
class AjnaUserDefinition:
    """
    Definition of Ajna user.

    Attributes:
        token_balances: list of definitions of initial token balances for Ajna user
    """

    token_balances: List[InitialUserTokenBalanceDefinition] = field(
        default_factory=list
    )


@dataclass
class AjnaProtocolStateDefinition:
    """
    Protocol definition for AjnaProtocol.

    It can be used by AjnaProtocolRunner to prepare AjnaProtocol to desired state.

    Attributes:
        - tokens: list of TokenUsedInAjnaProtocolDefinition, list of tokens used in AjnaProtocol
        - deploy_pools: list of AjnaDeployedPoolsDefinition, which defines pools to deploy
        - lenders: list of AjnaUserDefinition, which defines how many tokens each user initially has
        - borrowers: list of AjnaUserDefinition, which defines how many tokens each user initially has
    """

    lenders: List[AjnaUserDefinition] = field(default_factory=list)
    borrowers: List[AjnaUserDefinition] = field(default_factory=list)
    tokens: List[TokenUsedInAjnaProtocolDefinition] = field(default_factory=list)
    deploy_pools: List[AjnaDeployedPoolsDefinition] = field(default_factory=list)

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
        options = AjnaProtocolStateDefinitionBuilder()
        for _ in range(10):
            options.with_lender().add()
            options.with_borrower().add()

        options.add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
        options.add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)

        options.deploy_pool(MKR_ADDRESS, DAI_ADDRESS)

        return options.build()


class AjnaProtocolStateDefinitionBuilder:
    def __init__(self) -> None:
        self._options = AjnaProtocolStateDefinition()

    def build(self) -> AjnaProtocolStateDefinition:
        return self._options

    def with_lender(self) -> "AjnaUserStateDefinitionBuilder":
        """
        Starts definition builder for Ajna Lender.
        """
        return AjnaUserStateDefinitionBuilder(self, self._options.lenders)

    def with_lenders(
        self, number_of_lenders: int
    ) -> "AjnaMultipleUsersStateDefinitionBuilder":
        """
        Starts definition builder for multiple Ajna Lenders with same definition.

        Args:
            number_of_lenders: number of lenders to be added
        """

        return AjnaMultipleUsersStateDefinitionBuilder(
            self, self._options.lenders, number_of_lenders
        )

    def with_borrower(self) -> "AjnaUserStateDefinitionBuilder":
        """
        Starts definition builder for Ajna Borrower.
        """

        account_builder = AjnaUserStateDefinitionBuilder(self, self._options.borrowers)
        return account_builder

    def with_borrowers(
        self, number_of_borrowers: int
    ) -> "AjnaMultipleUsersStateDefinitionBuilder":
        """
        Starts definition builder for multiple Ajna Borrowers with same definition.

        Args:
            number_of_borrowers: number of Borrowers to be added
        """

        return AjnaMultipleUsersStateDefinitionBuilder(
            self, self._options.borrowers, number_of_borrowers
        )

    def add_token(
        self, address: str, reserve_address: str
    ) -> "AjnaProtocolStateDefinitionBuilder":
        """
        Adds token definition to be used in AjnaProtocol.

        Args:
            address: address of ERC20 token contract
            reserve_address: address of account with huge amount of token balance used to top up token balance for Ajna users
        """

        self._options.tokens.append(
            TokenUsedInAjnaProtocolDefinition(address, reserve_address)
        )
        return self

    def deploy_pool(
        self, collateral_address: str, quote_token_address: str
    ) -> "AjnaProtocolStateDefinitionBuilder":
        self._options.deploy_pools.append(
            AjnaDeployedPoolsDefinition(collateral_address, quote_token_address)
        )
        return self


class AjnaUserStateDefinitionBuilder:
    def __init__(self, builder: AjnaProtocolStateDefinitionBuilder, accounts: List):
        self._account_params = AjnaUserDefinition()
        self._builder = builder
        self._accounts = accounts

    def add(self) -> AjnaProtocolStateDefinitionBuilder:
        """
        Finalizes AjnaUserDefinition and adds it to AjnaProtocolStateDefinition.
        """

        self._accounts.append(self._account_params)
        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AjnaUserStateDefinitionBuilder":
        """
        Adds token balance definition to AjnaUserDefinition.

        Args:
            address: address of ERC20 token contract
            amount: amount of token to be added to Ajna user
            approve_max: if True, Ajna user can pre-approve maximum amount of tokens to any Ajna Pool contract
        """

        self._account_params.token_balances.append(
            InitialUserTokenBalanceDefinition(address, amount, approve_max)
        )
        return self


class AjnaMultipleUsersStateDefinitionBuilder:
    def __init__(
        self, builder: AjnaProtocolStateDefinitionBuilder, accounts: List, amount: int
    ):
        self._account_params = AjnaUserDefinition()
        self._builder = builder
        self._accounts = accounts
        self._amount = amount

    def add(self) -> AjnaProtocolStateDefinitionBuilder:
        """
        Finalizes AjnaUserDefinition and adds multiple copies of it to AjnaProtocolStateDefinition.
        """

        for _ in range(self._amount):
            self._accounts.append(self._account_params)

        return self._builder

    def with_token(
        self, address: str, amount: int, *, approve_max=True
    ) -> "AjnaUserStateDefinitionBuilder":
        """
        Adds token balance definition to AjnaUserDefinition.

        Args:
            address: address of ERC20 token contract
            amount: amount of token to be added to Ajna user
            approve_max: if True, Ajna user can pre-approve maximum amount of tokens to any Ajna Pool contract
        """
        self._account_params.token_balances.append(
            InitialUserTokenBalanceDefinition(address, amount, approve_max)
        )
        return self
