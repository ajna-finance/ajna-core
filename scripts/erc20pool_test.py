from brownie import *
import json


def main():

    # deploy Ajna pool factories and dump them in json config file
    Deposits.deploy({"from": accounts[0]})
    PoolCommons.deploy({"from": accounts[0]})
    LenderActions.deploy({"from": accounts[0]})
    BorrowerActions.deploy({"from": accounts[0]})
    Auctions.deploy({"from": accounts[0]})
    erc20_pool_factory = ERC20PoolFactory.deploy({"from": accounts[0]})

    # read config and fund accounts
    with open('scripts/ajna-setup.json', 'r') as setupfile:
        ajna_config = json.load(setupfile)

    dai_config = ajna_config.get('tokens').get('DAI')

    dai_contract = Contract(dai_config.get('address'))
    dai_reserve = accounts.at(dai_config.get('reserve'), True);

    comp_config = ajna_config.get('tokens').get('COMP')

    comp_contract = Contract(comp_config.get('address'))
    comp_reserve = accounts.at(comp_config.get('reserve'), True);

    test_accounts = ajna_config.get('accounts')
    erc20_pool_factory.deployPool(comp_contract, dai_contract, 0.05 * 1e18, {"from": accounts[0]})
    erc20pool = ERC20Pool.at(erc20_pool_factory.deployedPools("2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2", comp_contract, dai_contract))
    poolInfo = PoolInfoUtils.deploy({"from": accounts[0]})
    for addresses in test_accounts.items():
        address = addresses[0]
        accounts[0].transfer(address, 20 * 1e18)

        balances = test_accounts.get(address)
        for token in balances:
            if token == 'DAI':
                balance = balances.get(token)
                print(f"=== Transfer {balance} DAI to {address} ===")
                dai_contract.transfer(address, balance * 1e18, {'from': dai_reserve})
                dai_contract.approve(erc20pool, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, {'from': accounts.at(address, True)})

            if token == 'COMP':
                balance = balances.get(token)
                print(f"=== Transfer {balance} COMP to {address} ===")
                comp_contract.transfer(address, balance * 1e18, {'from': comp_reserve})
                comp_contract.approve(erc20pool, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, {'from': accounts.at(address, True)})
    
    print(f"Pool address: {erc20pool.address}")
    print(f"Utils address: {poolInfo.address}")
    
    return (
        erc20pool,
        poolInfo,
    )