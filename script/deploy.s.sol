// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import { Script } from "forge-std/Script.sol";
import "forge-std/console.sol";

import { ERC20PoolFactory }      from 'src/ERC20PoolFactory.sol';
import { ERC721PoolFactory }     from 'src/ERC721PoolFactory.sol';
import { PoolInfoUtils }         from 'src/PoolInfoUtils.sol';
import { PoolInfoUtilsMulticall} from 'src/PoolInfoUtilsMulticall.sol';
import { PositionManager }       from 'src/PositionManager.sol';

contract Deploy is Script {
    address ajna;

    function run() public {
        ajna = vm.envAddress("AJNA_TOKEN");
        console.log("Deploying to chain with AJNA token address %s", ajna);

        vm.startBroadcast();
        ERC20PoolFactory       erc20factory           = new ERC20PoolFactory(ajna);
        ERC721PoolFactory      erc721factory          = new ERC721PoolFactory(ajna);
        PoolInfoUtils          poolInfoUtils          = new PoolInfoUtils();
        PoolInfoUtilsMulticall poolInfoUtilsMulticall = new PoolInfoUtilsMulticall(poolInfoUtils);
        PositionManager        positionManager        = new PositionManager(erc20factory, erc721factory);
        vm.stopBroadcast();

        console.log("=== Deployment addresses ===");
        console.log("ERC20PoolFactory       %s", address(erc20factory));
        console.log("ERC721PoolFactory      %s", address(erc721factory));
        console.log("PoolInfoUtils          %s", address(poolInfoUtils));
        console.log("PoolInfoUtilsMulticall %s", address(poolInfoUtilsMulticall));
        console.log("PositionManager        %s", address(positionManager));
    }
}
