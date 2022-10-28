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

    dai_config = sdk_config.get('tokens').get('DAI')

    dai_contract = Contract(dai_config.get('address'))
    dai_reserve = accounts.at(dai_config.get('reserve'), True);

    mkr_config = sdk_config.get('tokens').get('MKR')

    mkr_contract = Contract(mkr_config.get('address'))
    mkr_reserve = accounts.at(mkr_config.get('reserve'), True);

    bored_ape_config = sdk_config.get('tokens').get('BAYC')
    ape_contract = Contract(bored_ape_config.get('address'))

    test_accounts = sdk_config.get('accounts')
    for addresses in test_accounts.items():
        address = addresses[0]

        balances = test_accounts.get(address)
        for token in balances:
            if token == 'DAI':
                balance = balances.get(token)
                print(f"=== Transfer {balance} DAI to {address} ===")
                dai_contract.transfer(address, balance * 1e18, {'from': dai_reserve})

            if token == 'MKR':
                balance = balances.get(token)
                print(f"=== Transfer {balance} MKR to {address} ===")
                mkr_contract.transfer(address, balance * 1e18, {'from': mkr_reserve})

            if token == 'BAYC':
                for tokenId in balances.get(token):         
                    print(f"=== Transfer Bored Ape {tokenId} to {address} ===")
                    ape_owner = accounts.at(ape_contract.ownerOf(tokenId), True);
                    ape_contract.transferFrom(ape_owner, address, tokenId, {'from': ape_owner})

