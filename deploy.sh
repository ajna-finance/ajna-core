#!/bin/bash

read -p "Enter keystore password: " -s password

regex="Deployed to: ([0-9xa-fA-F]+)"
linkage=()

echo
echo Deploying libraries...
libraries=( Auctions LenderActions PoolCommons )
for contract in "${libraries[@]}"
do
    createlib="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password} \
        src/libraries/external/$contract.sol:$contract"    
    output=$($createlib)
    if [[ $output =~ $regex ]]
    then
        address=${BASH_REMATCH[1]}
        printf "Deployed %20s to %s\n" ${contract:0:20} $address
        linkage+="--libraries src/libraries/external/$contract.sol:$contract:$address "
    else
        echo $contract was not deployed: $output
        exit 1
    fi
done

echo Deploying factories...
factories=( ERC20PoolFactory ERC721PoolFactory )
for contract in "${factories[@]}"
do
    createfactory="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password} \
        src/erc20/ERC20PoolFactory.sol:ERC20PoolFactory ${linkage}"
    output=$($createfactory)
    if [[ $output =~ $regex ]]
    then
        address=${BASH_REMATCH[1]}
        printf "Deployed %20s to %s\n" ${contract:0:20} $address
    else
        echo $contract was not deployed: $output
        exit 2
    fi
done
