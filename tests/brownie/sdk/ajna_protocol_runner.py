import random

from brownie import *
from brownie import (
    Contract,
)

from .protocol_definition import *


class AjnaProtocolRunner:
    def __init__(self, protocol) -> None:
        self.protocol = protocol

    def prepare_protocol_to_state_by_definition(
        self, protocol_definition: InitialProtocolState = None
    ):
        """
        Prepares AjnaProtocol to desired state by given protocol definition defined in AjnaProtocolStateDefinition by hand or using AjnaProtocolStateDefinitionBuilder.

        For default prepares AjnaProtocol to:
            - creates a single Lender with 100 ETH and 0 tokens
            - creates a single Borrower with 100 ETH and 0 tokens
            - creates a MKR token wrapper
            - creates a DAI token wrapper
            - deploy single Pool for MKR and DAI pair

        Args:
            protocol_definition: AjnaProtocolStateDefinition
        """
        options = (
            protocol_definition
            if protocol_definition
            else InitialProtocolState.DEFAULT()
        )

        self.deploy_pools_according_by_definition(options)
        self.create_erc20_token_clients_by_definition(options)
        self.prepare_lenders_by_definition(protocol_definition)
        self.prepare_borrowers_by_definition(protocol_definition)

        self.perform_lenders_initial_pool_interactions_by_definition(
            protocol_definition
        )
        self.perform_borrowers_initial_pool_interactions_by_definition(
            protocol_definition
        )

    def create_erc20_token_clients_by_definition(
        self, protocol_definition: InitialProtocolState
    ):
        """
        Creates ERC20TokenClient for each tokens defined in protocol_definition.
        Token clients are used to simplify interaction with standard ERC20 tokens.
        Token clients define reserve account that can be used to top up token balance for any Ajna user.
        """
        for token_options in protocol_definition.tokens:
            self.protocol.add_token(
                token_options.token_address, token_options.reserve_address
            )

    def deploy_pools_according_by_definition(
        self, protocol_definition: InitialProtocolState
    ):
        """
        Deploys ERC20Pool for each pair of tokens defined in protocol_definition.
        """

        for pool_options in protocol_definition.deploy_pools:
            self.protocol.deploy_erc20_pool(
                pool_options.collateral_address, pool_options.quote_token_address
            )

    def prepare_borrowers_by_definition(self, protocol_definition: PoolsToDeploy):
        """
        Prepares Borrowers according to given protocol_definition.

        Each Borrower has 100 ETH.
        Each Borrower can have multiple ERC20 tokens.
        The initial amount of each ERC20 token is defined by protocol_definition.
        """

        for borrower_options in protocol_definition.borrowers:
            borrower = self.protocol.add_borrower()

            for token_options in borrower_options.token_balances:
                token = self.protocol.get_token(token_options.token_address)
                token.top_up(borrower, token_options.amount)

                if token_options.approve_max:
                    for pool in self.protocol.pools:
                        token.approve_max(pool.get_contract(), borrower)

    def prepare_lenders_by_definition(self, protocol_definition: InitialProtocolState):
        """
        Prepares Lenders according to given protocol_definition.

        Each Lender has 100 ETH.
        Each Lender can have multiple ERC20 tokens.
        The initial amount of each ERC20 token is defined by protocol_definition.
        """

        for lender_options in protocol_definition.lenders:
            lender = self.protocol.add_lender()

            for token_options in lender_options.token_balances:
                token = self.protocol.get_token(token_options.token_address)
                token.top_up(lender, token_options.amount)

                if token_options.approve_max:
                    for pool in self.protocol.pools:
                        token.approve_max(pool.get_contract(), lender)

    def perform_lenders_initial_pool_interactions_by_definition(
        self, protocol_definition: InitialProtocolState
    ):
        """
        Perform  initial lenders deposits for each pool defined in the protocol definition.
        """
        for lender, lender_index in enumerate(self.protocol.lenders):
            lender_options = protocol_definition.lenders[lender]
            self._perform_initial_pool_interactions_for_lender(
                lender_options, lender_index
            )

    def perform_borrowers_initial_pool_interactions_by_definition(
        self, protocol_definition: InitialProtocolState
    ):
        """
        Perform  initial borrowers deposits for each pool defined in the protocol definition.
        """
        for borrower, borrower_index in enumerate(self.protocol.borrowers):
            borrower_options = protocol_definition.borrowers[borrower]
            self._perform_initial_pool_interactions_for_borrower(
                borrower_options, borrower_index
            )

    def _perform_initial_pool_interactions_for_lender(
        self, lender_options: PoolInteractions, lender_index: int
    ):
        """
        Performs initial quote token deposits for each pool defined in .
        """
        for interactions in lender_options.pool_interactions:
            pool = self.protocol.get_pool(
                interactions.collateral_address, interactions.quote_token_address
            )

            for quote_deposits_definition in interactions.quote_deposits:
                min_amount = quote_deposits_definition.min_deposit_amount
                max_amount = quote_deposits_definition.max_deposit_amount
                amount = random.randrange(min_amount, max_amount)

                min_price_index = quote_deposits_definition.min_deposit_price_index
                max_price_index = quote_deposits_definition.max_deposit_price_index
                price_index = random.randrange(min_price_index, max_price_index)
                price = self.protocol.bucket_math.indexToPrice(price_index)

                pool.deposit_quote_token(amount, price, lender_index)

    def _perform_initial_pool_interactions_for_borrower(
        self, borrower_options: PoolInteractions, borrower_index: int
    ):
        for interactions in borrower_options.pool_interactions:
            pool = self.protocol.get_pool(
                interactions.collateral_address, interactions.quote_token_address
            )
            for collateral_deposits_definition in interactions.collateral_deposits:
                min_amount = collateral_deposits_definition.min_deposit_amount
                max_amount = collateral_deposits_definition.max_deposit_amount

                amount = random.randint(min_amount, max_amount)
                pool.deposit_collateral_token(amount, borrower_index)
