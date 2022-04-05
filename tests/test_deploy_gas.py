import brownie
from brownie import Contract
import pytest
import inspect
from sdk import *


def test_deploy_gas(
    capsys,
    test_utils,
):
    with test_utils.GasWatcher():
        protocol_definition = (
            InitialProtocolStateBuilder()
            .add_token(MKR_ADDRESS, MKR_RESERVE_ADDRESS)
            .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
            .deploy_pool(MKR_ADDRESS, DAI_ADDRESS)
        )

        ajna_protocol = AjnaProtocol()
        ajna_protocol.get_runner().prepare_protocol_to_state_by_definition(
            protocol_definition.build()
        )

        with capsys.disabled():
            print("\n==================================")
            print(f"Gas estimations({inspect.stack()[0][3]}):")
            print("==================================")
