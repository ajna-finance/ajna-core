#!/bin/bash

# load environment variables from .env file
set -o allexport
source .env
set +o allexport

echo Deploying to chain with AJNA token address ${AJNA_TOKEN:?}

read -p "Enter keystore password: " -s password

regex="Deployed to: ([0-9xa-fA-F]+)"
linkage=()

echo
echo Deploying libraries...
libraries=( Auctions LenderActions BorrowerActions PoolCommons PositionNFTSVG )
for contract in "${libraries[@]}"
do
    createlib="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password:?} \
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
factories=( 'erc20,ERC20PoolFactory' 'erc721,ERC721PoolFactory' )
for contract in "${factories[@]}"
do
    IFS=',' read -r -a arr <<< ${contract}
    dir=${arr[0]}
    name=${arr[1]}
    createfactory="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password:?} \
        src/$dir/$name.sol:$name --constructor-args ${AJNA_TOKEN:?} ${linkage}"
    output=$($createfactory)
    if [[ $output =~ $regex ]]
    then
        address=${BASH_REMATCH[1]}
        printf "Deployed %20s to %s\n" ${name:0:20} $address
    else
        echo $name was not deployed: $output
        exit 2
    fi
done

echo Deploying PoolInfoUtils...
contract=PoolInfoUtils
create="forge create --rpc-url ${ETH_RPC_URL:?} --keystore ${DEPLOY_KEY:?} --password ${password:?} \
    src/base/$contract.sol:$contract ${linkage}"
output=$($create)
if [[ $output =~ $regex ]]
then
    address=${BASH_REMATCH[1]}
    printf "Deployed %20s to %s\n" ${contract:0:20} $address
else
    echo $contract was not deployed: $output
    exit 1
fi