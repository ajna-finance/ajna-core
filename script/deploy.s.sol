// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import { Script } from "forge-std/Script.sol";
import "forge-std/console.sol";

import { ERC20PoolFactory }  from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory } from 'src/ERC721PoolFactory.sol';
import { PoolInfoUtils }     from 'src/PoolInfoUtils.sol';
import { PositionManager }   from 'src/PositionManager.sol';
import { RewardsManager }    from 'src/RewardsManager.sol';

contract Deploy is Script {
    address ajna;

    function run() public {
        ajna = vm.envAddress("AJNA_TOKEN");
        console.log("Deploying to chain with AJNA token address %s", ajna);

        vm.startBroadcast();
        ERC20PoolFactory  erc20factory  = new ERC20PoolFactory(ajna);
        ERC721PoolFactory erc721factory = new ERC721PoolFactory(ajna);
        PoolInfoUtils   poolInfoUtils   = new PoolInfoUtils();

        PositionManager positionManager = new PositionManager(erc20factory, erc721factory);
        RewardsManager  rewardsManager  = new RewardsManager(ajna, positionManager);
        vm.stopBroadcast();

        console.log("=== Deployment addresses ===");
        console.log("ERC20  factory  %s", address(erc20factory));
        console.log("ERC721 factory  %s", address(erc721factory));
        console.log("PoolInfoUtils   %s", address(poolInfoUtils));
        console.log("PositionManager %s", address(positionManager));
        console.log("RewardsManager  %s", address(rewardsManager));
    }
}