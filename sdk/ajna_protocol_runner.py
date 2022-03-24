from typing import List

from brownie import *
from brownie import (
    Contract,
)

from .protocol_definition import *


class AjnaProtocolRunner:
    def __init__(self, protocol) -> None:
        self.protocol = protocol

    def prepare_protocol_to_state_by_definition(
        self, protocol_definition: AjnaProtocolStateDefinition = None
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
            else AjnaProtocolStateDefinition.DEFAULT()
        )

        self.deploy_pools_according_by_definition(options)
        self.create_erc20_token_clients_by_definition(options)
        self.prepare_lenders_by_definition(protocol_definition)
        self.prepare_borrowers_by_definition(protocol_definition)

    def create_erc20_token_clients_by_definition(self, protocol_definition):
        """
        Creates ERC20TokenClient for each tokens defined in protocol_definition.
        Token clients are used to simplify interaction with standard ERC20 tokens.
        Token clients define reserve account that can be used to top up token balance for any Ajna user.
        """
        for token_options in protocol_definition.tokens:
            self.protocol.add_token(
                token_options.token_address, token_options.reserve_address
            )

    def deploy_pools_according_by_definition(self, protocol_definition):
        """
        Deploys ERC20Pool for each pair of tokens defined in protocol_definition.
        """

        for pool_options in protocol_definition.deploy_pools:
            self.protocol.deploy_erc20_pool(
                pool_options.collateral_address, pool_options.quote_token_address
            )

    def prepare_borrowers_by_definition(self, protocol_definition):
        """
        Prepares Borrowers according to given protocol_definition.

        Each Borrower has 100 ETH.
        Each Borrower can have multiple ERC20 tokens.
        The initial amount of each ERC20 token is defined by protocol_definition.
        Using `approve_max` allows Borrower to pre-approve maximum amount of tokens to any Ajna Pool contract.
        """

        for borrower_options in protocol_definition.borrowers:
            borrower = self.protocol.add_borrower()

            for token_options in borrower_options.token_balances:
                token = self.protocol.get_token(token_options.token_address)
                token.top_up(borrower, token_options.amount)

                if token_options.approve_max:
                    for pool in self.protocol.pools:
                        token.approve_max(pool.get_contract(), borrower)

            self.protocol.borrowers.append(borrower)

    def prepare_lenders_by_definition(self, protocol_definition):
        """
        Prepares Lenders according to given protocol_definition.

        Each Lender has 100 ETH.
        Each Lender can have multiple ERC20 tokens.
        The initial amount of each ERC20 token is defined by protocol_definition.
        Using `approve_max` allows Lender to pre-approve maximum amount of tokens to any Ajna Pool contract.
        """

        for lender_options in protocol_definition.lenders:
            lender = self.protocol.add_lender()

            for token_options in lender_options.token_balances:
                token = self.protocol.get_token(token_options.token_address)
                token.top_up(lender, token_options.amount)

                if token_options.approve_max:
                    for pool in self.protocol.pools:
                        token.approve_max(pool.get_contract(), lender)

            self.protocol.lenders.append(lender)
