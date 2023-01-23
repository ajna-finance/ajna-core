// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.14;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import { TokensFactory } from "./test_token_factory/TokensFactory.sol";
import { ERC20Impl }     from "./test_token_factory/implementation/ERC20Impl.sol";
import { ERC721Impl }    from "./test_token_factory/implementation/ERC721Impl.sol";
import { ERC1155Impl }   from "./test_token_factory/implementation/ERC1155Impl.sol";


contract DeployTokensFactory is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        ERC20Impl erc20implementation = new ERC20Impl();
        address erc20implementationAddress = address(erc20implementation);

        ERC721Impl erc721implementation = new ERC721Impl();
        address erc721implementationAddress = address(erc721implementation);

        ERC1155Impl erc1155implementation = new ERC1155Impl();
        address erc1155implementationAddress = address(erc1155implementation);

        TokensFactory factory = new TokensFactory(erc20implementationAddress, erc721implementationAddress, erc1155implementationAddress);
        console.log("TokensFactory deployed to %s", address(factory));

        vm.stopBroadcast();
    }
}