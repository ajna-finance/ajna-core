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


class AjnaProtocolRunner:
    def __init__(self, protocol) -> None:
        self.protocol = protocol

    def prepare_protocol_to_state_by_definition(self, protocol_definition):
        options = (
            protocol_definition
            if protocol_definition
            else AjnaProtocolDefinition.DEFAULT()
        )

        self.deploy_pools_according_by_definition(options)
        self.create_erc20_token_clients_by_definition(options)
        self.prepare_lenders_by_definition(protocol_definition)
        self.prepare_borrowers_by_definition(protocol_definition)

    def create_erc20_token_clients_by_definition(self, protocol_definition):
        for token_options in protocol_definition.tokens:
            self.protocol.add_token(
                token_options.token_address, token_options.reserve_address
            )

    def deploy_pools_according_by_definition(self, protocol_definition):
        for pool_options in protocol_definition.deploy_pools:
            self.protocol.deploy_erc20_pool(
                pool_options.collateral_address, pool_options.quote_token_address
            )

    def prepare_borrowers_by_definition(self, protocol_definition):
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
        for lender_options in protocol_definition.lenders:
            lender = self.protocol.add_lender()

            for token_options in lender_options.token_balances:
                token = self.protocol.get_token(token_options.token_address)
                token.top_up(lender, token_options.amount)

                if token_options.approve_max:
                    for pool in self.protocol.pools:
                        token.approve_max(pool.get_contract(), lender)

            self.protocol.lenders.append(lender)
