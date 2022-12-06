#!/bin/bash

# TODO
# - store contract addresses in varibles
# - pass addresses using --libraries to deploy factories (see https://book.getfoundry.sh/reference/forge/forge-create)

read -p "Enter keystore password: " -s password

regex="Deployed to: ([0-9xa-fA-F]+)"
libraries=( Auctions LenderActions PoolCommons )

echo Deploying libraries...
for contract in "${libraries[@]}"
do
    createlib="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password} \
        src/libraries/external/$contract.sol:$contract"    
    output=$($createlib)
    if [[ $output =~ $regex ]]
    then
        echo Deployed $contract to ${BASH_REMATCH[1]}
    else
        echo $contract was not deployed: $output
    fi
done

# deploy factories
# factories=( ERC20PoolFactory ERC721PoolFactory )
forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password} \
    src/erc20/ERC20PoolFactory.sol:ERC20PoolFactory
