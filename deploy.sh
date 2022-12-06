#!/bin/bash

# TODO
# - interactively input password into variable, pass to each command
# - store contract addresses in varibles
# - pass addresses using --libraries to deploy factories (see https://book.getfoundry.sh/reference/forge/forge-create)

regex="Deployed to: ([0-9xa-fA-F]+)"
libraries=( Auctions BucketMath )

# deploy libraries
for contract in "${libraries[@]}"
do
    createlib="forge create --rpc-url ${ETH_RPC_URL:?} \
	    --keystore ${DEPLOY_KEY:?} src/libraries/$contract.sol:$contract"    
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
# forge create --rpc-url ${ETH_RPC_URL:?} \
#     --keystore ${DEPLOY_KEY:?} src/erc20/ERC20PoolFactory.sol:ERC20PoolFactory
