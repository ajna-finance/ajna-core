import brownie
from brownie import Contract
import pytest
from decimal import *


# Calldata dependencies
from web3 import HTTPProvider, Web3
from web3._utils.contracts import get_function_info, encode_abi

class Calldata:
    def __init__(self, value):
        if isinstance(value, str):
            assert(value.startswith('0x'))
            self.value = value

        elif isinstance(value, bytes):
            self.value = bytes_to_hexstring(value)

        else:
            raise Exception(f"Unable to create calldata from '{value}'")

    @classmethod
    def from_contract_abi(cls, web3: Web3, fn_sign: str, fn_args: list, contract_abi):
        """ Create a `Calldata` according to the given contract abi """
        assert isinstance(web3, Web3)
        assert isinstance(fn_sign, str)
        assert isinstance(fn_args, list)

        fn_split = re.split('[(),]', fn_sign)
        fn_name = fn_split[0]

        fn_abi, fn_selector, fn_arguments = get_function_info(fn_name, abi_codec=web3.codec, contract_abi=contract_abi, args=fn_args)
        calldata = encode_abi(web3, fn_abi, fn_arguments, fn_selector)

        return cls(calldata)

def encode_calldata(self, web3: Web3, fn_signature: str, arguments: list, contract_abi) -> Calldata:
    """ encode inputted contract and methods with call arguments as pymaker.Calldata """
    assert isinstance(web3, Web3)
    assert isinstance(fn_signature, str)
    assert isinstance(arguments, list)

    return Calldata.from_contract_abi(web3, fn_signature, arguments, contract_abi)


# TODO: add web3 access and abi parsing

def test_mint(position_manager, lenders):
    mint_params = [
        lenders[0],
        lenders[1],
        50 * 1e18,
        1000 * 1e18
    ]

    # encoded_mint_params = encode_calldata(mint_params)

    token_id = position_manager.mint(mint_params)
    assert token_id != 0
