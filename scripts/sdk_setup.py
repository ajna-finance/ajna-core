from brownie import *
import json


def main():

    # deploy Ajna pool factories and dump them in json config file
    Deposits.deploy({"from": accounts[0]})
    BucketMath.deploy({"from": accounts[0]})
    erc20_pool_factory = ERC20PoolFactory.deploy({"from": accounts[0]})
    erc721_pool_factory = ERC721PoolFactory.deploy({"from": accounts[0]})

    with open("scripts/.env", "w") as outfile:
        outfile.write("ETH_RPC_URL=http://localhost:8545/")
        outfile.write("\nPRIVATE_KEY=0xacd5fc4b1c3141f67b35f09210379295c34f7e5c33d6bf1755a65c3c07a9e854")
        outfile.write("\nERC20_FACTORY="+erc20_pool_factory.address)
        outfile.write("\nERC721_FACTORY="+erc721_pool_factory.address)
        outfile.write("\nCOMP=0xc00e94Cb662C3520282E6f5717214004A7f26888")
        outfile.write("\nDAI=0x6B175474E89094C44Da98b954EedeAC495271d0F")

    # read config and fund accounts
    with open('scripts/sdk-setup.json', 'r') as setupfile:
        sdk_config = json.load(setupfile)

    dai_config = sdk_config.get('tokens').get('DAI')

    dai_contract = Contract(dai_config.get('address'))
    dai_reserve = accounts.at(dai_config.get('reserve'), True);

    comp_config = sdk_config.get('tokens').get('COMP')

    comp_contract = Contract(comp_config.get('address'))
    comp_reserve = accounts.at(comp_config.get('reserve'), True);

    bored_ape_config = sdk_config.get('tokens').get('BAYC')
    ape_contract = Contract(bored_ape_config.get('address'))

    test_accounts = sdk_config.get('accounts')
    for addresses in test_accounts.items():
        address = addresses[0]
        accounts[0].transfer(address, 100 * 1e18)

        balances = test_accounts.get(address)
        for token in balances:
            if token == 'DAI':
                balance = balances.get(token)
                print(f"=== Transfer {balance} DAI to {address} ===")
                dai_contract.transfer(address, balance * 1e18, {'from': dai_reserve})

            if token == 'COMP':
                balance = balances.get(token)
                print(f"=== Transfer {balance} COMP to {address} ===")
                comp_contract.transfer(address, balance * 1e18, {'from': comp_reserve})

            if token == 'BAYC':
                for tokenId in balances.get(token):         
                    print(f"=== Transfer Bored Ape {tokenId} to {address} ===")
                    ape_owner = accounts.at(ape_contract.ownerOf(tokenId), True);
                    ape_contract.transferFrom(ape_owner, address, tokenId, {'from': ape_owner})
    
    return (
        erc20_pool_factory,
        erc721_pool_factory,
        comp_contract,
        dai_contract,
    )


