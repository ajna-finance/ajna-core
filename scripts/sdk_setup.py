from brownie import *
import json


def main():

    # deploy Ajna pool factories and dump them in json config file
    Deposits.deploy({"from": accounts[0]})
    BucketMath.deploy({"from": accounts[0]})
    erc20_pool_factory = ERC20PoolFactory.deploy({"from": accounts[0]})
    erc721_pool_factory = ERC721PoolFactory.deploy({"from": accounts[0]})
    dictionary = {
        "erc20factory": erc20_pool_factory.address,
        "erc721factory": erc721_pool_factory.address
    }
    
    with open("brownie_out/ajna-sdk.json", "w") as outfile:
        json.dump(dictionary, outfile, indent=4, sort_keys=True)

    # read config and fund accounts
    with open('scripts/sdk-setup.json', 'r') as setupfile:
        sdk_config = json.load(setupfile)

    dai_contract = Contract('0x6b175474e89094c44da98b954eedeac495271d0f')
    dai_reserve = accounts.at('0x616eFd3E811163F8fc180611508D72D842EA7D07', True);

    mkr_contract = Contract('0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2')
    mkr_reserve = accounts.at('0x0a3f6849f78076aefaDf113F5BED87720274dDC0', True);

    ape_contract = Contract('0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D')

    for addresses in sdk_config.items():
        address = addresses[0]

        balances = sdk_config.get(address)
        for token in balances:
            if token == 'DAI':
                balance = balances.get(token)
                print(f"=== Transfer {balance} DAI to {address} ===")
                dai_contract.transfer(address, balance * 1e18, {'from': dai_reserve})

            if token == 'MKR':
                balance = balances.get(token)
                print(f"=== Transfer {balance} MKR to {address} ===")
                mkr_contract.transfer(address, balance * 1e18, {'from': mkr_reserve})

            if token == 'BOREDAPE':
                for tokenId in balances.get(token):         
                    print(f"=== Transfer Bored Ape {tokenId} to {address} ===")
                    ape_owner = accounts.at(ape_contract.ownerOf(tokenId), True);
                    ape_contract.transferFrom(ape_owner, address, tokenId, {'from': ape_owner})

